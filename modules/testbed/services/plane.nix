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

  planeCfg = cfg.plane;
  podman = "${config.virtualisation.podman.package}/bin/podman";
  planeEnvironmentFile = "/run/plane/environment";
  planeAdminEnvironmentFile = "/run/plane/admin-bootstrap-environment";

  requiredSecretNames = [
    "plane-admin-email"
    "plane-admin-password"
    "plane-garage-access-key-id"
    "plane-garage-secret-access-key"
    "plane-live-server-secret-key"
    "plane-postgres-password"
    "plane-rabbitmq-password"
    "plane-secret-key"
  ];

  backendEnvironment = {
    API_KEY_RATE_LIMIT = "60/minute";
    APP_BASE_PATH = "";
    APP_BASE_URL = planeCfg.externalUrl;
    AWS_REGION = planeCfg.garageRegion;
    AWS_S3_BUCKET_NAME = planeCfg.garageBucket;
    AWS_S3_ENDPOINT_URL = planeCfg.garageEndpoint;
    CORS_ALLOWED_ORIGINS = planeCfg.externalUrl;
    DEBUG = "0";
    FILE_SIZE_LIMIT = "5242880";
    GUNICORN_WORKERS = "1";
    HARD_DELETE_AFTER_DAYS = "60";
    PGDATABASE = "plane";
    PGHOST = "127.0.0.1";
    PGPORT = "5432";
    POSTGRES_DB = "plane";
    POSTGRES_HOST = "127.0.0.1";
    POSTGRES_PORT = "5432";
    POSTGRES_USER = "plane";
    RABBITMQ_HOST = "127.0.0.1";
    RABBITMQ_PORT = toString cfg.ports.planeRabbitmq;
    RABBITMQ_USER = "plane";
    RABBITMQ_VHOST = "plane";
    REDIS_HOST = "127.0.0.1";
    REDIS_PORT = toString cfg.ports.planeRedis;
    REDIS_URL = "redis://127.0.0.1:${toString cfg.ports.planeRedis}/";
    SIGNED_URL_EXPIRATION = "3600";
    SPACE_BASE_PATH = "/spaces";
    SPACE_BASE_URL = "${planeCfg.externalUrl}/spaces";
    TRUSTED_PROXIES = "0.0.0.0/0";
    USE_MINIO = "0";
    WEB_URL = planeCfg.externalUrl;
  };

  backendEnvOptions = mapAttrsToList (
    name: value: "-e ${escapeShellArg name}=${escapeShellArg value}"
  ) backendEnvironment;

  backendRunOptions = backendEnvOptions ++ [
    "--env-file=${planeEnvironmentFile}"
    "--network=host"
    "--pull=missing"
    "--security-opt=no-new-privileges"
  ];

  planePodmanRun = name: command: extraOptions: ''
    ${podman} rm -f ${escapeShellArg name} >/dev/null 2>&1 || true
    ${podman} run --rm \
      --name=${escapeShellArg name} \
      ${concatStringsSep " \\\n        " (backendRunOptions ++ extraOptions)} \
      ${escapeShellArg planeCfg.backendImage} \
      ${command}
  '';
