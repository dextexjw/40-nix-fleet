{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  testbedLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg;

  fizzyCfg = cfg.fizzy;
in
{
  config = mkIf (cfg.enable && fizzyCfg.enable) {
    virtualisation.oci-containers.backend = "podman";
    systemd.user.sockets.podman.wantedBy = mkForce [ ];

    virtualisation.oci-containers.containers.fizzy = {
      image = fizzyCfg.image;
      pull = "missing";

      environment = {
        ASSUME_SSL = "true";
        BASE_URL = fizzyCfg.externalUrl;
        FORCE_SSL = "false";
        HTTP_PORT = toString cfg.ports.fizzy;
        MAILER_FROM_ADDRESS = "fizzy@testbed.home.arpa";
        MULTI_TENANT = "false";
        SMTP_ADDRESS = "127.0.0.1";
        SMTP_AUTHENTICATION = "plain";
        SMTP_DOMAIN = "testbed.home.arpa";
        SMTP_PASSWORD = "mailpit";
        SMTP_PORT = toString cfg.ports.mailpitSmtp;
        SMTP_USERNAME = "fizzy";
        SOLID_QUEUE_IN_PUMA = "true";
        TARGET_PORT = "9011";
      };

      environmentFiles = [ (toString fizzyCfg.environmentFile) ];

      volumes = [
        "${fizzyCfg.stateDir}/storage:/rails/storage"
      ];

      extraOptions = [
        "--cap-drop=ALL"
        "--init"
        "--network=host"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
      ];
    };

    systemd.services.podman-fizzy = {
      after = [
        "mailpit-testbed.service"
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      requires = [
        "mailpit-testbed.service"
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        RestartSec = "30s";
        UMask = "0077";
      };
    };
  };
}
