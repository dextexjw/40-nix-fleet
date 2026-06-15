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
  inherit (productivityLib) cfg secretPath serviceHosts;
in
{
  config = mkIf cfg.enable {
    services.searx = {
      enable = true;
      domain = serviceHosts.searxng;
      environmentFile = secretPath "searxng-environment";
      openFirewall = false;
      redisCreateLocally = true;
      settings = {
        search.safe_search = 1;
        server = {
          base_url = "http://${serviceHosts.searxng}/";
          bind_address = "0.0.0.0";
          limiter = false;
          port = cfg.ports.searxng;
          secret_key = "$SEARXNG_SECRET_KEY";
        };
        ui.static_use_hash = true;
      };
    };
  };
}
