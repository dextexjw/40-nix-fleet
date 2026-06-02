{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg appdata secretPath serviceHosts;
 in
{
  config = mkIf cfg.enable {
virtualisation.oci-containers.containers.rustfs = {
  image = "docker.io/rustfs/rustfs@sha256:029bab58b7cfca8b3b3483d49ac073075f555d7cc50abdd706d7df74bf6ec432";
  pull = "missing";

  environment = {
    RUSTFS_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsApi}";
    RUSTFS_CONSOLE_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsConsole}";
    RUSTFS_CONSOLE_ENABLE = "true";
    RUSTFS_SERVER_DOMAINS = serviceHosts.rustfs;
    RUSTFS_VOLUMES = "/data";
  };
  environmentFiles = [ (secretPath "rustfs-environment") ];

  extraOptions = [
    "--cap-drop=ALL"
    "--health-cmd=sh -c 'curl -f http://127.0.0.1:${toString cfg.ports.rustfsApi}/health && curl -f http://127.0.0.1:${toString cfg.ports.rustfsConsole}/rustfs/console/health'"
    "--health-interval=30s"
    "--health-retries=3"
    "--health-start-period=40s"
    "--health-timeout=10s"
    "--security-opt=no-new-privileges"
  ];

  podman.sdnotify = "healthy";

  ports = [
    "0.0.0.0:${toString cfg.ports.rustfsApi}:${toString cfg.ports.rustfsApi}/tcp"
    "0.0.0.0:${toString cfg.ports.rustfsConsole}:${toString cfg.ports.rustfsConsole}/tcp"
  ];

  volumes = [
    "${appdata}/rustfs/data:/data"
  ];
};

systemd.services.podman-rustfs = {
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  serviceConfig.RestartSec = "30s";
};
  };
}
