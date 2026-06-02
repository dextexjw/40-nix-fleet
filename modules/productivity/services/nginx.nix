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
  inherit (productivityLib) cfg mkdocsRoot serviceHostAliases serviceHosts;
 in
{
  config = mkIf cfg.enable {
services.nginx = {
  enable = true;
  recommendedGzipSettings = true;
  recommendedOptimisation = true;
  recommendedProxySettings = true;
  virtualHosts.${serviceHosts.docs} = {
    root = "${mkdocsRoot}/site";
    serverAliases = serviceHostAliases.docs;
    locations."/".tryFiles = "$uri $uri/ /index.html";
  };
};

services.nginx.virtualHosts.${serviceHosts.paperless} = {
  forceSSL = mkForce false;
  serverAliases = serviceHostAliases.paperless;
};
services.nginx.virtualHosts.${serviceHosts.freshrss}.serverAliases = serviceHostAliases.freshrss;
services.nginx.virtualHosts.${serviceHosts.privatebin}.serverAliases = serviceHostAliases.privatebin;
services.nginx.virtualHosts.${serviceHosts.firefly}.serverAliases = serviceHostAliases.firefly;
services.nginx.virtualHosts.${serviceHosts.nextcloud}.serverAliases = serviceHostAliases.nextcloud;

systemd.services.nginx = {
  wants = [ "mkdocs-material-build.service" ];
  after = [ "mkdocs-material-build.service" ];
};
  };
}
