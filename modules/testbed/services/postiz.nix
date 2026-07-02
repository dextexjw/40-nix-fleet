{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  testbedLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg;

  postizCfg = cfg.postiz;
  postizNetwork = "postiz";
  podman = "${config.virtualisation.podman.package}/bin/podman";

  postizJwtSecretFile = testbedLib.secretPath "postiz-jwt-secret";
  postizOidcClientSecretFile = testbedLib.secretPath "postiz-oidc-client-secret";
  postizPostgresPasswordFile = testbedLib.secretPath "postiz-postgres-password";
  postizTemporalPostgresPasswordFile = testbedLib.secretPath "postiz-temporal-postgres-password";
  postizTemporalDynamicConfig = pkgs.writeTextDir "development-sql.yaml" ''
    limit.maxIDLength:
      - value: 255
        constraints: {}
    system.forceSearchAttributesCacheRefreshOnRead:
      - value: true
  '';
  renderPostizEnvironmentScript = pkgs.writeShellScript "render-postiz-environment" ''
    set -euo pipefail

    ${lib.getExe pkgs.python3} <<'PY'
    from pathlib import Path
    from urllib.parse import quote

    def read_secret(path, name):
        value = Path(path).read_text().strip()
        if not value:
            raise SystemExit(f"{name} is empty: {path}")
        if "\n" in value or "\r" in value:
            raise SystemExit(f"{name} must be a single line: {path}")
        return value

    jwt_secret = read_secret("${postizJwtSecretFile}", "postiz-jwt-secret")
    oidc_client_secret = read_secret("${postizOidcClientSecretFile}", "postiz-oidc-client-secret")
    postgres_password = read_secret("${postizPostgresPasswordFile}", "postiz-postgres-password")
    temporal_postgres_password = read_secret("${postizTemporalPostgresPasswordFile}", "postiz-temporal-postgres-password")

    database_url = (
        "postgresql://${postizCfg.databaseUser}:"
        + quote(postgres_password, safe="")
        + "@postiz-postgres:5432/${postizCfg.databaseName}"
    )

    postiz_env = {
        "DATABASE_URL": database_url,
        "JWT_SECRET": jwt_secret,
        "POSTIZ_OAUTH_CLIENT_SECRET": oidc_client_secret,
    }
    postiz_postgres_env = {
        "POSTGRES_PASSWORD": postgres_password,
    }
    temporal_postgres_env = {
        "POSTGRES_PASSWORD": temporal_postgres_password,
    }
    temporal_env = {
        "POSTGRES_PWD": temporal_postgres_password,
    }

    def write_env(path, values):
        tmp = Path(str(path) + ".tmp")
        tmp.write_text("".join(f"{key}={value}\n" for key, value in sorted(values.items())))
        tmp.chmod(0o400)
        tmp.replace(path)

    run_dir = Path("/run/postiz")
    run_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    run_dir.chmod(0o700)
    write_env("${postizCfg.environmentFile}", postiz_env)
    write_env("${postizCfg.postgresEnvironmentFile}", postiz_postgres_env)
    write_env("${postizCfg.temporal.postgresEnvironmentFile}", temporal_postgres_env)
    write_env("${postizCfg.temporal.temporalEnvironmentFile}", temporal_env)
    PY
  '';

  requiredSecretNames = [
    "postiz-jwt-secret"
    "postiz-oidc-client-secret"
    "postiz-postgres-password"
    "postiz-temporal-postgres-password"
  ];

  optionalProviderEnvironment = {
    API_LIMIT = "30";
    BEEHIIVE_API_KEY = "";
    BEEHIIVE_PUBLICATION_ID = "";
    DISCORD_BOT_TOKEN_ID = "";
    DISCORD_CLIENT_ID = "";
    DISCORD_CLIENT_SECRET = "";
    DRIBBBLE_CLIENT_ID = "";
    DRIBBBLE_CLIENT_SECRET = "";
    FACEBOOK_APP_ID = "";
    FACEBOOK_APP_SECRET = "";
    FEE_AMOUNT = "0.05";
    GITHUB_CLIENT_ID = "";
    GITHUB_CLIENT_SECRET = "";
    LINKEDIN_CLIENT_ID = "";
    LINKEDIN_CLIENT_SECRET = "";
    MASTODON_CLIENT_ID = "";
    MASTODON_CLIENT_SECRET = "";
    MASTODON_URL = "https://mastodon.social";
    NEXT_PUBLIC_DISCORD_SUPPORT = "";
    NEXT_PUBLIC_POLOTNO = "";
    OPENAI_API_KEY = "";
    PINTEREST_CLIENT_ID = "";
    PINTEREST_CLIENT_SECRET = "";
    REDDIT_CLIENT_ID = "";
    REDDIT_CLIENT_SECRET = "";
    SLACK_ID = "";
    SLACK_SECRET = "";
    SLACK_SIGNING_SECRET = "";
    STRIPE_PUBLISHABLE_KEY = "";
    STRIPE_SECRET_KEY = "";
    STRIPE_SIGNING_KEY = "";
    STRIPE_SIGNING_KEY_CONNECT = "";
    THREADS_APP_ID = "";
    THREADS_APP_SECRET = "";
    TIKTOK_CLIENT_ID = "";
    TIKTOK_CLIENT_SECRET = "";
    X_API_KEY = "";
    X_API_SECRET = "";
    X_URL = "";
    YOUTUBE_CLIENT_ID = "";
    YOUTUBE_CLIENT_SECRET = "";
  };

  postizEnvironment = optionalProviderEnvironment // {
    BACKEND_INTERNAL_URL = "http://localhost:3000";
    DISABLE_REGISTRATION = "false";
    FRONTEND_URL = postizCfg.externalUrl;
    IS_GENERAL = "true";
    MAIN_URL = postizCfg.externalUrl;
    NEXT_PUBLIC_BACKEND_URL = "${postizCfg.externalUrl}/api";
    NEXT_PUBLIC_POSTIZ_OAUTH_DISPLAY_NAME = "Authentik";
    NEXT_PUBLIC_POSTIZ_OAUTH_LOGO_URL = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/master/png/authentik.png";
    NEXT_PUBLIC_UPLOAD_DIRECTORY = "/uploads";
    NEXT_PUBLIC_UPLOAD_STATIC_DIRECTORY = "/uploads";
    NX_ADD_PLUGINS = "false";
    POSTIZ_GENERIC_OAUTH = "true";
    POSTIZ_OAUTH_AUTH_URL = postizCfg.oidc.authorizationUrl;
    POSTIZ_OAUTH_CLIENT_ID = postizCfg.oidc.clientId;
    POSTIZ_OAUTH_SCOPE = concatStringsSep " " postizCfg.oidc.scopes;
    POSTIZ_OAUTH_TOKEN_URL = postizCfg.oidc.tokenUrl;
    POSTIZ_OAUTH_URL = postizCfg.oidc.url;
    POSTIZ_OAUTH_USERINFO_URL = postizCfg.oidc.userInfoUrl;
    REDIS_URL = "redis://postiz-redis:6379";
    RUN_CRON = "true";
    STORAGE_PROVIDER = "local";
    TEMPORAL_ADDRESS = "postiz-temporal:7233";
    UPLOAD_DIRECTORY = "/uploads";
  };
