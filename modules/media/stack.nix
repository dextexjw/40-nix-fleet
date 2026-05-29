{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.media.stack;
  appdata = cfg.appdataRoot;
  gluetunCfg = cfg.gluetun;
  mediaRoot = cfg.mediaRoot;
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
    option != "_netdev"
    && option != "noauto"
    && option != "nofail"
    && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;
  gluetunInputPorts =
    optional gluetunCfg.qbittorrentWebUi.enable cfg.ports.qbittorrent
    ++ [ cfg.ports.sabnzbd ]
    ++ optional gluetunCfg.webUi.enable gluetunCfg.webUi.port;

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

    exec ${pkgs.python3.withPackages (pythonPackages: [ pythonPackages.configobj ])}/bin/python3 - <<'PY'
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
    required_host = "sabnzbd.h"

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
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.media.stack = {
    enable = mkEnableOption "media-vm Jellyfin and ARR stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    mediaRoot = mkOption {
      type = types.path;
      default = "/mnt/media";
      description = "Mounted media library root.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use sops-nix secrets from secrets/secrets.yaml.";
    };

    libraries = mkOption {
      type = types.attrsOf types.path;
      default = {
        audiobooks = "/mnt/media/Audiobooks";
        books = "/mnt/media/Books";
        calibre = "/mnt/media/Books";
        comics = "/mnt/media/Comics";
        kidsMovies = "/mnt/media/KidsMedia/KidsMovies";
        kidsTv = "/mnt/media/KidsMedia/KidsTVshows";
        movies = "/mnt/media/MOVIES";
        newMovies = "/mnt/media/NewMovies";
        pdfs = "/mnt/media/PDFs";
        podcasts = "/mnt/media/Podcasts";
        tv = "/mnt/media/TVshows";
      };
      description = "Media library paths.";
    };

    downloads = mkOption {
      type = types.attrsOf types.path;
      default = {
        incomplete = "/var/lib/media-downloads";
        root = "/mnt/media/downloads";
        torrents = "/mnt/media/downloads";
        usenet = "/mnt/media/downloads";
      };
      description = "Download paths for torrent and Usenet clients.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        audiobookshelf = 8000;
        bazarr = 6767;
        jellyfin = 8096;
        kavita = 5000;
        prowlarr = 9696;
        qbittorrent = 8080;
        radarr = 7878;
        sabnzbd = 8085;
        seerr = 5055;
        sonarr = 8989;
      };
      description = "Web UI ports for exposed media services.";
    };

    jellyfin.publishedServerUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional URL Jellyfin advertises to clients during auto-discovery.";
    };

    qbittorrent.image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/qbittorrent@sha256:715d2bfbcf1cd3d734cbbd4fbd599eb7ea0642eaa079a372dd0d343f59516700";
      description = "Pinned qBittorrent OCI image reference.";
    };

    sabnzbd.image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/sabnzbd@sha256:6b392fce45ed587ba7213259fbce6f9f725b157b746b36ec53d3f08ee415602e";
      description = "Pinned SABnzbd OCI image reference.";
    };

    gluetun = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route MediaVM download clients through a dedicated Gluetun container.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address used for MediaVM Gluetun-published service ports.";
      };

      controlServer = {
        apiKeyFile = mkOption {
          type = types.path;
          default = mediaGluetunControlApiKeyFile;
          description = "Runtime secret file containing the MediaVM Gluetun control server API key.";
        };

        port = mkOption {
          type = types.port;
          default = 8000;
          description = "Container-only Gluetun HTTP control server port.";
        };
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/qdm12/gluetun@sha256:2f33c71e5e164fcd51a962cb950134df25155593edf0c3e1201f888d027049b4";
        description = "Pinned Gluetun OCI image reference.";
      };

      openvpnPasswordFile = mkOption {
        type = types.path;
        default = mediaGluetunOpenvpnPasswordFile;
        description = "Runtime secret file containing the MediaVM PIA OpenVPN password.";
      };

      openvpnUsernameFile = mkOption {
        type = types.path;
        default = mediaGluetunOpenvpnUsernameFile;
        description = "Runtime secret file containing the MediaVM PIA OpenVPN username.";
      };

      provider = mkOption {
        type = types.str;
        default = "private internet access";
        description = "Gluetun VPN service provider name.";
      };

      qbittorrentWebUi.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Publish qBittorrent WebUI through the MediaVM Gluetun container.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "/srv/appsdata/gluetun";
        description = "Persistent MediaVM Gluetun state directory.";
      };

      vpnPortForwarding = mkOption {
        type = types.bool;
        default = false;
        description = "Enable PIA VPN port forwarding.";
      };

      vpnType = mkOption {
        type = types.enum [ "openvpn" ];
        default = "openvpn";
        description = "Gluetun VPN protocol.";
      };

      webUi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Run the MediaVM Gluetun WebUI sidecar container.";
        };

        image = mkOption {
          type = types.str;
          default = "docker.io/scuzza/gluetun-webui@sha256:7f38c188ada9b21b585dcb28175c3d74e64c12d959bd979b7f106e4240f6c807";
          description = "Pinned Gluetun WebUI OCI image reference.";
        };

        name = mkOption {
          type = types.str;
          default = "MediaVM Gluetun";
          description = "Display name for the MediaVM Gluetun instance.";
        };

        port = mkOption {
          type = types.port;
          default = 3001;
          description = "Host and container port for the MediaVM Gluetun WebUI.";
        };

        trustProxy = mkOption {
          type = types.bool;
          default = false;
          description = "Allow Gluetun WebUI to trust reverse proxy forwarding headers.";
        };
      };
    };

    smb = {
      mediaDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/media";
        description = "SMB device for the media share.";
      };

      backupDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/backups";
        description = "SMB device for the backup share.";
      };

      backupMount = mkOption {
        type = types.path;
        default = "/mnt/backups";
        description = "Backup SMB mount point.";
      };

      mountOptions = mkOption {
        type = types.listOf types.str;
        default = [
          "vers=3.0"
          "noauto"
          "nofail"
          "x-systemd.automount"
          "x-systemd.after=network-online.target"
          "x-systemd.idle-timeout=60"
          "x-systemd.mount-timeout=30s"
          "x-systemd.requires=network-online.target"
          "_netdev"
        ];
        description = "Systemd-aware CIFS mount options.";
      };
    };

    backup = {
      repository = mkOption {
        type = types.path;
        default = "/mnt/backups/restic/appdata/media-stack-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by appsdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/appsdata-restore-check";
        description = "Temporary target used by appsdata-restore-check.service.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = gluetunCfg.enable;
        message = "fleet.media.stack.gluetun.enable must stay true because qBittorrent is routed through MediaVM Gluetun.";
      }
    ];

    # --------------------------------------------------------------------------
    # USERS, GROUPS, AND DIRECTORIES
    # --------------------------------------------------------------------------

    boot.supportedFilesystems.cifs = true;
    boot.kernelModules = [ "tun" ];

    users.groups.media = {
      gid = 992;
    };

    users.users.media = {
      isSystemUser = true;
      group = "media";
      home = appdata;
    };

    users.users.qbittorrent = {
      isSystemUser = true;
      uid = 988;
      group = "media";
      home = "${appdata}/qbittorrent";
    };

    users.users.sabnzbd = {
      isSystemUser = true;
      uid = 38;
      group = "media";
      home = "${appdata}/sabnzbd";
    };

    users.users.seerr = {
      isSystemUser = true;
      group = "media";
      home = "${appdata}/seerr";
    };

    users.users.kavita.extraGroups = [ "media" ];

    systemd.tmpfiles.rules =
      (map (path: "d '${path}' 0770 root media - -") appsdataDirs)
      ++ (map (path: "d '${path}' 0770 root media - -") downloadTempDirs);
    systemd.tmpfiles.settings."10-prowlarr"."${appdata}/prowlarr".d = {
      group = mkForce "nogroup";
      mode = mkForce "0700";
      user = mkForce "nobody";
    };

    # --------------------------------------------------------------------------
    # SMB MOUNTS
    # --------------------------------------------------------------------------

    systemd.automounts = [
      {
        where = toString cfg.smb.backupMount;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
      {
        where = toString mediaRoot;
        wantedBy = [ "multi-user.target" ];
      }
    ];

    systemd.mounts = [
      {
        description = "Backup SMB share";
        what = cfg.smb.backupDevice;
        where = toString cfg.smb.backupMount;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0750"
            "file_mode=0640"
            "forcegid"
            "gid=media"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
      {
        description = "Media SMB share";
        what = cfg.smb.mediaDevice;
        where = toString mediaRoot;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0775"
            "file_mode=0664"
            "forcegid"
            "forceuid"
            "gid=media"
            "uid=media"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
    ];

    # --------------------------------------------------------------------------
    # MEDIA SERVICES
    # --------------------------------------------------------------------------

    services.jellyfin = {
      enable = true;
      openFirewall = true;
      user = "jellyfin";
      group = "media";
      dataDir = "${appdata}/jellyfin";
      configDir = "${appdata}/jellyfin/config";
      cacheDir = "${appdata}/jellyfin/cache";
      logDir = "${appdata}/jellyfin/log";
    };

    services.audiobookshelf = {
      enable = true;
      user = "audiobookshelf";
      group = "media";
      dataDir = "audiobookshelf";
      host = "0.0.0.0";
      port = cfg.ports.audiobookshelf;
    };

    services.kavita = {
      enable = true;
      dataDir = "${appdata}/kavita";
      tokenKeyFile = "${appdata}/kavita/config/token.key";
      settings = {
        IpAddresses = "0.0.0.0";
        Port = cfg.ports.kavita;
      };
    };

    services.radarr = {
      enable = true;
      user = "radarr";
      group = "media";
      dataDir = "${appdata}/radarr";
      settings.server.port = cfg.ports.radarr;
    };

    services.sonarr = {
      enable = true;
      user = "sonarr";
      group = "media";
      dataDir = "${appdata}/sonarr";
      settings.server.port = cfg.ports.sonarr;
    };

    services.prowlarr = {
      enable = true;
      dataDir = "${appdata}/prowlarr";
      settings.server.port = cfg.ports.prowlarr;
    };

    services.bazarr = {
      enable = true;
      user = "bazarr";
      group = "media";
      dataDir = "${appdata}/bazarr";
      listenPort = cfg.ports.bazarr;
    };

    services.seerr = {
      enable = true;
      port = cfg.ports.seerr;
      configDir = "${appdata}/seerr";
    };

    services.flaresolverr = {
      enable = true;
      port = 8191;
    };

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers = {
      media-gluetun = {
        image = gluetunCfg.image;
        pull = "missing";

        capabilities.NET_ADMIN = true;
        devices = [
          "/dev/net/tun:/dev/net/tun"
        ];

        environment = {
          FIREWALL_OUTBOUND_SUBNETS = "10.2.20.0/24";
          HTTP_CONTROL_SERVER_ADDRESS = ":${toString gluetunCfg.controlServer.port}";
          HTTP_CONTROL_SERVER_AUTH_CONFIG_FILEPATH = "/run/media-gluetun-control-server/config.toml";
          HTTPPROXY = "off";
          OPENVPN_PASSWORD_SECRETFILE = "/run/secrets/openvpn_password";
          OPENVPN_USER_SECRETFILE = "/run/secrets/openvpn_user";
          TZ = config.time.timeZone;
          VPN_PORT_FORWARDING = if gluetunCfg.vpnPortForwarding then "on" else "off";
          VPN_SERVICE_PROVIDER = gluetunCfg.provider;
          VPN_TYPE = gluetunCfg.vpnType;
        } // optionalAttrs (gluetunInputPorts != [ ]) {
          FIREWALL_INPUT_PORTS = concatMapStringsSep "," toString gluetunInputPorts;
        };

        ports =
          optionals gluetunCfg.qbittorrentWebUi.enable [
            "${gluetunCfg.bindAddress}:${toString cfg.ports.qbittorrent}:${toString cfg.ports.qbittorrent}/tcp"
          ]
          ++ [
            "${gluetunCfg.bindAddress}:${toString cfg.ports.sabnzbd}:${toString cfg.ports.sabnzbd}/tcp"
          ]
          ++ optionals gluetunCfg.webUi.enable [
            "${gluetunCfg.bindAddress}:${toString gluetunCfg.webUi.port}:${toString gluetunCfg.webUi.port}/tcp"
          ];

        podman.sdnotify = "healthy";

        extraOptions = [
          "--health-cmd=/gluetun-entrypoint healthcheck"
          "--health-interval=5s"
          "--health-retries=1"
          "--health-start-period=10s"
          "--health-timeout=5s"
        ];

        volumes = [
          "${gluetunCfg.stateDir}:/gluetun"
          "${gluetunCfg.openvpnUsernameFile}:/run/secrets/openvpn_user:ro"
          "${gluetunCfg.openvpnPasswordFile}:/run/secrets/openvpn_password:ro"
          "${gluetunControlAuthConfigFile}:/run/media-gluetun-control-server/config.toml:ro"
        ];
      };

      media-qbittorrent = {
        image = cfg.qbittorrent.image;
        pull = "missing";

        dependsOn = [ "media-gluetun" ];

        environment = {
          PGID = toString config.users.groups.media.gid;
          PUID = toString config.users.users.qbittorrent.uid;
          TZ = config.time.timeZone;
          UMASK = "0077";
          WEBUI_PORT = toString cfg.ports.qbittorrent;
        };

        volumes = [
          "${appdata}/qbittorrent:/config"
          "${cfg.downloads.incomplete}:${cfg.downloads.incomplete}"
          "${mediaRoot}:${mediaRoot}"
        ];

        extraOptions = [
          "--network=container:media-gluetun"
        ];
      };

      media-sabnzbd = {
        image = cfg.sabnzbd.image;
        pull = "missing";

        dependsOn = [ "media-gluetun" ];

        environment = {
          PGID = toString config.users.groups.media.gid;
          PUID = toString config.users.users.sabnzbd.uid;
          TZ = config.time.timeZone;
          UMASK = "0077";
        };

        volumes = [
          "${appdata}/sabnzbd:/config"
          "${cfg.downloads.incomplete}:${cfg.downloads.incomplete}"
          "${mediaRoot}:${mediaRoot}"
        ];

        extraOptions = [
          "--network=container:media-gluetun"
        ];
      };

      media-gluetun-webui = mkIf gluetunCfg.webUi.enable {
        image = gluetunCfg.webUi.image;
        pull = "missing";

        dependsOn = [ "media-gluetun" ];

        environment = {
          GLUETUN_CONTROL_URL = "http://127.0.0.1:${toString gluetunCfg.controlServer.port}";
          GLUETUN_NAME = gluetunCfg.webUi.name;
          PORT = toString gluetunCfg.webUi.port;
          TRUST_PROXY = if gluetunCfg.webUi.trustProxy then "true" else "false";
        };
        environmentFiles = [ gluetunControlWebUiEnvFile ];

        extraOptions = [
          "--cap-drop=ALL"
          "--network=container:media-gluetun"
          "--read-only"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp"
        ];
      };
    };

    systemd.services = {
      jellyfin.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      jellyfin.environment = mkIf (cfg.jellyfin.publishedServerUrl != null) {
        JELLYFIN_PublishedServerUrl = cfg.jellyfin.publishedServerUrl;
      };
      audiobookshelf.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      audiobookshelf.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      audiobookshelf.serviceConfig = {
        ExecStart = mkForce audiobookshelfExecStart;
        StateDirectory = mkForce "";
        WorkingDirectory = mkForce "${appdata}/audiobookshelf";
      };
      kavita.requires = [
        "kavita-token-key.service"
        "${utils.escapeSystemdPath mediaRoot}.mount"
      ];
      kavita.after = [
        "kavita-token-key.service"
        "${utils.escapeSystemdPath mediaRoot}.mount"
      ];
      kavita-token-key = {
        description = "Create Kavita token key";
        before = [ "kavita.service" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail

          token_file='${appdata}/kavita/config/token.key'
          install -d -m 0750 -o kavita -g kavita "$(dirname "$token_file")"

          if [ ! -s "$token_file" ]; then
            tmp="$(mktemp "''${token_file}.XXXXXX")"
            trap 'rm -f "$tmp"' EXIT
            head -c 64 /dev/urandom | base64 --wrap=0 > "$tmp"
            chown kavita:kavita "$tmp"
            chmod 0600 "$tmp"
            mv "$tmp" "$token_file"
            trap - EXIT
          fi

          chown kavita:kavita "$token_file"
          chmod 0600 "$token_file"
        '';
      };
      radarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      radarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      sonarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      prowlarr.requires = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      prowlarr.after = [ "${utils.escapeSystemdPath "/var/lib/private/prowlarr"}.mount" ];
      prowlarr.serviceConfig.StateDirectoryMode = mkForce "0700";
      bazarr.requires = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];
      bazarr.after = [ "${utils.escapeSystemdPath mediaRoot}.mount" ];

      media-gluetun-control-auth-config = {
        description = "Generate MediaVM Gluetun control server authentication config";
        before = [ "podman-media-gluetun.service" ];
        path = [
          pkgs.coreutils
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
        };
        script = ''
          set -euo pipefail

          install -d -m 0700 -o root -g root '${gluetunControlAuthConfigDir}'

          api_key="$(tr -d '\r\n' < '${gluetunCfg.controlServer.apiKeyFile}')"
          if [ -z "$api_key" ]; then
            echo '${gluetunCfg.controlServer.apiKeyFile} is empty; refusing to generate MediaVM Gluetun control auth config' >&2
            exit 1
          fi

          tmp="$(mktemp '${gluetunControlAuthConfigDir}/config.toml.XXXXXX')"
          chmod 0400 "$tmp"
          cat >"$tmp" <<EOF
[[roles]]
name = "media-gluetun-webui"
routes = [
  "GET /v1/dns/status",
  "GET /v1/portforward",
  "GET /v1/publicip/ip",
  "GET /v1/vpn/settings",
  "GET /v1/vpn/status",
  "PUT /v1/vpn/status"
]
auth = "apikey"
apikey = "$api_key"
EOF

          install -m 0400 -o root -g root "$tmp" '${gluetunControlAuthConfigFile}'
          rm -f "$tmp"

          env_tmp="$(mktemp '${gluetunControlAuthConfigDir}/webui.env.XXXXXX')"
          chmod 0400 "$env_tmp"
          printf 'GLUETUN_API_KEY=%s\n' "$api_key" >"$env_tmp"
          install -m 0400 -o root -g root "$env_tmp" '${gluetunControlWebUiEnvFile}'
          rm -f "$env_tmp"
        '';
      };

      podman-media-gluetun = {
        after = [
          "media-gluetun-control-auth-config.service"
          "network-online.target"
        ];
        requires = [ "media-gluetun-control-auth-config.service" ];
        wants = [ "network-online.target" ];
        serviceConfig.RestartSec = "30s";
      };

      podman-media-qbittorrent = {
        after = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        bindsTo = [ "podman-media-gluetun.service" ];
        partOf = [ "podman-media-gluetun.service" ];
        preStart = "${qbittorrentConfigScript}";
        requires = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-media-sabnzbd = {
        after = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        bindsTo = [ "podman-media-gluetun.service" ];
        partOf = [ "podman-media-gluetun.service" ];
        preStart = "${sabnzbdConfigScript}";
        requires = [
          "podman-media-gluetun.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-media-gluetun-webui = mkIf gluetunCfg.webUi.enable {
        after = [
          "media-gluetun-control-auth-config.service"
          "podman-media-gluetun.service"
        ];
        bindsTo = [ "podman-media-gluetun.service" ];
        partOf = [ "podman-media-gluetun.service" ];
        requires = [
          "media-gluetun-control-auth-config.service"
          "podman-media-gluetun.service"
        ];
        serviceConfig.RestartSec = "30s";
      };

      seerr = {
        after = [ "seerr-appdata-migration.service" ];
        requires = [ "seerr-appdata-migration.service" ];
        serviceConfig = {
          DynamicUser = mkForce false;
          Group = "media";
          ReadWritePaths = [ "${appdata}/seerr" ];
          StateDirectory = mkForce "";
          User = "seerr";
        };
      };

      seerr-appdata-migration = {
        description = "Migrate Jellyseerr appdata to Seerr";
        before = [ "seerr.service" ];
        path = [
          pkgs.coreutils
          pkgs.findutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
        };
        script = ''
          set -euo pipefail

          old='${appdata}/jellyseerr'
          new='${appdata}/seerr'

          install -d -m 0770 -o root -g media "$new"

          if [ -d "$old" ]; then
            if find "$new" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
              echo "$new already contains data; leaving $old in place"
            else
              find "$old" -mindepth 1 -maxdepth 1 -exec mv -t "$new" -- {} +
              rmdir "$old" 2>/dev/null || true
            fi
          fi

          chown -R seerr:media "$new"
          chmod 0770 "$new"
        '';
      };
    };

    # --------------------------------------------------------------------------
    # BACKUPS
    # --------------------------------------------------------------------------

    environment.systemPackages = [ pkgs.restic ];

    systemd.services.appsdata-backup = {
      description = "Back up /srv/appsdata with restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-appsdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host media-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host media-vm \
          --one-file-system \
          --exclude-caches \
          --exclude '${appdata}/jellyfin/cache' \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host media-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata
      '';
    };

    systemd.services.appsdata-restore-check = {
      description = "Verify /srv/appsdata can be restored from restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-appsdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.backup.restoreCheckTarget}'
        case "$restore_parent" in
          /tmp/*|/var/tmp/*) ;;
          *)
            echo "restore check target must be under /tmp or /var/tmp: $restore_parent"
            exit 1
            ;;
        esac

        rm -rf -- "$restore_parent"
        install -d -m 0700 -o root -g root "$restore_parent"
        restore_root="$(mktemp -d "$restore_parent/run.XXXXXX")"
        cleanup() {
          rm -rf -- "$restore_root"
        }
        trap cleanup EXIT

        restic check --retry-lock 30m
        restic restore latest \
          --host media-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.backup.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        first_entry="$(find "$restored_source" -mindepth 1 -maxdepth 1 -print -quit)"
        if [ -z "$first_entry" ]; then
          echo "restore completed but $restored_source is empty"
          exit 1
        fi
      '';
    };

    systemd.timers.appsdata-backup = {
      description = "Daily /srv/appsdata restic backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "appsdata-backup.service";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [
      cfg.ports.audiobookshelf
      cfg.ports.bazarr
      cfg.ports.jellyfin
      cfg.ports.kavita
      cfg.ports.prowlarr
      cfg.ports.qbittorrent
      cfg.ports.radarr
      cfg.ports.sabnzbd
      cfg.ports.seerr
      cfg.ports.sonarr
    ] ++ optional gluetunCfg.webUi.enable gluetunCfg.webUi.port;

    # --------------------------------------------------------------------------
    # RECOVERY NOTES ON THE HOST
    # --------------------------------------------------------------------------

    environment.etc."fleet/media-vm.md".text = ''
      media-vm restore model
      ======================

      Restore /srv/appsdata after reinstalling this NixOS host, before first
      use of Jellyfin, Audiobookshelf, Kavita, ARR apps, qBittorrent, Gluetun,
      SABnzbd, or Seerr. The first activation creates /run/secrets/restic-password,
      /mnt/backups, Restic, users/groups, and service units needed for restore.

      Media files under /mnt/media are mounted from SMB and are not included in
      appsdata-backup.service.

      qBittorrent and SABnzbd write incomplete downloads to
      /var/lib/media-downloads on the local VM. Completed torrent and Usenet
      downloads are moved to /mnt/media/downloads. The local incomplete download
      directory is outside /srv/appsdata and is not included in Restic appdata
      backups.

      Seerr uses /srv/appsdata/seerr. On deploy or restore, legacy
      /srv/appsdata/jellyseerr data is moved there when the new path is empty.

      qBittorrent and SABnzbd run as podman-media-qbittorrent.service and
      podman-media-sabnzbd.service in the media-gluetun container network
      namespace. They have no host-published ports of their own;
      podman-media-gluetun.service publishes qBittorrent WebUI on
      10.2.20.113:8080, SABnzbd on 10.2.20.113:8085, and Gluetun WebUI on
      10.2.20.113:3001. If Gluetun is offline, qBittorrent and SABnzbd
      networking are unavailable. Gluetun state is stored in
      /srv/appsdata/gluetun and is included in appsdata backups.

      Backup repository:
        /mnt/backups/restic/appdata/media-stack-vm

      Password file:
        /run/secrets/restic-password

      Non-destructive validation:
        mount /mnt/backups
        systemctl start appsdata-backup.service
        systemctl start appsdata-restore-check.service
        systemctl is-active podman-media-gluetun.service
        systemctl is-active podman-media-qbittorrent.service
        systemctl is-active podman-media-sabnzbd.service
        systemctl is-active podman-media-gluetun-webui.service
        systemctl status appsdata-backup.service appsdata-restore-check.service

      Restore test target:
        /var/tmp/appsdata-restore-check

      Bootstrap restore outline:
        1. Deploy media-vm once.
        2. Before opening app web UIs, run this from the repo development shell:
             scripts/restore-media-appdata.sh
        3. The script stops media services, mounts /mnt/backups, checks for
           media-vm/appsdata snapshots, moves fresh appdata aside, repairs
           restored ownership, reapplies tmpfiles, fixes Prowlarr DynamicUser
           ownership, and restarts media services.
        4. If multiple snapshots exist, rerun with an explicit snapshot ID:
             scripts/restore-media-appdata.sh <snapshot-id>
        5. If no matching snapshot exists, the script starts media services and
           appsdata-backup.timer, then continues as a fresh system.

      Full restore outline:
        1. Stop appsdata-backup.timer and media services.
        2. Mount /mnt/backups.
        3. Choose a media-vm/appsdata snapshot ID, avoiding tiny fresh-system
           snapshots made after a rebuild.
        4. Move existing /srv/appsdata aside, then restore the chosen snapshot
           to / with restic --verify.
        5. Normalize ownership for rebuilt users and run systemd-tmpfiles --create.
           Keep /srv/appsdata/prowlarr owned by nobody:nogroup with mode 0700
           so the Prowlarr DynamicUser idmapped bind mount can access SQLite.
        6. Restart media-gluetun-control-auth-config.service,
           kavita-token-key.service, media services, appsdata-backup.timer,
           and appsdata-restore-check.service.

      Jellyfin kids access is configured inside Jellyfin after first setup:
      create a non-admin user named kids, grant only the Kids Movies and Kids TV
      Shows libraries, disable deletion and downloads, then optionally use
      parental controls or a kids-approved tag for an extra guardrail.

      First-run setup is available at http://10.2.20.113:8096/web/index.html#!/wizardstart.html.
      Complete it in a browser before connecting native Jellyfin clients.
      Audiobookshelf is available at http://10.2.20.113:8000, Kavita is
      available at http://10.2.20.113:5000, qBittorrent is available through
      MediaVM Gluetun at http://10.2.20.113:8080, SABnzbd is available through
      MediaVM Gluetun at http://10.2.20.113:8085, and the MediaVM Gluetun WebUI
      is available at http://10.2.20.113:3001 and, through Gateway Traefik,
      http://media-gluetun.h.
    '';
  };
}
