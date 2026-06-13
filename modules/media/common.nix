{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib)
    cfg
    appdata
    appsdataDirs
    downloadTempDirs
    gluetunCfg
    ;
in
{
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

    users.users.bookorbit = {
      isSystemUser = true;
      uid = 987;
      group = "media";
      home = "${appdata}/bookorbit";
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
      ++ (map (path: "d '${path}' 0770 root media - -") downloadTempDirs)
      ++ [
        "a+ '${appdata}' - - - - u:postgres:--x"
        "a+ '${appdata}/bookorbit' - - - - u:postgres:--x"
        "d '${appdata}/bookorbit/postgresql' 0750 postgres postgres - -"
        "z '${appdata}/bookorbit/postgresql' 0750 postgres postgres - -"
        "d '${appdata}/bookorbit/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
        "z '${appdata}/bookorbit/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
        "d '${appdata}/bookorbit/postgresql-dumps' 0700 postgres postgres - -"
        "z '${appdata}/bookorbit/postgresql-dumps' 0700 postgres postgres - -"
      ];
    systemd.tmpfiles.settings."10-prowlarr"."${appdata}/prowlarr".d = {
      group = mkForce "nogroup";
      mode = mkForce "0700";
      user = mkForce "nobody";
    };

    virtualisation.oci-containers.backend = "podman";
  };
}
