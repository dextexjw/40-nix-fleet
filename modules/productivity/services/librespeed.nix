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
    services.librespeed = {
      enable = true;
      downloadIPDB = false;
      frontend = {
        contactEmail = "admin@${head cfg.serviceDomains}";
        enable = true;
        pageTitle = "LibreSpeed";
        settings.telemetry_level = "disabled";
        useNginx = false;
      };
      settings = {
        base_url = "backend";
        bind_address = "::";
        database_type = "none";
        ipinfo_api_key = "";
        listen_port = cfg.ports.librespeed;
        redact_ip_addresses = true;
        stats_password = "";
        worker_threads = "auto";
      };
    };

    systemd.services.librespeed = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
  };
}
