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
    mkdocsRoot
    serviceHostAliases
    serviceHosts
    ;
in
{
  config = mkIf cfg.enable {
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      commonHttpConfig = mkAfter ''
        map $http_x_forwarded_proto $firefly_fastcgi_https {
          default $https;
          https on;
        }

        map $http_x_forwarded_proto $firefly_request_scheme {
          default $scheme;
          https https;
        }
      '';
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
    services.nginx.virtualHosts.${serviceHosts.privatebin}.serverAliases =
      serviceHostAliases.privatebin;
    services.nginx.virtualHosts.${serviceHosts.firefly} = {
      serverAliases = serviceHostAliases.firefly;
      locations."~ \\.php$".extraConfig = mkAfter ''
        fastcgi_param HTTPS $firefly_fastcgi_https;
        fastcgi_param REQUEST_SCHEME $firefly_request_scheme;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
        fastcgi_param HTTP_X_FORWARDED_HOST $http_x_forwarded_host;
      '';
    };
    services.nginx.virtualHosts.${serviceHosts.nextcloud}.serverAliases = serviceHostAliases.nextcloud;

    systemd.services.nginx = {
      wants = [ "mkdocs-material-build.service" ];
      after = [ "mkdocs-material-build.service" ];
    };
  };
}
