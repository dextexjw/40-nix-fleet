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
  bookorbitAdmin = cfg.bookorbit.admin;
  bookorbitOidc = cfg.bookorbit.oidc;
  bookorbitPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.bcrypt
    pythonPackages.psycopg
  ]);

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

  bookorbitDeclarativeConfigScript = pkgs.writeShellScript "bookorbit-declarative-config" ''
    set -euo pipefail

    export BOOKORBIT_ADMIN_EMAIL=${escapeShellArg bookorbitAdmin.email}
    export BOOKORBIT_ADMIN_NAME=${escapeShellArg bookorbitAdmin.name}
    export BOOKORBIT_ADMIN_PASSWORD_FILE=${escapeShellArg (toString bookorbitAdmin.passwordFile)}
    export BOOKORBIT_ADMIN_USERNAME=${escapeShellArg bookorbitAdmin.username}
    export BOOKORBIT_OIDC_AUTO_PROVISION=${
      escapeShellArg (
        builtins.toJSON {
          enabled = bookorbitOidc.autoProvision;
          allowLocalLinking = bookorbitOidc.allowLocalLinking;
          defaultPermissionNames = bookorbitOidc.defaultPermissionNames;
        }
      )
    }
    export BOOKORBIT_OIDC_CLAIM_MAPPING=${escapeShellArg (builtins.toJSON bookorbitOidc.claimMapping)}
    export BOOKORBIT_OIDC_CLIENT_ID=${escapeShellArg bookorbitOidc.clientId}
    export BOOKORBIT_OIDC_CLIENT_SECRET_FILE=${escapeShellArg (toString bookorbitOidc.clientSecretFile)}
    export BOOKORBIT_OIDC_DISPLAY_NAME=${escapeShellArg bookorbitOidc.displayName}
    export BOOKORBIT_OIDC_ISSUER_URI=${escapeShellArg bookorbitOidc.issuerUri}
    export BOOKORBIT_OIDC_SCOPES=${escapeShellArg (concatStringsSep " " bookorbitOidc.scopes)}
    export BOOKORBIT_OIDC_SLUG=${escapeShellArg bookorbitOidc.slug}
    export BOOKORBIT_PORT=${escapeShellArg (toString cfg.ports.bookorbit)}
    export BOOKORBIT_POSTGRES_PASSWORD_FILE=${escapeShellArg bookorbitPostgresqlPasswordFile}

    ${lib.getExe bookorbitPython} <<'PY'
    import json
    import os
    import sys
    import time
    import urllib.error
    import urllib.request

    import bcrypt
    import psycopg
    from psycopg import sql

    api_base = f"http://127.0.0.1:{os.environ['BOOKORBIT_PORT']}/api/v1"


    def read_secret(path, label):
        try:
            value = open(path, "r", encoding="utf-8").read()
        except OSError as error:
            raise SystemExit(f"unable to read BookOrbit {label} secret {path}: {error}") from error
        value = value.strip()
        if not value:
            raise SystemExit(f"BookOrbit {label} secret is empty: {path}")
        if "\n" in value or "\r" in value:
            raise SystemExit(f"BookOrbit {label} secret must be a single line: {path}")
        return value


    def request_json(method, path, payload=None, headers=None):
        body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            f"{api_base}{path}",
            data=body,
            method=method,
            headers={
                "Content-Type": "application/json",
                **(headers or {}),
            },
        )
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read().decode("utf-8")
            return {} if not data else json.loads(data)


    def wait_for_bookorbit():
        last_error = "not checked"
        for _attempt in range(60):
            try:
                request_json("GET", "/health")
                return
            except Exception as error:
                last_error = str(error)
                time.sleep(2)
        raise SystemExit(f"BookOrbit API did not become ready: {last_error}")


    admin_username = os.environ["BOOKORBIT_ADMIN_USERNAME"]
    admin_password = read_secret(os.environ["BOOKORBIT_ADMIN_PASSWORD_FILE"], "admin password")
    oidc_client_secret = read_secret(os.environ["BOOKORBIT_OIDC_CLIENT_SECRET_FILE"], "OIDC client")
    postgres_password = read_secret(os.environ["BOOKORBIT_POSTGRES_PASSWORD_FILE"], "PostgreSQL")

    wait_for_bookorbit()

    with psycopg.connect(
        host="127.0.0.1",
        port=5432,
        dbname="bookorbit",
        user="bookorbit",
        password=postgres_password,
    ) as conn:
        with conn.transaction():
            with conn.cursor() as cur:
                cur.execute(
                    """
                    select username
                    from users
                    where lower(email) = lower(%s)
                      and lower(username) <> lower(%s)
                    """,
                    (os.environ["BOOKORBIT_ADMIN_EMAIL"], admin_username),
                )
                conflicting_email = cur.fetchone()
                if conflicting_email:
                    raise SystemExit(
                        "BookOrbit admin email is already used by another user: "
                        + conflicting_email[0]
                    )

                cur.execute(
                    """
                    select id, password_hash
                    from users
                    where lower(username) = lower(%s)
                    """,
                    (admin_username,),
                )
                row = cur.fetchone()
                if row:
                    user_id, existing_hash = row
                    password_matches = bcrypt.checkpw(
                        admin_password.encode("utf-8"),
                        existing_hash.encode("utf-8"),
                    )
                    password_hash = existing_hash if password_matches else bcrypt.hashpw(
                        admin_password.encode("utf-8"),
                        bcrypt.gensalt(rounds=12),
                    ).decode("utf-8")
                    token_increment = 0 if password_matches else 1
                    cur.execute(
                        """
                        update users
                           set username = %s,
                               name = %s,
                               email = %s,
                               password_hash = %s,
                               active = true,
                               is_superuser = true,
                               is_default_password = false,
                               token_version = token_version + %s,
                               failed_login_attempts = 0,
                               locked_until = null,
                               provisioning_method = 'local',
                               updated_at = now()
                         where id = %s
                        """,
                        (
                            admin_username,
                            os.environ["BOOKORBIT_ADMIN_NAME"],
                            os.environ["BOOKORBIT_ADMIN_EMAIL"],
                            password_hash,
                            token_increment,
                            user_id,
                        ),
                    )
                    print(f"updated BookOrbit local superuser {admin_username}")
                else:
                    password_hash = bcrypt.hashpw(
                        admin_password.encode("utf-8"),
                        bcrypt.gensalt(rounds=12),
                    ).decode("utf-8")
                    cur.execute(
                        """
                        insert into users (
                          username,
                          name,
                          email,
                          password_hash,
                          active,
                          is_superuser,
                          is_default_password,
                          provisioning_method
                        )
                        values (%s, %s, %s, %s, true, true, false, 'local')
                        """,
                        (
                            admin_username,
                            os.environ["BOOKORBIT_ADMIN_NAME"],
                            os.environ["BOOKORBIT_ADMIN_EMAIL"],
                            password_hash,
                        ),
                    )
                    print(f"created BookOrbit local superuser {admin_username}")

                cur.execute(
                    """
                    insert into app_settings (key, value, updated_at)
                    values ('initial_setup_completed_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'), now())
                    on conflict (key) do nothing
                    """
                )

                cur.execute(
                    """
                    select slug
                    from oidc_providers
                    where issuer_uri = %s
                      and slug <> %s
                    """,
                    (os.environ["BOOKORBIT_OIDC_ISSUER_URI"], os.environ["BOOKORBIT_OIDC_SLUG"]),
                )
                conflicting_provider = cur.fetchone()
                if conflicting_provider:
                    raise SystemExit(
                        "BookOrbit OIDC issuer is already used by provider slug: "
                        + conflicting_provider[0]
                    )

                cur.execute(
                    """
                    insert into oidc_providers (
                      slug,
                      display_name,
                      enabled,
                      issuer_uri,
                      client_id,
                      client_secret,
                      scopes,
                      icon_url,
                      claim_mapping,
                      auto_provision,
                      display_order,
                      created_at,
                      updated_at
                    )
                    values (
                      %s,
                      %s,
                      true,
                      %s,
                      %s,
                      %s,
                      %s,
                      null,
                      %s::jsonb,
                      %s::jsonb,
                      0,
                      now(),
                      now()
                    )
                    on conflict (slug) do update set
                      display_name = excluded.display_name,
                      enabled = true,
                      issuer_uri = excluded.issuer_uri,
                      client_id = excluded.client_id,
                      client_secret = excluded.client_secret,
                      scopes = excluded.scopes,
                      icon_url = null,
                      claim_mapping = excluded.claim_mapping,
                      auto_provision = excluded.auto_provision,
                      updated_at = now()
                    """,
                    (
                        os.environ["BOOKORBIT_OIDC_SLUG"],
                        os.environ["BOOKORBIT_OIDC_DISPLAY_NAME"],
                        os.environ["BOOKORBIT_OIDC_ISSUER_URI"],
                        os.environ["BOOKORBIT_OIDC_CLIENT_ID"],
                        oidc_client_secret,
                        os.environ["BOOKORBIT_OIDC_SCOPES"],
                        os.environ["BOOKORBIT_OIDC_CLAIM_MAPPING"],
                        os.environ["BOOKORBIT_OIDC_AUTO_PROVISION"],
                    ),
                )
                print(f"configured BookOrbit OIDC provider {os.environ['BOOKORBIT_OIDC_SLUG']}")

    login = request_json(
        "POST",
        "/auth/login",
        {
            "username": admin_username,
            "password": admin_password,
        },
    )
    user = login.get("user") or {}
    if user.get("username") != admin_username or user.get("isSuperuser") is not True:
        raise SystemExit("BookOrbit local superuser login verification failed")

    providers = request_json("GET", "/app-settings/oidc/providers/public")
    if not any(
        provider.get("slug") == os.environ["BOOKORBIT_OIDC_SLUG"]
        and provider.get("enabled") is True
        and provider.get("clientId") == os.environ["BOOKORBIT_OIDC_CLIENT_ID"]
        and provider.get("scopes") == os.environ["BOOKORBIT_OIDC_SCOPES"]
        for provider in providers
    ):
        raise SystemExit("BookOrbit public OIDC provider verification failed")

    print("BookOrbit declarative account and OIDC verification passed")
    PY
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
      bookorbit-declarative-config = mkIf bookorbitOidc.enable {
        description = "Ensure BookOrbit local admin account and Authentik OIDC provider";
        after = [
          "bookorbit-postgresql-extensions.service"
          "bookorbit-postgresql-password.service"
          "network-online.target"
          "podman-media-bookorbit.service"
          "postgresql.service"
        ];
        requires = [
          "bookorbit-postgresql-extensions.service"
          "bookorbit-postgresql-password.service"
          "podman-media-bookorbit.service"
          "postgresql.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ bookorbitDeclarativeConfigScript ];
        serviceConfig = {
          ExecStart = bookorbitDeclarativeConfigScript;
          Group = "media";
          RemainAfterExit = true;
          Type = "oneshot";
          User = "bookorbit";
        };
      };

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
