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
  inherit (testbedLib)
    cfg
    appdata
    secretPath
    serviceHostAliases
    serviceHosts
    ;
in
{
  config = mkIf (cfg.enable && cfg.firefly.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "firefly-app-key" config.sops.secrets;
        message = "firefly-app-key must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    services.firefly-iii = {
      enable = true;
      dataDir = "${appdata}/firefly-iii";
      enableNginx = true;
      virtualHost = serviceHosts.firefly;
      settings = {
        APP_ENV = "production";
        APP_KEY_FILE = secretPath "firefly-app-key";
        APP_URL = "https://${serviceHosts.firefly}";
        DB_CONNECTION = "sqlite";
      };
    };

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
    };

    services.nginx.virtualHosts.${serviceHosts.firefly} = {
      serverAliases = serviceHostAliases.firefly;
      locations."~ \\.php$".extraConfig = mkAfter ''
        fastcgi_param HTTPS $firefly_fastcgi_https;
        fastcgi_param REQUEST_SCHEME $firefly_request_scheme;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
        fastcgi_param HTTP_X_FORWARDED_HOST $http_x_forwarded_host;
      '';
    };
  };
}
