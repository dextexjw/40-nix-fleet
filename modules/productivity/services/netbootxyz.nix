{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg appdata;
  netbootCfg = cfg.netbootxyz;
in
{
  config = mkIf (cfg.enable && netbootCfg.enable) {
    environment.systemPackages = [ pkgs.atftp ];

    virtualisation.oci-containers.containers.netbootxyz = {
      image = netbootCfg.image;
      pull = "missing";

      environment = {
        MENU_VERSION = netbootCfg.menuVersion;
        NGINX_PORT = "80";
        TFTPD_OPTS = "--tftp-single-port";
        WEB_APP_PORT = "3000";
      };

      ports = [
        "${netbootCfg.tftpBindAddress}:${toString netbootCfg.tftpPort}:69/udp"
        "${netbootCfg.webUiBindAddress}:${toString netbootCfg.webUiPort}:3000/tcp"
        "${netbootCfg.assetBindAddress}:${toString netbootCfg.assetPort}:80/tcp"
      ];

      volumes = [
        "${netbootCfg.stateDir}/config:/config"
        "${netbootCfg.stateDir}/assets:/assets"
      ];
    };

    systemd.services.podman-netbootxyz = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.tmpfiles.rules = [
      "d ${netbootCfg.stateDir} 0755 root root - -"
      "d ${netbootCfg.stateDir}/assets 0755 root root - -"
      "d ${netbootCfg.stateDir}/config 0755 root root - -"
    ];

  };
}
