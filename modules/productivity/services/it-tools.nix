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
  itToolsCfg = cfg.itTools;
in
{
  config = mkIf (cfg.enable && itToolsCfg.enable) {
    virtualisation.oci-containers.containers.it-tools = {
      extraOptions = [
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=NET_BIND_SERVICE"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--security-opt=no-new-privileges"
        "--cpus=${itToolsCfg.resources.cpus}"
        "--memory=${itToolsCfg.resources.memory}"
        "--memory-swap=${itToolsCfg.resources.memorySwap}"
      ];

      image = itToolsCfg.image;
      pull = "missing";

      ports = [
        "0.0.0.0:${toString cfg.ports.itTools}:80/tcp"
      ];
    };

    systemd.services.podman-it-tools = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };
  };
}
