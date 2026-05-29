{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.traefik;

  dashboardHost =
    if cfg.dashboard.domain == null then
      "traefik.${cfg.domain}"
    else
      cfg.dashboard.domain;

  routerEntryPoints =
    if cfg.enableTLS then
      [ "websecure" ]
    else
      [ "web" ];

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

  mkRouter =
    name: route:
    nameValuePair (mkName name) (
      {
        entryPoints = routerEntryPoints;
        rule = "Host(`${route.host}`)";
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

  dashboardRouters = optionalAttrs cfg.dashboard.enable {
    dashboard = {
      entryPoints = [ "dashboard" ];
      rule = dashboardRule;
      service = "api@internal";
    };
  } // optionalAttrs (cfg.dashboard.enable && cfg.dashboard.webRoute.enable) {
    dashboard-web = {
      entryPoints = [ "web" ];
      rule = "Host(`${dashboardHost}`) && (${dashboardRule})";
      service = "api@internal";
    };
  };

  metricsEntryPoint =
    if cfg.metrics.entryPoint == null then
      "dashboard"
    else
      cfg.metrics.entryPoint;
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
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable route purpose.";
          };

          host = mkOption {
            type = types.str;
            description = "Hostname matched by Traefik.";
            example = "homepage.h";
          };

          url = mkOption {
            type = types.str;
            description = "Backend URL Traefik should proxy to.";
            example = "http://10.2.20.113:8096";
          };
        };
      });
      default = { };
      description = "Named Traefik HTTP routes.";
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

      staticConfigOptions = {
        api.dashboard = cfg.dashboard.enable;

        entryPoints = {
          web.address = ":${toString cfg.httpPort}";
          websecure.address = ":${toString cfg.httpsPort}";
        } // optionalAttrs cfg.dashboard.enable {
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

    networking.firewall.allowedTCPPorts =
      [ cfg.httpPort ]
      ++ optional cfg.enableTLS cfg.httpsPort
      ++ optional cfg.dashboard.enable cfg.dashboard.port;
  };
}
