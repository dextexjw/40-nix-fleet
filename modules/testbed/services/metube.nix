{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  testbedLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg;

  metubeCfg = cfg.metube;
  mediaMountUnit = "${utils.escapeSystemdPath cfg.smb.mediaMount}.mount";
in
{
  config = mkIf (cfg.enable && metubeCfg.enable) {
    virtualisation.oci-containers.backend = "podman";
    systemd.user.sockets.podman.wantedBy = mkForce [ ];

    virtualisation.oci-containers.containers.metube = {
      image = metubeCfg.image;
      pull = "missing";

      environment = {
        ALLOW_YTDL_OPTIONS_OVERRIDES = "false";
        CHOWN_DIRS = "false";
        CORS_ALLOWED_ORIGINS = "";
        DELETE_FILE_ON_TRASHCAN = "false";
        DOWNLOAD_DIR = "/downloads";
        DOWNLOAD_DIRS_INDEXABLE = "false";
        HOST = "0.0.0.0";
        LOGLEVEL = "INFO";
        PGID = "1000";
        PORT = toString cfg.ports.metube;
        PUBLIC_HOST_URL = metubeCfg.externalUrl;
        PUID = "1000";
        STATE_DIR = "/state";
        TEMP_DIR = "/temp";
        UMASK = "002";
      };

      volumes = [
        "${metubeCfg.downloadDir}:/downloads"
        "${metubeCfg.stateDir}/state:/state"
        "${metubeCfg.tempDir}:/temp"
      ];

      extraOptions = [
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--network=host"
        "--security-opt=no-new-privileges"
      ];
    };

    systemd.services.podman-metube = {
      after = [
        mediaMountUnit
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [
        mediaMountUnit
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "network-online.target" ];
      path = [ pkgs.coreutils ];
      preStart = ''
        mkdir -p ${escapeShellArg (toString metubeCfg.downloadDir)}
      '';
      serviceConfig = {
        RestartSec = "30s";
        UMask = "0002";
      };
    };
  };
}
