{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib)
    cfg
    secretPath
    serviceHosts
    ;

  affineCfg = cfg.affine;
  affineEnvFile = "/run/affine/environment";
  affineSecretFile = secretPath "affine-environment";
  podman = "${config.virtualisation.podman.package}/bin/podman";

  affineEnvironment = {
    AFFINE_INDEXER_ENABLED = "false";
    AFFINE_SERVER_EXTERNAL_URL = affineCfg.externalUrl;
    AFFINE_SERVER_HOST = serviceHosts.affine;
    AFFINE_SERVER_HTTPS = "true";
    AFFINE_SERVER_PORT = toString cfg.ports.affine;
    NODE_ENV = "production";
    REDIS_SERVER_DATABASE = toString affineCfg.redisDatabase;
    REDIS_SERVER_HOST = "127.0.0.1";
    REDIS_SERVER_PORT = toString cfg.ports.affineRedis;
  };

  mkEnvOption = name: value: "-e ${escapeShellArg name}=${escapeShellArg value}";
  affinePodmanResourceOptions = [
    "--cpus=${affineCfg.resources.cpus}"
    "--memory=${affineCfg.resources.memory}"
    "--memory-swap=${affineCfg.resources.memorySwap}"
  ];
  affineEnvOptions = mapAttrsToList mkEnvOption affineEnvironment;
  affineMigrationOptions =
    affineEnvOptions
    ++ [
      "--cap-drop=ALL"
      "--env-file=${affineEnvFile}"
      "--init"
      "--network=host"
      "--security-opt=no-new-privileges"
    ]
    ++ affinePodmanResourceOptions
    ++ [
      "-v ${escapeShellArg "${affineCfg.stateDir}/storage:/root/.affine/storage"}"
      "-v ${escapeShellArg "${affineCfg.stateDir}/config:/root/.affine/config"}"
    ];

  affineEnvScript = pkgs.writeShellScript "affine-env" ''
    set -euo pipefail

    if [ ! -r ${escapeShellArg affineSecretFile} ]; then
      echo "${affineSecretFile} is not readable; refusing to start AFFiNE" >&2
      exit 1
    fi

    set -a
    . ${escapeShellArg affineSecretFile}
    set +a

    : "''${DB_PASSWORD:?missing DB_PASSWORD in affine-environment}"

    database_url="$(AFFINE_DB_PASSWORD="$DB_PASSWORD" ${lib.getExe pkgs.python3} -c 'import os, urllib.parse; print("postgresql://${affineCfg.databaseUser}:" + urllib.parse.quote(os.environ["AFFINE_DB_PASSWORD"], safe="") + "@127.0.0.1:5432/${affineCfg.databaseName}", end="")')"

    install -d -m 0700 -o root -g root /run/affine
    tmp="$(mktemp /run/affine/.environment.XXXXXX)"
    trap 'rm -f "$tmp"' EXIT

    {
      printf 'DATABASE_URL=%s\n' "$database_url"
    } > "$tmp"

    chown root:root "$tmp"
    chmod 0400 "$tmp"
    mv "$tmp" ${escapeShellArg affineEnvFile}
    trap - EXIT
  '';

  affineMigrationScript = pkgs.writeShellScript "affine-migration" ''
    set -euo pipefail

    ${affineEnvScript}

    ${podman} rm -f affine_migration_job >/dev/null 2>&1 || true
    ${podman} run --rm \
      --name=affine_migration_job \
      --pull=missing \
      ${concatStringsSep " \\\n      " affineMigrationOptions} \
      ${escapeShellArg affineCfg.image} \
      sh -c 'node ./scripts/self-host-predeploy.js'
  '';
in
{
  config = mkIf (cfg.enable && affineCfg.enable) {
    services.redis.servers.affine = {
      enable = true;
      appendOnly = false;
      bind = "127.0.0.1";
      openFirewall = false;
      port = cfg.ports.affineRedis;
      save = [ ];
      settings = {
        maxmemory = "128mb";
        maxmemory-policy = "allkeys-lru";
      };
    };

    virtualisation.oci-containers.containers.affine = {
      image = affineCfg.image;
      pull = "missing";

      environment = affineEnvironment;
      environmentFiles = [ affineEnvFile ];

      extraOptions = [
        "--cap-drop=ALL"
        "--init"
        "--network=host"
        "--security-opt=no-new-privileges"
      ]
      ++ affinePodmanResourceOptions;

      volumes = [
        "${affineCfg.stateDir}/storage:/root/.affine/storage"
        "${affineCfg.stateDir}/config:/root/.affine/config"
      ];
    };

    systemd.services = {
      affine-postgresql-extensions = {
        description = "Install AFFiNE PostgreSQL extensions";
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

          psql -d ${escapeShellArg affineCfg.databaseName} -v ON_ERROR_STOP=1 <<'SQL'
          CREATE EXTENSION IF NOT EXISTS vector;
          SQL
        '';
      };

      affine-postgresql-password = {
        description = "Set AFFiNE PostgreSQL role password from runtime secret";
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
          EnvironmentFile = affineSecretFile;
          Type = "oneshot";
          User = "postgres";
          Group = "postgres";
        };
        script = ''
          set -euo pipefail

          : "''${DB_PASSWORD:?missing DB_PASSWORD in affine-environment}"

          psql -v ON_ERROR_STOP=1 -v affine_password="$DB_PASSWORD" -d postgres <<'SQL'
          ALTER ROLE ${affineCfg.databaseUser} WITH LOGIN PASSWORD :'affine_password';
          SQL
        '';
      };

      podman-affine = {
        after = [
          "affine-postgresql-extensions.service"
          "affine-postgresql-password.service"
          "network-online.target"
          "postgresql.service"
          "redis-affine.service"
        ];
        preStart = "${affineMigrationScript}";
        requires = [
          "affine-postgresql-extensions.service"
          "affine-postgresql-password.service"
          "postgresql.service"
          "redis-affine.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };
    };
  };
}
