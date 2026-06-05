{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.authentik;
  postgresqlDataDir = "${cfg.stateDir}/postgresql/${config.services.postgresql.package.psqlSchema}";
  redisDataDir = "${cfg.stateDir}/redis";
  secretFile = path: if path == null then "/run/secrets/UNSET" else path;
  bootstrapEmailFallback = if cfg.bootstrap.email == null then "" else cfg.bootstrap.email;
  bootstrapUsernameFallback = if cfg.bootstrap.username == null then "" else cfg.bootstrap.username;
  authentikEnvironment = {
    AUTHENTIK_CERT_DISCOVERY_DIR = "${cfg.stateDir}/certs";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_DISABLE_UPDATE_CHECK = "true";
    AUTHENTIK_ERROR_REPORTING__ENABLED = "false";
    AUTHENTIK_LISTEN__HTTP = "${cfg.listenAddress}:${toString cfg.httpPort}";
    AUTHENTIK_LISTEN__HTTPS = "${cfg.listenAddress}:9443";
    AUTHENTIK_LISTEN__METRICS = "${cfg.listenAddress}:${toString cfg.metricsPort}";
    AUTHENTIK_LOG_LEVEL = "info";
    AUTHENTIK_POSTGRESQL__HOST = "127.0.0.1";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_POSTGRESQL__PORT = "5432";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__CONN_MAX_AGE = "0";
    AUTHENTIK_STORAGE__FILE__PATH = "${cfg.stateDir}/media";
  };

  authentikWrapper = pkgs.writeShellScript "fleet-authentik" ''
    set -euo pipefail

    export AUTHENTIK_SECRET_KEY="$(<${secretFile cfg.secretKeyFile})"
    export AUTHENTIK_POSTGRESQL__PASSWORD="$(<${secretFile cfg.postgresql.passwordFile})"

    read_secret_or_fallback() {
      local variable_name="$1"
      local file="$2"
      local fallback="$3"
      local value="$fallback"

      if [ -r "$file" ]; then
        IFS= read -r value < "$file" || [ -n "$value" ]
      fi

      if [ -n "$value" ]; then
        export "$variable_name=$value"
      fi
    }

    read_secret_or_fallback AUTHENTIK_BOOTSTRAP_EMAIL ${escapeShellArg (secretFile cfg.bootstrap.emailFile)} ${escapeShellArg bootstrapEmailFallback}
    read_secret_or_fallback AUTHENTIK_BOOTSTRAP_USERNAME ${escapeShellArg (secretFile cfg.bootstrap.usernameFile)} ${escapeShellArg bootstrapUsernameFallback}

    if [ -r "${secretFile cfg.bootstrap.passwordFile}" ]; then
      export AUTHENTIK_BOOTSTRAP_PASSWORD="$(<${secretFile cfg.bootstrap.passwordFile})"
    fi

    if [ -r "${secretFile cfg.bootstrap.tokenFile}" ]; then
      export AUTHENTIK_BOOTSTRAP_TOKEN="$(<${secretFile cfg.bootstrap.tokenFile})"
    fi

    exec ${lib.getExe cfg.package} "$@"
  '';

  groupProvisioningJson = pkgs.writeText "fleet-authentik-groups.json" (
    builtins.toJSON {
      groups = cfg.groups;
    }
  );

  applicationProvisioningJson = pkgs.writeText "fleet-authentik-applications.json" (
    builtins.toJSON {
      adminGroups = cfg.adminGroups;
      applications = cfg.applications;
    }
  );

  nativeOidcApplications = filter (app: app.mode == "native-oidc") cfg.applications;

  mkOidcApplicationAssertions = app: [
    {
      assertion = app.oidc.clientSecretFile != null;
      message = "fleet.gateway.authentik application ${app.slug} uses native-oidc but does not set oidc.clientSecretFile.";
    }
    {
      assertion = app.oidc.redirectUris != [ ];
      message = "fleet.gateway.authentik application ${app.slug} uses native-oidc but does not set oidc.redirectUris.";
    }
  ];

  provisioningPython = pkgs.replaceVars ./provision.py {
    inherit groupProvisioningJson applicationProvisioningJson;
  };

  provisioningScript = pkgs.writeShellScript "fleet-authentik-provision" ''
    set -euo pipefail

    wait_for_authentik() {
      for attempt in $(seq 1 120); do
        if curl -fsS "http://${cfg.listenAddress}:${toString cfg.httpPort}/-/health/ready/" >/dev/null; then
          return 0
        fi
        sleep 1
      done

      echo "authentik API did not become ready" >&2
      exit 1
    }

    wait_for_authentik
    ${authentikWrapper} shell < ${provisioningPython}
  '';
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.authentik = {
    enable = mkEnableOption "Authentik identity provider on gateway-vm";

    package = mkOption {
      type = types.package;
      default = pkgs.authentik;
      defaultText = literalExpression "pkgs.authentik";
      description = "Authentik package to run.";
    };

    domain = mkOption {
      type = types.str;
      default = "auth.jax22.com";
      description = "Canonical public Authentik hostname.";
    };

    aliases = mkOption {
      type = types.listOf types.str;
      default = [ "auth.h" ];
      description = "Unprotected LAN Authentik aliases.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/srv/appsdata/authentik";
      description = "Authoritative Authentik state root.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address for Authentik HTTP and metrics listeners.";
    };

    httpPort = mkOption {
      type = types.port;
      default = 9000;
      description = "Authentik HTTP listener port.";
    };

    metricsPort = mkOption {
      type = types.port;
      default = 9300;
      description = "Authentik metrics listener port.";
    };

    secretKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Runtime file containing AUTHENTIK_SECRET_KEY.";
    };

    groups = mkOption {
      type = types.listOf types.str;
      default = [
        "fleet-admins"
        "media-users"
        "monitoring-users"
        "productivity-users"
      ];
      description = "Role groups that the provisioning unit ensures exist.";
    };

    adminGroups = mkOption {
      type = types.listOf types.str;
      default = [ "fleet-admins" ];
      description = "Role groups that can reach every managed Authentik application.";
    };

    applications = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            slug = mkOption { type = types.str; };
            name = mkOption { type = types.str; };
            mode = mkOption {
              type = types.enum [
                "forward-auth"
                "native-header"
                "native-oidc"
              ];
            };
            groups = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            hosts = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            oidc = {
              clientId = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "OIDC client ID. Defaults to the application slug.";
              };

              clientSecretFile = mkOption {
                type = types.nullOr types.path;
                default = null;
                description = "Runtime file containing the OIDC client secret.";
              };

              clientType = mkOption {
                type = types.enum [
                  "confidential"
                  "public"
                ];
                default = "confidential";
                description = "OAuth2 client type.";
              };

              includeClaimsInIdToken = mkOption {
                type = types.bool;
                default = true;
                description = "Include scope claims in the ID token.";
              };

              launchUrl = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Launch URL shown in Authentik for this application.";
              };

              redirectUris = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "Strict redirect URIs allowed for this OIDC client.";
              };

              subMode = mkOption {
                type = types.enum [
                  "hashed_user_id"
                  "user_id"
                  "user_uuid"
                  "user_username"
                  "user_email"
                  "user_upn"
                ];
                default = "hashed_user_id";
                description = "Authentik subject identifier mode.";
              };
            };
          };
        }
      );
      default = [ ];
      description = "Declared Authentik application inventory used by the provisioning unit.";
    };

    bootstrap = {
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Fallback bootstrap admin email when emailFile is unset or unreadable.";
      };

      emailFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the bootstrap admin email.";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Fallback bootstrap admin username when usernameFile is unset or unreadable.";
      };

      usernameFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the bootstrap admin username.";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the initial bootstrap admin password.";
      };

      tokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the bootstrap API token.";
      };
    };

    postgresql = {
      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Runtime file containing the Authentik PostgreSQL role password.";
      };
    };

    provisioning = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the idempotent Authentik provisioning unit after Authentik starts.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secretKeyFile != null;
        message = "fleet.gateway.authentik.secretKeyFile must be set.";
      }
      {
        assertion = cfg.postgresql.passwordFile != null;
        message = "fleet.gateway.authentik.postgresql.passwordFile must be set.";
      }
    ]
    ++ concatMap mkOidcApplicationAssertions nativeOidcApplications;

    users.groups.authentik = { };
    users.users.authentik = {
      description = "Authentik service user";
      group = "authentik";
      home = cfg.stateDir;
      isSystemUser = true;
    };

    services.postgresql = {
      enable = true;
      dataDir = postgresqlDataDir;
      ensureDatabases = [ "authentik" ];
      ensureUsers = [
        {
          name = "authentik";
          ensureDBOwnership = true;
        }
      ];
      settings.max_connections = 300;
      authentication = mkAfter ''
        host authentik authentik 127.0.0.1/32 scram-sha-256
      '';
    };

    services.redis.servers.authentik = {
      enable = true;
      appendOnly = true;
      bind = "127.0.0.1";
      openFirewall = false;
      port = 6379;
      settings.dir = mkForce redisDataDir;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 root authentik - -"
      "d ${cfg.stateDir}/certs 0750 authentik authentik - -"
      "d ${cfg.stateDir}/media 0750 authentik authentik - -"
      "d ${cfg.stateDir}/postgresql 0750 postgres postgres - -"
      "d ${postgresqlDataDir} 0750 postgres postgres - -"
      "d ${redisDataDir} 0750 redis-authentik redis-authentik - -"
    ];

    systemd.services.authentik-postgresql-password = {
      description = "Set Authentik PostgreSQL role password";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
      };
      path = [
        config.services.postgresql.package
        pkgs.coreutils
        pkgs.gnused
      ];
      script = ''
        set -euo pipefail

        password="$(<${secretFile cfg.postgresql.passwordFile})"
        escaped="$(${lib.getExe pkgs.python3} -c 'import sys; print(sys.stdin.read().replace(chr(39), chr(39) * 2), end="")' <<<"$password")"
        printf "ALTER ROLE authentik WITH PASSWORD '%s';\n" "$escaped" | psql -d postgres
      '';
    };

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = mkForce [ "${cfg.stateDir}/postgresql" ];
      SupplementaryGroups = [ "authentik" ];
    };
    systemd.services.redis-authentik.serviceConfig = {
      ReadWritePaths = [ redisDataDir ];
      SupplementaryGroups = [ "authentik" ];
    };

    systemd.services.authentik-server = {
      description = "Authentik server";
      after = [
        "authentik-postgresql-password.service"
        "network-online.target"
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "authentik-postgresql-password.service"
        "postgresql.service"
        "redis-authentik.service"
      ];
      wants = [ "network-online.target" ];
      environment = authentikEnvironment;
      serviceConfig = {
        ExecStart = "${authentikWrapper} server";
        Group = "authentik";
        Restart = "on-failure";
        StateDirectory = "authentik";
        Type = "simple";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.authentik-worker = {
      description = "Authentik worker";
      after = [
        "authentik-postgresql-password.service"
        "authentik-server.service"
        "network-online.target"
        "postgresql.service"
        "redis-authentik.service"
      ];
      requires = [
        "authentik-postgresql-password.service"
        "postgresql.service"
        "redis-authentik.service"
      ];
      wants = [
        "authentik-server.service"
        "network-online.target"
      ];
      environment = authentikEnvironment;
      serviceConfig = {
        ExecStart = "${authentikWrapper} worker";
        Group = "authentik";
        Restart = "on-failure";
        StateDirectory = "authentik";
        Type = "simple";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.services.authentik-provision = mkIf cfg.provisioning.enable {
      description = "Provision fleet Authentik groups and applications";
      after = [
        "authentik-server.service"
        "authentik-worker.service"
      ];
      before = [ "traefik.service" ];
      requiredBy = [ "traefik.service" ];
      requires = [
        "authentik-server.service"
        "authentik-worker.service"
      ];
      wants = [ "authentik-worker.service" ];
      serviceConfig = {
        ExecStart = provisioningScript;
        Group = "authentik";
        Type = "oneshot";
        User = "authentik";
        WorkingDirectory = cfg.stateDir;
      };
      path = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      wantedBy = [
        "authentik-worker.service"
        "multi-user.target"
      ];
    };
  };
}