in
{
  config = mkIf (cfg.enable && planeCfg.enable) {
    assertions = map (secretName: {
      assertion = !cfg.secrets.enable || hasAttr secretName config.sops.secrets;
      message = "${secretName} must be declared as a SOPS secret when testbed secrets are enabled.";
    }) requiredSecretNames;

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ "plane" ];
      ensureUsers = [
        {
          name = "plane";
          ensureDBOwnership = true;
        }
      ];
      authentication = mkAfter ''
        host plane plane 127.0.0.1/32 scram-sha-256
      '';
      settings.listen_addresses = mkForce "127.0.0.1";
    };

    services.redis.servers.plane = {
      enable = true;
      appendOnly = true;
      bind = "127.0.0.1";
      openFirewall = false;
      port = cfg.ports.planeRedis;
      settings = {
        dir = mkForce (toString "${planeCfg.stateDir}/redis");
        maxmemory = "256mb";
        maxmemory-policy = "noeviction";
      };
    };

    virtualisation.oci-containers.containers = {
      plane-web = {
        image = planeCfg.frontendImage;
        pull = "missing";
        ports = [ "127.0.0.1:${toString cfg.ports.planeWeb}:3000/tcp" ];
        extraOptions = [ "--security-opt=no-new-privileges" ];
      };

      plane-admin = {
        image = planeCfg.adminImage;
        pull = "missing";
        ports = [ "127.0.0.1:${toString cfg.ports.planeAdmin}:3000/tcp" ];
        extraOptions = [ "--security-opt=no-new-privileges" ];
      };

      plane-space = {
        image = planeCfg.spaceImage;
        pull = "missing";
        ports = [ "127.0.0.1:${toString cfg.ports.planeSpace}:3000/tcp" ];
        extraOptions = [ "--security-opt=no-new-privileges" ];
      };

      plane-live = {
        image = planeCfg.liveImage;
        pull = "missing";
        environment = {
          API_BASE_URL = "http://127.0.0.1:${toString cfg.ports.planeApi}";
          CORS_ALLOWED_ORIGINS = planeCfg.externalUrl;
          LIVE_BASE_PATH = "/live";
          PORT = toString cfg.ports.planeLive;
          REDIS_HOST = "127.0.0.1";
          REDIS_PORT = toString cfg.ports.planeRedis;
          REDIS_URL = "redis://127.0.0.1:${toString cfg.ports.planeRedis}/";
        };
        environmentFiles = [ planeEnvironmentFile ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
      };

      plane-api = {
        image = planeCfg.backendImage;
        pull = "missing";
        cmd = [ "./bin/docker-entrypoint-api.sh" ];
        environment = backendEnvironment // {
          PORT = toString cfg.ports.planeApi;
        };
        environmentFiles = [ planeEnvironmentFile ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${planeCfg.stateDir}/logs/api:/code/plane/logs" ];
      };

      plane-worker = {
        image = planeCfg.backendImage;
        pull = "missing";
        cmd = [ "./bin/docker-entrypoint-worker.sh" ];
        environment = backendEnvironment;
        environmentFiles = [ planeEnvironmentFile ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${planeCfg.stateDir}/logs/worker:/code/plane/logs" ];
      };

      plane-beat-worker = {
        image = planeCfg.backendImage;
        pull = "missing";
        cmd = [ "./bin/docker-entrypoint-beat.sh" ];
        environment = backendEnvironment;
        environmentFiles = [ planeEnvironmentFile ];
        extraOptions = [
          "--network=host"
          "--security-opt=no-new-privileges"
        ];
        volumes = [ "${planeCfg.stateDir}/logs/beat-worker:/code/plane/logs" ];
      };

      plane-rabbitmq = {
        image = planeCfg.rabbitmqImage;
        pull = "missing";
        environment = {
          RABBITMQ_DEFAULT_USER = "plane";
          RABBITMQ_DEFAULT_VHOST = "plane";
        };
        environmentFiles = [ planeEnvironmentFile ];
        ports = [ "127.0.0.1:${toString cfg.ports.planeRabbitmq}:5672/tcp" ];
        volumes = [ "${planeCfg.stateDir}/rabbitmq:/var/lib/rabbitmq" ];
      };

    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      virtualHosts.${cfg.serviceHosts.plane} = {
        default = true;
        listen = [
          {
            addr = planeCfg.bindAddress;
            port = cfg.ports.plane;
          }
        ];
        locations = {
          "= /god-mode".extraConfig = "return 308 /god-mode/;";
          "= /spaces".extraConfig = "return 308 /spaces/;";
          "/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeWeb}";
            proxyWebsockets = true;
          };
          "/api/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeApi}";
            proxyWebsockets = true;
          };
          "/auth/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeApi}";
            proxyWebsockets = true;
          };
          "/god-mode/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeAdmin}";
            proxyWebsockets = true;
          };
          "/live/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeLive}";
            proxyWebsockets = true;
          };
          "/spaces/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeSpace}";
            proxyWebsockets = true;
          };
          "/static/" = {
            proxyPass = "http://127.0.0.1:${toString cfg.ports.planeApi}";
            proxyWebsockets = true;
          };
        };
        extraConfig = ''
          client_max_body_size 5m;
        '';
      };
    };

    systemd.services = {
      plane-environment = {
        description = "Render Plane runtime environment files from SOPS secrets";
        wantedBy = [ "multi-user.target" ];
        before = [
          "plane-postgresql-password.service"
          "podman-plane-api.service"
          "podman-plane-beat-worker.service"
          "podman-plane-live.service"
          "podman-plane-rabbitmq.service"
          "podman-plane-worker.service"
          "plane-admin-bootstrap.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
        ];
        path = [
          pkgs.coreutils
          pkgs.python3
        ];
        serviceConfig = {
          RemainAfterExit = true;
          RuntimeDirectory = "plane";
          RuntimeDirectoryMode = "0700";
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
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

          secret_key = read_secret("${planeCfg.secretKeyFile}", "plane-secret-key")
          live_secret = read_secret("${planeCfg.liveServerSecretKeyFile}", "plane-live-server-secret-key")
          postgres_password = read_secret("${planeCfg.postgresPasswordFile}", "plane-postgres-password")
          rabbitmq_password = read_secret("${planeCfg.rabbitmqPasswordFile}", "plane-rabbitmq-password")
          garage_access_key = read_secret("${planeCfg.garageAccessKeyFile}", "plane-garage-access-key-id")
          garage_secret_key = read_secret("${planeCfg.garageSecretKeyFile}", "plane-garage-secret-access-key")
          admin_email = read_secret("${planeCfg.adminEmailFile}", "plane-admin-email")
          admin_password = read_secret("${planeCfg.adminPasswordFile}", "plane-admin-password")

          database_url = "postgresql://plane:" + quote(postgres_password, safe="") + "@127.0.0.1:5432/plane"

          env = {
              "AWS_ACCESS_KEY_ID": garage_access_key,
              "AWS_SECRET_ACCESS_KEY": garage_secret_key,
              "DATABASE_URL": database_url,
              "LIVE_SERVER_SECRET_KEY": live_secret,
              "PGPASSWORD": postgres_password,
              "POSTGRES_PASSWORD": postgres_password,
              "RABBITMQ_DEFAULT_PASS": rabbitmq_password,
              "RABBITMQ_PASSWORD": rabbitmq_password,
              "SECRET_KEY": secret_key,
          }
          admin_env = {
              "PLANE_ADMIN_EMAIL": admin_email,
              "PLANE_ADMIN_PASSWORD": admin_password,
          }

          def write_env(path, values):
              tmp = Path(str(path) + ".tmp")
              tmp.write_text("".join(f"{key}={value}\n" for key, value in sorted(values.items())))
              tmp.chmod(0o400)
              tmp.replace(path)

          run_dir = Path("/run/plane")
          run_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
          write_env(run_dir / "environment", env)
          write_env(run_dir / "admin-bootstrap-environment", admin_env)
          PY
        '';
      };

      plane-postgresql-password = {
        description = "Set Plane PostgreSQL role password from runtime secret";
        after = [
          "plane-environment.service"
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "plane-environment.service"
          "postgresql.service"
          "postgresql-setup.service"
        ];
        path = [
          config.services.postgresql.package
          pkgs.coreutils
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
        script = ''
          set -euo pipefail

          secret_file=${escapeShellArg (toString planeCfg.postgresPasswordFile)}
          if [ ! -r "$secret_file" ]; then
            echo "$secret_file is not readable; refusing to configure Plane PostgreSQL password" >&2
            exit 1
          fi

          IFS= read -r plane_password < "$secret_file" || [ -n "$plane_password" ]
          if [ -z "$plane_password" ]; then
            echo "Plane PostgreSQL password is empty: $secret_file" >&2
            exit 1
          fi

          psql -v ON_ERROR_STOP=1 -v plane_password="$plane_password" -d postgres <<'SQL'
          ALTER ROLE plane WITH LOGIN PASSWORD :'plane_password';
          SQL
        '';
      };

      plane-migrate = {
        description = "Run Plane database migrations";
        after = [
          "network-online.target"
          "plane-environment.service"
          "plane-postgresql-password.service"
          "postgresql.service"
          "redis-plane.service"
        ];
        requires = [
          "plane-environment.service"
          "plane-postgresql-password.service"
          "postgresql.service"
          "redis-plane.service"
        ];
        wants = [ "network-online.target" ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = planePodmanRun "plane-migrate" "./bin/docker-entrypoint-migrator.sh" [
          "-v ${escapeShellArg "${planeCfg.stateDir}/logs/migrator:/code/plane/logs"}"
        ];
      };

      plane-rabbitmq-config = {
        description = "Ensure Plane RabbitMQ vhost, user, and permissions";
        after = [
          "plane-environment.service"
          "podman-plane-rabbitmq.service"
        ];
        requires = [
          "plane-environment.service"
          "podman-plane-rabbitmq.service"
        ];
        wantedBy = [ "multi-user.target" ];
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

          set -a
          . ${escapeShellArg planeEnvironmentFile}
          set +a

          : "''${RABBITMQ_PASSWORD:?missing RABBITMQ_PASSWORD in ${planeEnvironmentFile}}"

          for attempt in $(seq 1 120); do
            if ${podman} exec plane-rabbitmq rabbitmq-diagnostics -q check_running >/dev/null 2>&1; then
              break
            fi
            if [ "$attempt" = 120 ]; then
              echo "Plane RabbitMQ did not become ready" >&2
              exit 1
            fi
            sleep 1
          done

          ${podman} exec plane-rabbitmq rabbitmqctl add_vhost plane >/dev/null 2>&1 || true
          if ! ${podman} exec plane-rabbitmq rabbitmqctl change_password plane "$RABBITMQ_PASSWORD" >/dev/null 2>&1; then
            ${podman} exec plane-rabbitmq rabbitmqctl add_user plane "$RABBITMQ_PASSWORD" >/dev/null
          fi
          ${podman} exec plane-rabbitmq rabbitmqctl set_permissions -p plane plane '.*' '.*' '.*' >/dev/null
        '';
      };

      plane-admin-bootstrap = {
        description = "Create Plane initial instance admin from runtime secrets";
        after = [
          "plane-environment.service"
          "plane-migrate.service"
          "podman-plane-api.service"
        ];
        requires = [
          "plane-environment.service"
          "plane-migrate.service"
          "podman-plane-api.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          config.virtualisation.podman.package
          pkgs.coreutils
          pkgs.curl
        ];
        serviceConfig = {
          RemainAfterExit = true;
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail

          for attempt in $(seq 1 120); do
            if curl -fsS --max-time 5 http://127.0.0.1:${toString cfg.ports.planeApi}/api/instances/ >/dev/null; then
              break
            fi
            if [ "$attempt" = 120 ]; then
              echo "Plane API did not become ready" >&2
              exit 1
            fi
            sleep 1
          done

          cat > /run/plane/admin-bootstrap.py <<'PY'
          import os
          import uuid

          from django.contrib.auth.hashers import make_password
          from django.utils import timezone

          from plane.db.models import Profile, User
          from plane.license.models import Instance, InstanceAdmin

          email = os.environ["PLANE_ADMIN_EMAIL"].strip().lower()
          password = os.environ["PLANE_ADMIN_PASSWORD"]

          if InstanceAdmin.objects.exists():
              raise SystemExit(0)

          instance = Instance.objects.last()
          if instance is None:
              raise SystemExit("Plane instance is not registered")

          user = User.objects.filter(email=email).first()
          if user is None:
              user = User.objects.create(
                  first_name="Plane",
                  last_name="Admin",
                  email=email,
                  username=uuid.uuid4().hex,
                  password=make_password(password),
                  is_password_autoset=False,
              )
              Profile.objects.get_or_create(user=user, defaults={"company_name": "Plane"})
          else:
              user.password = make_password(password)
              user.is_password_autoset = False

          user.is_active = True
          user.is_email_verified = True
          user.last_active = timezone.now()
          user.token_updated_at = timezone.now()
          user.save()

          InstanceAdmin.objects.get_or_create(user=user, instance=instance, defaults={"role": 20})
          instance.is_setup_done = True
          instance.instance_name = "Plane"
          instance.is_telemetry_enabled = False
          instance.save()
          PY

          ${planePodmanRun "plane-admin-bootstrap"
            "python manage.py shell -c \"$(${pkgs.coreutils}/bin/cat /run/plane/admin-bootstrap.py)\""
            [
              "--env-file=${planeAdminEnvironmentFile}"
            ]
          }
        '';
      };

      podman-plane-api = {
        after = [
          "network-online.target"
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-plane-worker = {
        after = [
          "network-online.target"
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-api.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-api.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-plane-beat-worker = {
        after = [
          "network-online.target"
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-api.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "plane-environment.service"
          "plane-migrate.service"
          "plane-rabbitmq-config.service"
          "podman-plane-api.service"
          "podman-plane-rabbitmq.service"
          "postgresql.service"
          "redis-plane.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-plane-live = {
        after = [
          "network-online.target"
          "plane-environment.service"
          "podman-plane-api.service"
          "redis-plane.service"
        ];
        requires = [
          "plane-environment.service"
          "podman-plane-api.service"
          "redis-plane.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig.RestartSec = "30s";
      };

      podman-plane-rabbitmq = {
        after = [
          "plane-environment.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "plane-environment.service"
          "systemd-tmpfiles-setup.service"
        ];
        serviceConfig.RestartSec = "30s";
      };

      nginx = {
        after = [
          "podman-plane-admin.service"
          "podman-plane-api.service"
          "podman-plane-live.service"
          "podman-plane-space.service"
          "podman-plane-web.service"
        ];
        wants = [
          "podman-plane-admin.service"
          "podman-plane-api.service"
          "podman-plane-live.service"
          "podman-plane-space.service"
          "podman-plane-web.service"
        ];
      };

      redis-plane.serviceConfig = {
        ReadWritePaths = [ (toString "${planeCfg.stateDir}/redis") ];
        SupplementaryGroups = [ "testbed" ];
      };
    };
  };
}
