{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  mediaLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (mediaLib) cfg appdata mediaRoot;

  bookorbitEnvFile = "/run/bookorbit/bookorbit.env";
  bookorbitPostgresqlDataDir = "${appdata}/bookorbit/postgresql/${config.services.postgresql.package.psqlSchema}";
  bookorbitPostgresqlPasswordFile = toString cfg.bookorbit.postgresPasswordFile;

  bookorbitEnvScript = pkgs.writeShellScript "bookorbit-env" ''
    set -euo pipefail

    install -d -m 0750 -o root -g media /run/bookorbit
    tmp="$(mktemp /run/bookorbit/.bookorbit.XXXXXX.env)"
    trap 'rm -f "$tmp"' EXIT

    read_secret() {
      local path="$1"
      local name="$2"
      local value

      if [ ! -r "$path" ]; then
        echo "$path is not readable; refusing to start BookOrbit" >&2
        exit 1
      fi

      value="$(cat "$path")"
      case "$value" in
        *$'\n'*|*$'\r'*)
          echo "BookOrbit $name secret must be a single line: $path" >&2
          exit 1
          ;;
      esac

      if [ -z "$value" ]; then
        echo "BookOrbit $name secret is empty: $path" >&2
        exit 1
      fi

      printf '%s' "$value"
    }

    write_secret_env() {
      local name="$1"
      local path="$2"
      local value

      value="$(read_secret "$path" "$name")"
      printf '%s=%s\n' "$name" "$value" >> "$tmp"
    }

    postgres_password="$(read_secret ${escapeShellArg bookorbitPostgresqlPasswordFile} POSTGRES_PASSWORD)"
    database_url="$(BOOKORBIT_POSTGRES_PASSWORD="$postgres_password" ${lib.getExe pkgs.python3} -c 'import os, urllib.parse; print("postgres://bookorbit:" + urllib.parse.quote(os.environ["BOOKORBIT_POSTGRES_PASSWORD"], safe="") + "@127.0.0.1:5432/bookorbit", end="")')"
    printf 'POSTGRES_PASSWORD=%s\n' "$postgres_password" >> "$tmp"
    printf 'DATABASE_URL=%s\n' "$database_url" >> "$tmp"

    write_secret_env JWT_SECRET ${escapeShellArg (toString cfg.bookorbit.jwtSecretFile)}
    write_secret_env SETUP_BOOTSTRAP_TOKEN ${escapeShellArg (toString cfg.bookorbit.setupBootstrapTokenFile)}
    write_secret_env EMAIL_ENCRYPTION_KEY ${escapeShellArg (toString cfg.bookorbit.emailEncryptionKeyFile)}
    write_secret_env MIGRATION_ENCRYPTION_KEY ${escapeShellArg (toString cfg.bookorbit.migrationEncryptionKeyFile)}

    chown root:media "$tmp"
    chmod 0640 "$tmp"
    mv "$tmp" ${escapeShellArg bookorbitEnvFile}
    trap - EXIT
  '';
in
{
  config = mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      package = pkgs.postgresql_16.withPackages (postgresqlPackages: [
        postgresqlPackages.pgvector
      ]);
      dataDir = bookorbitPostgresqlDataDir;
      ensureDatabases = [ "bookorbit" ];
      ensureUsers = [
        {
          name = "bookorbit";
          ensureDBOwnership = true;
        }
      ];
      settings = {
        listen_addresses = mkForce "127.0.0.1";
        password_encryption = "scram-sha-256";
      };
      authentication = mkAfter ''
        host bookorbit bookorbit 127.0.0.1/32 scram-sha-256
      '';
    };

    virtualisation.oci-containers.containers.media-bookorbit = {
      image = cfg.bookorbit.image;
      pull = "missing";

      environment = {
        APP_URL = "https://bookorbit.jax22.com";
        APP_PORT = toString cfg.ports.bookorbit;
        BOOKORBIT_FIX_PERMISSIONS = "true";
        CLIENT_URL = "https://bookorbit.jax22.com";
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        NODE_MAX_OLD_SPACE_SIZE = "2048";
        OIDC_ALLOW_LOCAL_ISSUERS = "true";
        PGID = toString config.users.groups.media.gid;
        POSTGRES_DB = "bookorbit";
        POSTGRES_HOST = "127.0.0.1";
        POSTGRES_PORT = "5432";
        POSTGRES_USER = "bookorbit";
        PORT = toString cfg.ports.bookorbit;
        PUID = toString config.users.users.bookorbit.uid;
        TZ = config.time.timeZone;
      };

      environmentFiles = [ bookorbitEnvFile ];

      volumes = [
        "${appdata}/bookorbit/data:/data"
        "${cfg.libraries.books}:/books"
      ];

      extraOptions = [
        "--cap-add=CHOWN"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=FOWNER"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-drop=ALL"
        "--init"
        "--network=host"
        "--read-only"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
      ];
    };

    systemd.services = {
      bookorbit-postgresql-password = {
        description = "Set BookOrbit PostgreSQL role password";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        path = [
          config.services.postgresql.package
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
        };
        script = ''
          set -euo pipefail

          password="$(<${escapeShellArg bookorbitPostgresqlPasswordFile})"
          escaped="$(${lib.getExe pkgs.python3} -c 'import sys; print(sys.stdin.read().replace(chr(39), chr(39) * 2), end="")' <<<"$password")"
          printf "ALTER ROLE bookorbit WITH PASSWORD '%s';\n" "$escaped" | psql -d postgres
        '';
      };

      bookorbit-postgresql-extensions = {
        description = "Install BookOrbit PostgreSQL extensions";
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        requires = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        path = [ config.services.postgresql.package ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
        };
        script = ''
          set -euo pipefail

          psql -d bookorbit -v ON_ERROR_STOP=1 <<'SQL'
          CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
          CREATE EXTENSION IF NOT EXISTS pg_trgm;
          CREATE EXTENSION IF NOT EXISTS vector;
          SQL
        '';
      };

      podman-media-bookorbit = {
        after = [
          "bookorbit-postgresql-extensions.service"
          "bookorbit-postgresql-password.service"
          "network-online.target"
          "postgresql.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        preStart = ''
          ${bookorbitEnvScript}
        '';
        requires = [
          "bookorbit-postgresql-extensions.service"
          "bookorbit-postgresql-password.service"
          "postgresql.service"
          "${utils.escapeSystemdPath mediaRoot}.mount"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      postgresql.serviceConfig.ReadWritePaths = [ "${appdata}/bookorbit/postgresql" ];
    };
  };
}
