{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.networking.reverseProxy;

  # Helper function to create a virtual host configuration
  mkVirtualHost = name: hostConfig: {
    enableACME = false;
    forceSSL = cfg.enableTLS;

    sslCertificate = mkIf cfg.enableTLS "/var/lib/fleet-ca/certs/${name}/cert.pem";
    sslCertificateKey = mkIf cfg.enableTLS "/var/lib/fleet-ca/certs/${name}/key.pem";

    locations."/" = {
      proxyPass = "http://${hostConfig.target}:${toString hostConfig.port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        ${hostConfig.extraConfig}
      '';
    };
  };
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.networking.reverseProxy = {
    enable = mkEnableOption "Nginx reverse proxy";

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "HTTP port for nginx";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS port for nginx";
    };

    enableTLS = mkOption {
      type = types.bool;
      default = false;
      description = "Enable TLS/SSL for all routes";
    };

    routes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            target = mkOption {
              type = types.str;
              description = "Target host IP or hostname";
            };

            port = mkOption {
              type = types.port;
              description = "Target port";
            };

            description = mkOption {
              type = types.str;
              default = "";
              description = "Description of this route";
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = "Additional nginx configuration for this route";
              example = ''
                client_max_body_size 100M;
                proxy_read_timeout 300;
              '';
            };
          };
        }
      );
      default = { };
      description = "Hostname to backend mapping";
      example = {
        "jenkins.home.arpa" = {
          target = "10.2.20.112";
          port = 8888;
          description = "Jenkins CI/CD";
        };
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # NGINX SERVICE
    # --------------------------------------------------------------------------

    services.nginx = {
      enable = true;

      # Default configuration
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      # Generate virtual hosts from routes
      virtualHosts = mapAttrs mkVirtualHost cfg.routes;
    };

    # --------------------------------------------------------------------------
    # FIREWALL CONFIGURATION
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [
      cfg.httpPort
      cfg.httpsPort
    ];
  };
}