in
{
  config = mkIf (cfg.enable && postizCfg.enable) {
    assertions = map (secretName: {
      assertion = !cfg.secrets.enable || hasAttr secretName config.sops.secrets;
      message = "${secretName} must be declared as a SOPS secret when testbed secrets are enabled.";
    }) requiredSecretNames;

    boot.kernel.sysctl."vm.max_map_count" = 262144;
    systemd.tmpfiles.rules = [
      "d /run/postiz 0700 root root - -"
      "d ${postizCfg.stateDir}/nginx 0755 100 101 - -"
      "d ${postizCfg.stateDir}/nginx-logs 0755 100 101 - -"
    ];
    virtualisation.oci-containers.backend = "podman";

    virtualisation.oci-containers.containers = {
      postiz = {
        image = postizCfg.image;
        pull = "missing";
        dependsOn = [
          "postiz-postgres"
          "postiz-redis"
          "postiz-temporal"
        ];
        environment = postizEnvironment;
        environmentFiles = [ (toString postizCfg.environmentFile) ];
        ports = [ "${postizCfg.bindAddress}:${toString cfg.ports.postiz}:5000/tcp" ];
        extraOptions = [
          "--init"
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
          "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
        ];
        volumes = [
          "${postizCfg.stateDir}/config:/config"
          "${postizCfg.stateDir}/nginx:/var/lib/nginx"
          "${postizCfg.stateDir}/nginx-logs:/var/log/nginx"
          "${postizCfg.stateDir}/uploads:/uploads"
        ];
      };

      postiz-postgres = {
        image = postizCfg.postgresImage;
        pull = "missing";
        environment = {
          POSTGRES_DB = postizCfg.databaseName;
          POSTGRES_USER = postizCfg.databaseUser;
        };
        environmentFiles = [ (toString postizCfg.postgresEnvironmentFile) ];
        extraOptions = [
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${postizCfg.stateDir}/postgresql:/var/lib/postgresql/data" ];
      };

      postiz-redis = {
        image = postizCfg.redisImage;
        pull = "missing";
        extraOptions = [
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${postizCfg.stateDir}/redis:/data" ];
      };

      postiz-temporal = {
        image = postizCfg.temporal.image;
        pull = "missing";
        dependsOn = [
          "postiz-temporal-elasticsearch"
          "postiz-temporal-postgres"
        ];
        environment = {
          DB = "postgres12";
          DB_PORT = "5432";
          DYNAMIC_CONFIG_FILE_PATH = "/etc/temporal/config/dynamicconfig/development-sql.yaml";
          ENABLE_ES = "true";
          ES_SEEDS = "postiz-temporal-elasticsearch";
          ES_VERSION = "v7";
          POSTGRES_SEEDS = "postiz-temporal-postgres";
          POSTGRES_USER = "temporal";
          TEMPORAL_NAMESPACE = "default";
        };
        environmentFiles = [ (toString postizCfg.temporal.temporalEnvironmentFile) ];
        extraOptions = [
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
        ];
        volumes = [
          "${postizTemporalDynamicConfig}:/etc/temporal/config/dynamicconfig:ro"
        ];
      };

      postiz-temporal-elasticsearch = {
        image = postizCfg.temporal.elasticsearchImage;
        pull = "missing";
        environment = {
          ES_JAVA_OPTS = "-Xms256m -Xmx256m";
          "cluster.routing.allocation.disk.threshold_enabled" = "true";
          "cluster.routing.allocation.disk.watermark.flood_stage" = "128mb";
          "cluster.routing.allocation.disk.watermark.high" = "256mb";
          "cluster.routing.allocation.disk.watermark.low" = "512mb";
          "discovery.type" = "single-node";
          "xpack.security.enabled" = "false";
        };
        extraOptions = [
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${postizCfg.stateDir}/temporal/elasticsearch:/usr/share/elasticsearch/data" ];
      };

      postiz-temporal-postgres = {
        image = postizCfg.temporal.postgresImage;
        pull = "missing";
        environment = {
          POSTGRES_USER = "temporal";
        };
        environmentFiles = [ (toString postizCfg.temporal.postgresEnvironmentFile) ];
        extraOptions = [
          "--network=${postizNetwork}"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${postizCfg.stateDir}/temporal/postgresql:/var/lib/postgresql/data" ];
      };
    };

    systemd.services = {
      postiz-environment = {
        description = "Render Postiz runtime environment files from SOPS secrets";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-tmpfiles-resetup.service"
          "systemd-tmpfiles-setup.service"
        ];
        before = [
          "podman-postiz.service"
          "podman-postiz-postgres.service"
          "podman-postiz-temporal.service"
          "podman-postiz-temporal-postgres.service"
        ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        wants = [ "systemd-tmpfiles-resetup.service" ];
        path = [
          pkgs.coreutils
          pkgs.python3
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          ${renderPostizEnvironmentScript}
        '';
      };

      postiz-podman-network = {
        description = "Create the private Postiz Podman network";
        wantedBy = [ "multi-user.target" ];
        before = [
          "podman-postiz.service"
          "podman-postiz-postgres.service"
          "podman-postiz-redis.service"
          "podman-postiz-temporal.service"
          "podman-postiz-temporal-elasticsearch.service"
          "podman-postiz-temporal-postgres.service"
        ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
        };
        script = ''
          set -euo pipefail

          if ! ${podman} network exists ${escapeShellArg postizNetwork}; then
            ${podman} network create ${escapeShellArg postizNetwork}
          fi
        '';
      };

      podman-postiz = {
        after = [
          "network-online.target"
          "podman-postiz-postgres.service"
          "podman-postiz-redis.service"
          "podman-postiz-temporal.service"
          "postiz-postgresql-password.service"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "podman-postiz-postgres.service"
          "podman-postiz-redis.service"
          "podman-postiz-temporal.service"
          "postiz-postgresql-password.service"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        preStart = ''
          set -euo pipefail
          ${renderPostizEnvironmentScript}

          wait_for() {
            name="$1"
            shift
            for attempt in $(seq 1 180); do
              if "$@" >/dev/null 2>&1; then
                return 0
              fi
              if [ "$attempt" = 180 ]; then
                echo "$name did not become ready" >&2
                return 1
              fi
              sleep 1
            done
          }

          wait_for "Postiz PostgreSQL" ${podman} exec postiz-postgres pg_isready -U ${escapeShellArg postizCfg.databaseUser} -d ${escapeShellArg postizCfg.databaseName}
          wait_for "Postiz Redis" ${podman} exec postiz-redis redis-cli ping
          wait_for "Postiz Temporal" ${podman} exec postiz-temporal temporal operator cluster health --address postiz-temporal:7233
        '';
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-postiz-postgres = {
        after = [
          "network-online.target"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
        preStart = ''
          ${renderPostizEnvironmentScript}
        '';
      };

      podman-postiz-redis = {
        after = [
          "network-online.target"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-postiz-temporal = {
        after = [
          "network-online.target"
          "podman-postiz-temporal-elasticsearch.service"
          "podman-postiz-temporal-postgres.service"
          "postiz-temporal-postgresql-password.service"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "podman-postiz-temporal-elasticsearch.service"
          "podman-postiz-temporal-postgres.service"
          "postiz-temporal-postgresql-password.service"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        preStart = ''
          set -euo pipefail
          ${renderPostizEnvironmentScript}

          wait_for() {
            name="$1"
            shift
            for attempt in $(seq 1 180); do
              if "$@" >/dev/null 2>&1; then
                return 0
              fi
              if [ "$attempt" = 180 ]; then
                echo "$name did not become ready" >&2
                return 1
              fi
              sleep 1
            done
          }

          wait_for "Postiz Temporal PostgreSQL" ${podman} exec postiz-temporal-postgres pg_isready -U temporal
          wait_for "Postiz Temporal Elasticsearch" ${podman} exec postiz-temporal-elasticsearch curl -fsS "http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s"
        '';
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-postiz-temporal-elasticsearch = {
        after = [
          "network-online.target"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          LimitMEMLOCK = "infinity";
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-postiz-temporal-postgres = {
        after = [
          "network-online.target"
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "postiz-environment.service"
          "postiz-podman-network.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
        preStart = ''
          ${renderPostizEnvironmentScript}
        '';
      };

      postiz-postgresql-password = {
        description = "Set Postiz PostgreSQL role password from runtime secret";
        after = [
          "podman-postiz-postgres.service"
          "postiz-environment.service"
        ];
        before = [ "podman-postiz.service" ];
        requires = [
          "podman-postiz-postgres.service"
          "postiz-environment.service"
        ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          for attempt in $(seq 1 180); do
            if ${podman} exec postiz-postgres pg_isready -U ${escapeShellArg postizCfg.databaseUser} -d ${escapeShellArg postizCfg.databaseName}; then
              break
            fi
            if [ "$attempt" = 180 ]; then
              echo "Postiz PostgreSQL did not become ready" >&2
              exit 1
            fi
            sleep 1
          done

          password="$(cat ${escapeShellArg postizPostgresPasswordFile})"
          ${podman} exec -i postiz-postgres psql -U ${postizCfg.databaseUser} -v ON_ERROR_STOP=1 --set=secret="$password" <<'SQL'
          ALTER USER ${postizCfg.databaseUser} PASSWORD :'secret';
          SQL
        '';
      };

      postiz-temporal-postgresql-password = {
        description = "Set Postiz Temporal PostgreSQL role password from runtime secret";
        after = [
          "podman-postiz-temporal-postgres.service"
          "postiz-environment.service"
        ];
        before = [ "podman-postiz-temporal.service" ];
        requires = [
          "podman-postiz-temporal-postgres.service"
          "postiz-environment.service"
        ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          for attempt in $(seq 1 180); do
            if ${podman} exec postiz-temporal-postgres pg_isready -U temporal; then
              break
            fi
            if [ "$attempt" = 180 ]; then
              echo "Postiz Temporal PostgreSQL did not become ready" >&2
              exit 1
            fi
            sleep 1
          done

          password="$(cat ${escapeShellArg postizTemporalPostgresPasswordFile})"
          ${podman} exec -i postiz-temporal-postgres psql -U temporal -v ON_ERROR_STOP=1 --set=secret="$password" <<'SQL'
          ALTER USER temporal PASSWORD :'secret';
          SQL
        '';
      };
    };
  };
}
