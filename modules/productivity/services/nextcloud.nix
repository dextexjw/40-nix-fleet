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
  inherit (productivityLib) cfg appdata secretPath serviceHostAliases serviceHosts;
 in
{
  config = mkIf cfg.enable {
services.nextcloud = {
  enable = true;
  configureRedis = true;
  database.createLocally = true;
  datadir = "${appdata}/nextcloud";
  home = "${appdata}/nextcloud";
  hostName = serviceHosts.nextcloud;
  https = false;
  package = pkgs.nextcloud32;
  config = {
    adminpassFile = secretPath "nextcloud-admin-password";
    adminuser = "smoke";
    dbtype = "pgsql";
  };
  settings = {
    overwrite.cli.url = "http://${serviceHosts.nextcloud}";
    overwriteprotocol = "http";
    trusted_domains = serviceHostAliases.nextcloud;
  };
};
  };
}
