{
  config,
  lib,
  pkgs,
}:

with lib;

let
  cfg = config.fleet.media.stack;
  appdata = cfg.appdataRoot;
  gluetunCfg = cfg.gluetun;
  mediaRoot = cfg.mediaRoot;
  mediaGluetunRouteUrls = map (
    serviceDomain: "http://gluetun.media.${serviceDomain}"
  ) cfg.serviceDomains;
  smbCredentialsFile =
    if cfg.secrets.enable then
      config.sops.secrets.smb-credentials.path
    else
      "/run/secrets/smb-credentials";
  resticPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.restic-password.path
    else
      "/run/secrets/restic-password";
  audiobookshelfExecStart = concatStringsSep " " [
    "${pkgs.audiobookshelf}/bin/audiobookshelf"
    "--host 0.0.0.0"
    "--port ${toString cfg.ports.audiobookshelf}"
    "--config ${appdata}/audiobookshelf/config"
    "--metadata ${appdata}/audiobookshelf/metadata"
  ];
  qbittorrentWebuiPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.qbittorrent-webui-password.path
    else
      "/run/secrets/qbittorrent-webui-password";
  qbittorrentWebuiUsernameFile =
    if cfg.secrets.enable then
      config.sops.secrets.qbittorrent-webui-username.path
    else
      "/run/secrets/qbittorrent-webui-username";
  mediaGluetunControlApiKeyFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-control-api-key.path
    else
      "/run/secrets/media-gluetun-control-api-key";
  mediaGluetunOpenvpnPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-openvpn-password.path
    else
      "/run/secrets/media-gluetun-openvpn-password";
  mediaGluetunOpenvpnUsernameFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-openvpn-username.path
    else
      "/run/secrets/media-gluetun-openvpn-username";
  gluetunControlAuthConfigDir = "/run/media-gluetun-control-server";
  gluetunControlAuthConfigFile = "${gluetunControlAuthConfigDir}/config.toml";
  gluetunControlWebUiEnvFile = "${gluetunControlAuthConfigDir}/webui.env";
  systemdMountOptions = filter (
    option:
    option != "_netdev" && option != "noauto" && option != "nofail" && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;
  gluetunInputPorts =
    optional gluetunCfg.qbittorrentWebUi.enable cfg.ports.qbittorrent
    ++ [ cfg.ports.sabnzbd ]
    ++ optional gluetunCfg.webUi.enable gluetunCfg.webUi.port;
  sabnzbdHostWhitelist = map (serviceDomain: "sabnzbd.${serviceDomain}") cfg.serviceDomains;

  appsdataDirs = [
    "${appdata}"
    "${appdata}/audiobookshelf"
    "${appdata}/audiobookshelf/config"
    "${appdata}/audiobookshelf/metadata"
    "${appdata}/flaresolverr"
    "${appdata}/gluetun"
    "${appdata}/monitoring"
    "${appdata}/qbittorrent"
    "${appdata}/sabnzbd"
    "${appdata}/seerr"
  ];
  downloadTempDirs = [
    "${cfg.downloads.incomplete}"
  ];

  sabnzbdConfigScript = pkgs.writeShellScript "configure-sabnzbd" ''
    set -euo pipefail

    exec ${
      pkgs.python3.withPackages (pythonPackages: [ pythonPackages.configobj ])
    }/bin/python3 - <<'PY'
    import os
    import pathlib
    import pwd
    import grp
    import tempfile

    from configobj import ConfigObj

    config_file = pathlib.Path(${builtins.toJSON "${appdata}/sabnzbd/sabnzbd.ini"})
    managed_misc = {
        "host": "0.0.0.0",
        "port": ${builtins.toJSON (toString cfg.ports.sabnzbd)},
        "download_dir": ${builtins.toJSON (toString cfg.downloads.incomplete)},
        "complete_dir": ${builtins.toJSON (toString cfg.downloads.usenet)},
    }
    required_hosts = ${builtins.toJSON sabnzbdHostWhitelist}

    config_file.parent.mkdir(parents=True, exist_ok=True)
    config = ConfigObj(str(config_file), encoding="UTF8") if config_file.exists() else ConfigObj(encoding="UTF8")
    if "misc" not in config:
        config["misc"] = {}

    misc = config["misc"]
    for key, value in managed_misc.items():
        misc[key] = value

    host_whitelist = misc.get("host_whitelist", "")
    if isinstance(host_whitelist, list):
        hosts = [str(host).strip() for host in host_whitelist]
    else:
        hosts = [host.strip() for host in str(host_whitelist).split(",")]
    hosts = [host for host in hosts if host]
    for required_host in required_hosts:
        if required_host not in hosts:
            hosts.append(required_host)
    misc["host_whitelist"] = ",".join(hosts)

    uid = pwd.getpwnam("sabnzbd").pw_uid
    gid = grp.getgrnam("media").gr_gid
    fd, tmp_name = tempfile.mkstemp(prefix=".sabnzbd.ini.", dir=config_file.parent)
    os.close(fd)
    try:
        config.filename = tmp_name
        config.write()
        if os.geteuid() == 0:
            os.chown(tmp_name, uid, gid)
        os.chmod(tmp_name, 0o640)
        os.replace(tmp_name, config_file)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
    PY
  '';

  qbittorrentConfigScript = pkgs.writeShellScript "configure-qbittorrent" ''
    set -euo pipefail

    exec ${pkgs.python3}/bin/python3 - <<'PY'
    import base64
    import hashlib
    import os
    import pathlib
    import pwd
    import grp
    import tempfile

    config_dir = pathlib.Path(${builtins.toJSON "${appdata}/qbittorrent/qBittorrent"})
    config_file = config_dir / "qBittorrent.conf"
    legacy_config_dir = config_dir / "config"
    legacy_config_file = legacy_config_dir / "qBittorrent.conf"
    username_file = pathlib.Path(${builtins.toJSON qbittorrentWebuiUsernameFile})
    password_file = pathlib.Path(${builtins.toJSON qbittorrentWebuiPasswordFile})

    def read_secret(path, name):
        value = path.read_text(encoding="utf-8").rstrip("\n")
        if not value:
            raise RuntimeError(f"qBittorrent WebUI {name} secret is empty: {path}")
        if "\n" in value or "\r" in value:
            raise RuntimeError(f"qBittorrent WebUI {name} secret must be a single line: {path}")
        return value

    username = read_secret(username_file, "username")
    password = read_secret(password_file, "password")

    salt = os.urandom(16)
    password_hash = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, 100000)
    encoded_salt = base64.b64encode(salt).decode("ascii")
    encoded_hash = base64.b64encode(password_hash).decode("ascii")

    content = f"""[LegalNotice]
    Accepted=true

    [Preferences]
    Downloads\\SavePath=${cfg.downloads.torrents}
    Downloads\\TempPath=${cfg.downloads.incomplete}
    Downloads\\TempPathEnabled=true
    WebUI\\Address=*
    WebUI\\Password_PBKDF2="@ByteArray({encoded_salt}:{encoded_hash})"
    WebUI\\Port=${toString cfg.ports.qbittorrent}
    WebUI\\Username={username}
    """

    config_dir.mkdir(parents=True, exist_ok=True)
    legacy_config_dir.mkdir(parents=True, exist_ok=True)
    uid = pwd.getpwnam("qbittorrent").pw_uid
    gid = grp.getgrnam("media").gr_gid

    for runtime_path in [
        config_dir / "ipc-socket",
        config_dir / "lockfile",
        config_dir / "qBittorrent-data.conf.lock",
    ]:
        try:
            runtime_path.unlink()
        except FileNotFoundError:
            pass

    def write_config(path):
        fd, tmp_name = tempfile.mkstemp(prefix=".qBittorrent.conf.", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as tmp:
                tmp.write(content)
            os.chown(tmp_name, uid, gid)
            os.chmod(tmp_name, 0o600)
            os.replace(tmp_name, path)
        finally:
            try:
                os.unlink(tmp_name)
            except FileNotFoundError:
                pass

    write_config(config_file)
    write_config(legacy_config_file)
    PY
  '';
in
{
  inherit
    appdata
    appsdataDirs
    audiobookshelfExecStart
    cfg
    downloadTempDirs
    gluetunCfg
    gluetunControlAuthConfigDir
    gluetunControlAuthConfigFile
    gluetunControlWebUiEnvFile
    gluetunInputPorts
    mediaGluetunRouteUrls
    mediaRoot
    qbittorrentConfigScript
    resticPasswordFile
    sabnzbdConfigScript
    smbCredentialsFile
    systemdMountOptions
    ;
}
