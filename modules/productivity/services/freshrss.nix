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
services.freshrss = {
  enable = true;
  api.enable = true;
  authType = "form";
  baseUrl = "http://${serviceHosts.freshrss}";
  dataDir = "${appdata}/freshrss";
  defaultUser = "smoke";
  passwordFile = secretPath "freshrss-admin-password";
  virtualHost = serviceHosts.freshrss;
  webserver = "nginx";
};
  };
}
