{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.traefik;

  dashboardHosts =
    if cfg.dashboard.domains != [ ] then
      cfg.dashboard.domains
    else if cfg.dashboard.domain == null then
      [ "traefik.${cfg.domain}" ]
    else
      [ cfg.dashboard.domain ];

  routerEntryPoints = if cfg.enableTLS then [ "websecure" ] else [ "web" ];

  dashboardRule = "PathPrefix(`/api`) || PathPrefix(`/dashboard`)";

  mkName =
    name:
    replaceStrings
      [
        "."
        "*"
      ]
      [
        "-"
        "wildcard"
      ]
      name;

  mkHostRule = host: "Host(`${host}`)";

  mkRouter =
    name: route:
    nameValuePair (mkName name) (
      {
        entryPoints = routerEntryPoints;
        rule = concatStringsSep " || " (map mkHostRule route.hosts);
        service = mkName name;
      }
      // optionalAttrs cfg.enableTLS { tls = { }; }
    );

  mkService =
    name: route:
    nameValuePair (mkName name) {
      loadBalancer = {
        passHostHeader = true;
        servers = [
          {
            url = route.url;
          }
        ];
      };
    };

  mkTcpRouter =
    name: route:
    nameValuePair (mkName name) {
      entryPoints = [ route.entryPoint ];
      rule = "HostSNI(`*`)";
      service = mkName name;
    };

  mkTcpService =
    name: route:
    nameValuePair (mkName name) {
      loadBalancer.servers = [
        {
          address = route.url;
        }
      ];
    };

  mkUdpRouter =
    name: route:
    nameValuePair (mkName name) {
      entryPoints = [ route.entryPoint ];
      service = mkName name;
    };

  mkUdpService =
    name: route:
    nameValuePair (mkName name) {
      loadBalancer.servers = [
        {
          address = route.url;
        }
      ];
    };

  mkTcpEntryPoint =
    name: route:
    nameValuePair route.entryPoint {
      address = ":${toString route.port}/tcp";
    };

  mkUdpEntryPoint =
    name: route:
    nameValuePair route.entryPoint {
      address = ":${toString route.port}/udp";
    };

  dashboardRouters =
    optionalAttrs cfg.dashboard.enable {
      dashboard = {
        entryPoints = [ "dashboard" ];
        rule = dashboardRule;
        service = "api@internal";
      };
    }
    // optionalAttrs (cfg.dashboard.enable && cfg.dashboard.webRoute.enable) {
      dashboard-web = {
        entryPoints = [ "web" ];
        rule = "(${concatStringsSep " || " (map mkHostRule dashboardHosts)}) && (${dashboardRule})";
        service = "api@internal";
      };
    };

  metricsEntryPoint = if cfg.metrics.entryPoint == null then "dashboard" else cfg.metrics.entryPoint;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.traefik = {
    enable = mkEnableOption "Traefik gateway ingress";

    accessLog = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Traefik request access logs.";
      };

      addInternals = mkOption {
        type = types.bool;
        default = false;
        description = "Include Traefik internal services in access logs.";
      };

      format = mkOption {
        type = types.enum [
          "common"
          "genericCLF"
          "json"
        ];
        default = "json";
        description = "Access log output format.";
      };
    };

    dashboard = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Expose the Traefik dashboard through the file provider.";
      };

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Dashboard hostname. Defaults to traefik.<domain>.";
        example = "traefik.h";
      };

      domains = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Dashboard hostnames. When non-empty, this replaces dashboard.domain for the web route.";
        example = [
          "traefik.jax22.com"
          "traefik.h"
        ];
      };

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Dedicated Traefik dashboard and API entrypoint port.";
      };

      webRoute = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Expose the dashboard and API paths on the HTTP web entrypoint using dashboard.domain.";
        };
      };
    };

    domain = mkOption {
      type = types.str;
      default = "home.arpa";
      description = "Internal service domain used for generated defaults.";
    };

    enableTLS = mkOption {
      type = types.bool;
      default = false;
      description = "Attach a TLS router on the websecure entrypoint.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 80;
      description = "HTTP entrypoint port.";
    };

    httpsPort = mkOption {
      type = types.port;
      default = 443;
      description = "HTTPS entrypoint port.";
    };

    logLevel = mkOption {
      type = types.enum [
        "DEBUG"
        "INFO"
        "WARN"
        "ERROR"
      ];
      default = "INFO";
      description = "Traefik log level.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.traefik;
      defaultText = literalExpression "pkgs.traefik";
      description = "Traefik package to run on the gateway.";
    };

    metrics = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Traefik Prometheus metrics.";
      };

      addInternals = mkOption {
        type = types.bool;
        default = false;
        description = "Include Traefik internal services in metrics.";
      };

      addRoutersLabels = mkOption {
        type = types.bool;
        default = true;
        description = "Add router labels to Prometheus metrics.";
      };

      entryPoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Entrypoint used to expose Prometheus metrics. Defaults to the dashboard entrypoint.";
      };
    };

    routes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable route purpose.";
            };

            hosts = mkOption {
              type = types.nonEmptyListOf types.str;
              description = "Hostnames matched by Traefik. The first hostname is treated as canonical by exposure catalog consumers.";
              example = [
                "homepage.h"
                "hg.h"
              ];
            };

            url = mkOption {
              type = types.str;
              description = "Backend URL Traefik should proxy to.";
              example = "http://10.2.20.113:8096";
            };
          };
        }
      );
      default = { };
      description = "Named Traefik HTTP routes.";
    };

    tcpRoutes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable TCP route purpose.";
            };

            entryPoint = mkOption {
              type = types.str;
              description = "Dedicated Traefik TCP entrypoint name.";
              example = "rustdesk-signal-tcp";
            };

            port = mkOption {
              type = types.port;
              description = "Gateway TCP port for this entrypoint.";
            };

            url = mkOption {
              type = types.str;
              description = "Backend host:port address Traefik should proxy.";
              example = "10.2.20.114:21116";
            };
          };
        }
      );
      default = { };
      description = "Named Traefik TCP passthrough routes on dedicated entrypoints.";
    };

    tracing = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Traefik OpenTelemetry tracing.";
      };

      addInternals = mkOption {
        type = types.bool;
        default = false;
        description = "Include Traefik internal services in traces.";
      };

      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "OTLP HTTP trace collector endpoint.";
        example = "http://otel-collector.h:4318/v1/traces";
      };

      sampleRate = mkOption {
        type = types.float;
        default = 1.0;
        description = "Proportion of requests to trace.";
      };

      serviceName = mkOption {
        type = types.str;
        default = "gateway-traefik";
        description = "OpenTelemetry service name for Traefik traces.";
      };
    };

    udpRoutes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              default = "";
              description = "Human-readable UDP route purpose.";
            };

            entryPoint = mkOption {
              type = types.str;
              description = "Dedicated Traefik UDP entrypoint name.";
              example = "rustdesk-signal-udp";
            };

            port = mkOption {
              type = types.port;
              description = "Gateway UDP port for this entrypoint.";
            };

            url = mkOption {
              type = types.str;
              description = "Backend host:port address Traefik should proxy.";
              example = "10.2.20.114:21116";
            };
          };
        }
      );
      default = { };
      description = "Named Traefik UDP passthrough routes on dedicated entrypoints.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.tracing.enable || cfg.tracing.endpoint != null;
        message = "fleet.gateway.traefik.tracing.endpoint must be set when tracing is enabled.";
      }
      {
        assertion = !cfg.metrics.enable || cfg.dashboard.enable || cfg.metrics.entryPoint != null;
        message = "fleet.gateway.traefik.metrics.entryPoint must be set when metrics are enabled without the dashboard entrypoint.";
      }
    ];

    services.traefik = {
      enable = true;
      package = cfg.package;

      dynamicConfigOptions.http = {
        routers = dashboardRouters // mapAttrs' mkRouter cfg.routes;
        services = mapAttrs' mkService cfg.routes;
      };
      dynamicConfigOptions.tcp = mkIf (cfg.tcpRoutes != { }) {
        routers = mapAttrs' mkTcpRouter cfg.tcpRoutes;
        services = mapAttrs' mkTcpService cfg.tcpRoutes;
      };
      dynamicConfigOptions.udp = mkIf (cfg.udpRoutes != { }) {
        routers = mapAttrs' mkUdpRouter cfg.udpRoutes;
        services = mapAttrs' mkUdpService cfg.udpRoutes;
      };

      staticConfigOptions = {
        api.dashboard = cfg.dashboard.enable;

        entryPoints = {
          web.address = ":${toString cfg.httpPort}";
          websecure.address = ":${toString cfg.httpsPort}";
        }
        // mapAttrs' mkTcpEntryPoint cfg.tcpRoutes
        // mapAttrs' mkUdpEntryPoint cfg.udpRoutes
        // optionalAttrs cfg.dashboard.enable {
          dashboard.address = ":${toString cfg.dashboard.port}";
        };

        global = {
          checkNewVersion = false;
          sendAnonymousUsage = false;
        };

        log.level = cfg.logLevel;
      }
      // optionalAttrs cfg.accessLog.enable {
        accessLog = {
          addInternals = cfg.accessLog.addInternals;
          format = cfg.accessLog.format;
        };
      }
      // optionalAttrs cfg.metrics.enable {
        metrics = {
          addInternals = cfg.metrics.addInternals;
          prometheus = {
            addRoutersLabels = cfg.metrics.addRoutersLabels;
            entryPoint = metricsEntryPoint;
          };
        };
      }
      // optionalAttrs cfg.tracing.enable {
        tracing = {
          addInternals = cfg.tracing.addInternals;
          otlp.http.endpoint = cfg.tracing.endpoint;
          sampleRate = cfg.tracing.sampleRate;
          serviceName = cfg.tracing.serviceName;
        };
      };
    };

    networking.firewall.allowedTCPPorts = [
      cfg.httpPort
    ]
    ++ optional cfg.enableTLS cfg.httpsPort
    ++ optional cfg.dashboard.enable cfg.dashboard.port
    ++ mapAttrsToList (_name: route: route.port) cfg.tcpRoutes;

    networking.firewall.allowedUDPPorts = mapAttrsToList (_name: route: route.port) cfg.udpRoutes;
  };
}
