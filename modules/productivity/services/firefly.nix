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
    services.firefly-iii = {
      enable = true;
      dataDir = "${appdata}/firefly-iii";
      enableNginx = true;
      virtualHost = serviceHosts.firefly;
      settings = {
        APP_ENV = "production";
        APP_KEY_FILE = secretPath "firefly-app-key";
        APP_URL = "http://${serviceHosts.firefly}";
        DB_CONNECTION = "sqlite";
      };
    };
  };
}
