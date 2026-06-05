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
  inherit (productivityLib)
    cfg
    appdata
    secretPath
    serviceHosts
    ;
in
{
  config = mkIf cfg.enable {
    services.vaultwarden = {
      enable = true;
      configurePostgres = true;
      dbBackend = "postgresql";
      environmentFile = [ (secretPath "vaultwarden-environment") ];
      config = {
        DATA_FOLDER = "${appdata}/vaultwarden";
        DOMAIN = "http://${serviceHosts.vaultwarden}";
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = cfg.ports.vaultwarden;
        SIGNUPS_ALLOWED = false;
        WEB_VAULT_ENABLED = true;
      };
    };

    systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [ "${appdata}/vaultwarden" ];
  };
}
