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

  sureCfg = cfg.sure;
  surePostgresqlPasswordFile = testbedLib.secretPath "sure-postgres-password";

  commonEnvironment = {
    APP_DOMAIN = "sure.jax22.com";
    AUTH_JIT_MODE = "create_and_link";
    AUTH_LOCAL_LOGIN_ENABLED = "true";
    BINDING = sureCfg.bindAddress;
    DB_HOST = "127.0.0.1";
    DB_PORT = "5432";
    EXCHANGE_RATE_PROVIDER = "yahoo_finance";
    OIDC_BUTTON_LABEL = "Sign in with Authentik";
    OIDC_CLIENT_ID = sureCfg.oidc.clientId;
    OIDC_ISSUER = sureCfg.oidc.issuerUrl;
    OIDC_REDIRECT_URI = sureCfg.oidc.redirectUri;
    ONBOARDING_STATE = "closed";
    PORT = toString cfg.ports.sure;
    POSTGRES_DB = sureCfg.databaseName;
    POSTGRES_USER = sureCfg.databaseUser;
    RAILS_ASSUME_SSL = "true";
    RAILS_FORCE_SSL = "true";
    REDIS_URL = "redis://127.0.0.1:${toString cfg.ports.sureRedis}/1";
    SECURITIES_PROVIDER = "yahoo_finance";
    SELF_HOSTED = "true";
    SMTP_ADDRESS = "127.0.0.1";
    SMTP_PASSWORD = "mailpit";
    SMTP_PORT = toString cfg.ports.mailpitSmtp;
    SMTP_TLS_ENABLED = "false";
    SMTP_USERNAME = "sure";
  };

  commonOptions = [
    "--cap-drop=ALL"
    "--init"
    "--network=host"
    "--security-opt=no-new-privileges"
    "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
  ];
in
{
  config = mkIf (cfg.enable && sureCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "sure-postgres-password" config.sops.secrets;
        message = "sure-postgres-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "sure-oidc-client-secret" config.sops.secrets;
        message = "sure-oidc-client-secret must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "sure-secret-key-base" config.sops.secrets;
        message = "sure-secret-key-base must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ sureCfg.databaseName ];
      ensureUsers = [
        {
          name = sureCfg.databaseUser;
          ensureDBOwnership = true;
        }
      ];
      authentication = mkAfter ''
        host ${sureCfg.databaseName} ${sureCfg.databaseUser} 127.0.0.1/32 scram-sha-256
      '';
      settings.listen_addresses = mkForce "127.0.0.1";
    };

    services.redis.servers.sure = {
      enable = true;
      appendOnly = true;
      bind = "127.0.0.1";
      openFirewall = false;
      port = cfg.ports.sureRedis;
      settings = {
        dir = mkForce (toString "${sureCfg.stateDir}/redis");
        maxmemory = "256mb";
        maxmemory-policy = "noeviction";
      };
    };

    virtualisation.oci-containers.containers = {
      sure-web = {
        image = sureCfg.image;
        pull = "missing";
        environment = commonEnvironment;
        environmentFiles = [ (toString sureCfg.environmentFile) ];
        volumes = [
          "${sureCfg.stateDir}/storage:/rails/storage"
        ];
        extraOptions = commonOptions;
      };

      sure-worker = {
        image = sureCfg.image;
        pull = "missing";
        cmd = [
          "bundle"
          "exec"
          "sidekiq"
        ];
        environment = commonEnvironment;
        environmentFiles = [ (toString sureCfg.environmentFile) ];
        volumes = [
          "${sureCfg.stateDir}/storage:/rails/storage"
        ];
        extraOptions = commonOptions;
      };
    };

    systemd.services = {
      sure-postgresql-password = {
        description = "Set Sure PostgreSQL role password from runtime secret";
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

          secret_file=${escapeShellArg surePostgresqlPasswordFile}
          if [ ! -r "$secret_file" ]; then
            echo "$secret_file is not readable; refusing to configure Sure PostgreSQL password" >&2
            exit 1
          fi

          IFS= read -r sure_password < "$secret_file" || [ -n "$sure_password" ]
          if [ -z "$sure_password" ]; then
            echo "Sure PostgreSQL password is empty: $secret_file" >&2
            exit 1
          fi

          psql -v ON_ERROR_STOP=1 -v sure_password="$sure_password" -d postgres <<SQL
          ALTER ROLE ${sureCfg.databaseUser} WITH LOGIN PASSWORD :'sure_password';
          SQL
        '';
      };

      podman-sure-web = {
        after = [
          "mailpit-testbed.service"
          "network-online.target"
          "postgresql.service"
          "redis-sure.service"
          "sure-postgresql-password.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "mailpit-testbed.service"
          "postgresql.service"
          "redis-sure.service"
          "sure-postgresql-password.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      podman-sure-worker = {
        after = [
          "podman-sure-web.service"
          "redis-sure.service"
          "sure-postgresql-password.service"
        ];
        requires = [
          "postgresql.service"
          "redis-sure.service"
          "sure-postgresql-password.service"
        ];
        wants = [ "podman-sure-web.service" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      redis-sure.serviceConfig = {
        ReadWritePaths = [ (toString "${sureCfg.stateDir}/redis") ];
        SupplementaryGroups = [ "testbed" ];
      };
    };
  };
}
