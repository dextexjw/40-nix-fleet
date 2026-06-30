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

  keeperCfg = cfg.keeper;
  keeperPostgresqlPasswordFile = testbedLib.secretPath "keeper-postgres-password";
  privateResolutionWhitelist = concatStringsSep "," keeperCfg.privateResolutionWhitelist;
in
{
  config = mkIf (cfg.enable && keeperCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "keeper-postgres-password" config.sops.secrets;
        message = "keeper-postgres-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ "keeper" ];
      ensureUsers = [
        {
          name = "keeper";
          ensureDBOwnership = true;
        }
      ];
      authentication = mkAfter ''
        host keeper keeper 127.0.0.1/32 scram-sha-256
      '';
      settings.listen_addresses = mkForce "127.0.0.1";
    };

    services.redis.servers.keeper = {
      enable = true;
      appendOnly = false;
      bind = "127.0.0.1";
      openFirewall = false;
      port = cfg.ports.keeperRedis;
      save = [ ];
      settings = {
        dir = mkForce (toString "${keeperCfg.stateDir}/redis");
        maxmemory = "128mb";
        maxmemory-policy = "noeviction";
      };
    };

    virtualisation.oci-containers.containers.keeper = {
      image = keeperCfg.image;
      pull = "missing";

      environment = {
        API_PORT = toString cfg.ports.keeperApi;
        BLOCK_PRIVATE_RESOLUTION = boolToString keeperCfg.blockPrivateResolution;
        ENV = "production";
        PORT = toString cfg.ports.keeper;
        PRIVATE_RESOLUTION_WHITELIST = privateResolutionWhitelist;
        VITE_API_URL = "http://127.0.0.1:${toString cfg.ports.keeperApi}";
        WORKER_JOB_QUEUE_ENABLED = "true";
      };

      environmentFiles = [ (toString keeperCfg.environmentFile) ];

      extraOptions = [
        "--cap-drop=ALL"
        "--network=host"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
      ];
    };

    systemd.services = {
      keeper-postgresql-password = {
        description = "Set Keeper PostgreSQL role password from runtime secret";
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
          Group = "postgres";
        };
        script = ''
          set -euo pipefail

          secret_file=${escapeShellArg keeperPostgresqlPasswordFile}
          if [ ! -r "$secret_file" ]; then
            echo "$secret_file is not readable; refusing to configure Keeper PostgreSQL password" >&2
            exit 1
          fi

          IFS= read -r keeper_password < "$secret_file" || [ -n "$keeper_password" ]
          if [ -z "$keeper_password" ]; then
            echo "Keeper PostgreSQL password is empty: $secret_file" >&2
            exit 1
          fi

          psql -v ON_ERROR_STOP=1 -v keeper_password="$keeper_password" -d postgres <<'SQL'
          ALTER ROLE keeper WITH LOGIN PASSWORD :'keeper_password';
          SQL
        '';
      };

      podman-keeper = {
        after = [
          "keeper-postgresql-password.service"
          "network-online.target"
          "postgresql.service"
          "redis-keeper.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "keeper-postgresql-password.service"
          "postgresql.service"
          "redis-keeper.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      redis-keeper.serviceConfig = {
        ReadWritePaths = [ (toString "${keeperCfg.stateDir}/redis") ];
        SupplementaryGroups = [ "testbed" ];
      };
    };
  };
}
