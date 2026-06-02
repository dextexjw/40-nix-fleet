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
  inherit (productivityLib) cfg;
in
{
  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.openspeedtest = {
      environment = {
        ENABLE_LETSENCRYPT = "false";
        HTTP_PORT = "3000";
        HTTPS_PORT = "3001";
      };

      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
      ];

      image = "docker.io/openspeedtest/latest@sha256:1745e913f596fe98882b286a67751efdae74774e9caa742a4934bb056e8748d2";
      pull = "missing";

      ports = [
        "0.0.0.0:${toString cfg.ports.openspeedtest}:3000/tcp"
      ];
    };

    systemd.services.podman-openspeedtest = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };
  };
}
