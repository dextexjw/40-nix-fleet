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
  inherit (testbedLib) cfg appdata;
in
{
  config = mkIf (cfg.enable && cfg.stirlingPdf.enable) {
    services.stirling-pdf = {
      enable = true;
      environment = {
        SERVER_ADDRESS = "0.0.0.0";
        SERVER_PORT = cfg.ports.stirlingPdf;
        SYSTEM_DEFAULTLOCALE = "en-US";
        UI_APPNAME = "Fleet PDF";
      };
    };

    systemd.services.stirling-pdf.serviceConfig = {
      DynamicUser = mkForce false;
      Group = "stirling-pdf";
      ReadWritePaths = [ "${appdata}/stirling-pdf" ];
      StateDirectory = mkForce "";
      User = "stirling-pdf";
      WorkingDirectory = mkForce "${appdata}/stirling-pdf";
    };

    systemd.services.stirling-pdf.environment.HOME = mkForce "${appdata}/stirling-pdf";
  };
}
