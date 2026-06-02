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
services.paperless = {
  enable = true;
  address = "127.0.0.1";
  configureNginx = true;
  consumptionDir = "${appdata}/paperless/consume";
  dataDir = "${appdata}/paperless";
  database.createLocally = true;
  domain = serviceHosts.paperless;
  mediaDir = "${appdata}/paperless/media";
  passwordFile = secretPath "paperless-admin-password";
  settings = {
    PAPERLESS_ADMIN_USER = "smoke";
    PAPERLESS_ALLOWED_HOSTS = concatStringsSep "," ([ serviceHosts.paperless ] ++ serviceHostAliases.paperless);
    PAPERLESS_OCR_LANGUAGE = "eng";
    PAPERLESS_URL = mkForce "http://${serviceHosts.paperless}";
  };
};
  };
}
