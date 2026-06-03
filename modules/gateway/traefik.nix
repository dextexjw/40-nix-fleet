{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.traefik;
  authModes = [
    "none"
    "forward-auth"
    "native-header"
    "native-oidc"
  ];

  dashboardHosts =
    if cfg.dashboard.domains != [ ] then
      cfg.dashboard.domains
    else if cfg.dashboard.domain == null then
      [ "traefik.${cfg.domain}" ]
    else
      [ cfg.dashboard.domain ];

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

  mkRule = hosts: concatStringsSep " || " (map mkHostRule hosts);

  tlsEnabled = cfg.tls.enable;
  tlsDomain = cfg.tls.domain;
  isTlsHost = host: host == tlsDomain || hasSuffix ".${tlsDomain}" host;
  tlsHosts = hosts: filter isTlsHost hosts;

  routeProtectedHosts =
    route:
    filter (
      host: route.auth.mode == "forward-auth" && elem host route.auth.protectedHosts && isTlsHost host
    ) route.hosts;

  dashboardProtectedHosts =
    let
      protectedHosts =
        if cfg.dashboard.auth.protectedHosts == [ ] then
          tlsHosts dashboardHosts
        else
          cfg.dashboard.auth.protectedHosts;
    in
    filter (
      host: cfg.dashboard.auth.mode == "forward-auth" && elem host protectedHosts && isTlsHost host
    ) dashboardHosts;

  allForwardAuthHosts = unique (
    dashboardProtectedHosts
    ++ concatLists (mapAttrsToList (_name: route: routeProtectedHosts route) cfg.routes)
  );

  hasForwardAuth = allForwardAuthHosts != [ ];

  mkRouter =
    name: route:
    nameValuePair (mkName name) {
      entryPoints = [ "web" ];
      rule = mkRule route.hosts;
      service = mkName name;
    };

  mkTlsRouter =
    name: route:
    nameValuePair "${mkName name}-tls" (
      {
        entryPoints = [ "websecure" ];
        rule = mkRule (tlsHosts route.hosts);
        service = mkName name;
        tls = { };
      }
      // optionalAttrs (routeProtectedHosts route != [ ]) {
        middlewares = [ cfg.authentik.middlewareName ];
      }
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
        rule = "(${mkRule dashboardHosts}) && (${dashboardRule})";
        service = "api@internal";
      };
    }
    //
      optionalAttrs
        (
          cfg.dashboard.enable
          && cfg.dashboard.webRoute.enable
          && tlsEnabled
          && tlsHosts dashboardHosts != [ ]
        )
        {
          dashboard-websecure = {
            entryPoints = [ "websecure" ];
            rule = "(${mkRule (tlsHosts dashboardHosts)}) && (${dashboardRule})";
            service = "api@internal";
            tls = { };
          }
          // optionalAttrs (dashboardProtectedHosts != [ ]) {
            middlewares = [ cfg.authentik.middlewareName ];
          };
        };

  authentikMiddlewares = optionalAttrs (cfg.authentik.enable && hasForwardAuth) {
    ${cfg.authentik.middlewareName} = {
      forwardAuth = {
        address = "${cfg.authentik.serviceUrl}/outpost.goauthentik.io/auth/traefik";
        authResponseHeaders = [
          "X-authentik-username"
          "X-authentik-groups"
          "X-authentik-entitlements"
          "X-authentik-email"
          "X-authentik-name"
          "X-authentik-uid"
          "X-authentik-jwt"
          "X-authentik-meta-jwks"
        ];
        trustForwardHeader = true;
      };
    };
  };

  authentikRouters = optionalAttrs (cfg.authentik.enable && hasForwardAuth) {
    authentik-outpost = {
      entryPoints = [ "websecure" ];
      priority = 1000;
      rule = "(${mkRule allForwardAuthHosts}) && PathPrefix(`/outpost.goauthentik.io/`)";
      service = "authentik-outpost";
      tls = { };
    };
  };

  authentikServices = optionalAttrs (cfg.authentik.enable && hasForwardAuth) {
    authentik-outpost.loadBalancer.servers = [
      {
        url = cfg.authentik.serviceUrl;
      }
    ];
  };

  tlsRoutes = filterAttrs (_: route: tlsEnabled && tlsHosts route.hosts != [ ]) cfg.routes;

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

      auth = {
        mode = mkOption {
          type = types.enum authModes;
          default = "none";
          description = "Authentication mode for the HTTPS dashboard route.";
        };

        groups = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Authentik groups allowed to reach the dashboard route.";
        };

        protectedHosts = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Dashboard hostnames that should receive forwardAuth middleware. Defaults to TLS dashboard hosts.";
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

            auth = {
              mode = mkOption {
                type = types.enum authModes;
                default = "none";
                description = "Authentication mode for this route.";
              };

              groups = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Authentik groups allowed to reach this route.";
              };

              protectedHosts = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Hostnames that should receive forwardAuth middleware.";
              };
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

    tls = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable managed HTTPS routers for the public service domain.";
      };

      domain = mkOption {
        type = types.str;
        default = cfg.domain;
        description = "Public service domain covered by the managed wildcard certificate.";
        example = "jax22.com";
      };

      resolver = mkOption {
        type = types.str;
        default = "letsencrypt";
        description = "Traefik certificate resolver name used for ACME issuance.";
      };

      acme = {
        dnsApiTokenFile = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Runtime secret file containing the DNS provider API token.";
          example = "/run/secrets/traefik-cloudflare-dns-api-token";
        };

        dnsProvider = mkOption {
          type = types.str;
          default = "cloudflare";
          description = "Traefik ACME DNS-01 provider name.";
        };

        dnsResolvers = mkOption {
          type = types.listOf types.str;
          default = [
            "1.1.1.1:53"
            "8.8.8.8:53"
          ];
          description = "Recursive DNS resolvers Traefik should use while validating DNS-01 propagation.";
        };

        email = mkOption {
          type = types.str;
          default = "admin@jax22.com";
          description = "ACME account email address.";
        };

        storage = mkOption {
          type = types.str;
          default = "/var/lib/traefik/acme.json";
          description = "Runtime path where Traefik stores ACME account and certificate state.";
        };
      };
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

    authentik = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable generated Authentik forwardAuth middleware and embedded-outpost route.";
      };

      middlewareName = mkOption {
        type = types.str;
        default = "authentik-forward-auth";
        description = "Traefik middleware name used for Authentik forwardAuth.";
      };

      serviceUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:9000";
        description = "Internal Authentik server URL used for forwardAuth and embedded outpost paths.";
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
      {
        assertion = !cfg.tls.enable || cfg.tls.acme.dnsApiTokenFile != null;
        message = "fleet.gateway.traefik.tls.acme.dnsApiTokenFile must be set when managed TLS is enabled.";
      }
      {
        assertion = !cfg.tls.enable || cfg.tls.acme.dnsProvider == "cloudflare";
        message = "fleet.gateway.traefik.tls currently supports Cloudflare DNS-01 credentials.";
      }
      {
        assertion = !hasForwardAuth || cfg.authentik.enable;
        message = "fleet.gateway.traefik.authentik.enable must be true when any route uses forward-auth.";
      }
    ];

    services.traefik = {
      enable = true;
      package = cfg.package;

      dynamicConfigOptions = {
        http = {
          routers =
            dashboardRouters
            // authentikRouters
            // mapAttrs' mkRouter cfg.routes
            // mapAttrs' mkTlsRouter tlsRoutes;
          services = authentikServices // mapAttrs' mkService cfg.routes;
        }
        // optionalAttrs (authentikMiddlewares != { }) {
          middlewares = authentikMiddlewares;
        };
      }
      // optionalAttrs (cfg.tcpRoutes != { }) {
        tcp = {
          routers = mapAttrs' mkTcpRouter cfg.tcpRoutes;
          services = mapAttrs' mkTcpService cfg.tcpRoutes;
        };
      }
      // optionalAttrs (cfg.udpRoutes != { }) {
        udp = {
          routers = mapAttrs' mkUdpRouter cfg.udpRoutes;
          services = mapAttrs' mkUdpService cfg.udpRoutes;
        };
      }
      // optionalAttrs cfg.tls.enable {
        tls.stores.default.defaultGeneratedCert = {
          resolver = cfg.tls.resolver;
          domain = {
            main = cfg.tls.domain;
            sans = [ "*.${cfg.tls.domain}" ];
          };
        };
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
      // optionalAttrs cfg.tls.enable {
        certificatesResolvers.${cfg.tls.resolver}.acme = {
          inherit (cfg.tls.acme) email storage;
          dnsChallenge = {
            provider = cfg.tls.acme.dnsProvider;
            resolvers = cfg.tls.acme.dnsResolvers;
          };
        };
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

    systemd.services.traefik = {
      after = optional cfg.authentik.enable "authentik-server.service";
      environment = optionalAttrs cfg.tls.enable {
        CF_DNS_API_TOKEN_FILE = cfg.tls.acme.dnsApiTokenFile;
      };
      wants = optional cfg.authentik.enable "authentik-server.service";
    };

    networking.firewall.allowedTCPPorts = [
      cfg.httpPort
    ]
    ++ optional (cfg.enableTLS || cfg.tls.enable) cfg.httpsPort
    ++ optional cfg.dashboard.enable cfg.dashboard.port
    ++ mapAttrsToList (_name: route: route.port) cfg.tcpRoutes;

    networking.firewall.allowedUDPPorts = mapAttrsToList (_name: route: route.port) cfg.udpRoutes;
  };
}
