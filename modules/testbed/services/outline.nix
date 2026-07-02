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

  outlineCfg = cfg.outline;
  outlinePostgresqlPasswordFile = testbedLib.secretPath "outline-postgres-password";
in
{
  config = mkIf (cfg.enable && outlineCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-postgres-password" config.sops.secrets;
        message = "outline-postgres-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-secret-key" config.sops.secrets;
        message = "outline-secret-key must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-utils-secret" config.sops.secrets;
        message = "outline-utils-secret must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-oidc-client-secret" config.sops.secrets;
        message = "outline-oidc-client-secret must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-garage-access-key-id" config.sops.secrets;
        message = "outline-garage-access-key-id must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "outline-garage-secret-access-key" config.sops.secrets;
        message = "outline-garage-secret-access-key must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ outlineCfg.databaseName ];
      ensureUsers = [
        {
          name = outlineCfg.databaseUser;
          ensureDBOwnership = true;
        }
      ];
      authentication = mkAfter ''
        host ${outlineCfg.databaseName} ${outlineCfg.databaseUser} 127.0.0.1/32 scram-sha-256
      '';
      settings.listen_addresses = mkForce "127.0.0.1";
    };

    services.redis.servers.outline = {
      enable = true;
      appendOnly = true;
      bind = "127.0.0.1";
      openFirewall = false;
      port = cfg.ports.outlineRedis;
      settings = {
        dir = mkForce (toString "${outlineCfg.stateDir}/redis");
        maxmemory = "256mb";
        maxmemory-policy = "noeviction";
      };
    };

    virtualisation.oci-containers.containers.outline = {
      image = outlineCfg.image;
      pull = "missing";

      environment = {
        AWS_REGION = outlineCfg.s3.region;
        AWS_S3_ACL = "private";
        AWS_S3_FORCE_PATH_STYLE = boolToString outlineCfg.s3.forcePathStyle;
        AWS_S3_UPLOAD_BUCKET_NAME = outlineCfg.s3.bucket;
        AWS_S3_UPLOAD_BUCKET_URL = outlineCfg.s3.endpoint;
        CDN_URL = outlineCfg.externalUrl;
        FILE_STORAGE = "s3";
        FORCE_HTTPS = "false";
        OIDC_AUTH_URI = outlineCfg.oidc.authorizationUrl;
        OIDC_CLIENT_ID = outlineCfg.oidc.clientId;
        OIDC_DISPLAY_NAME = "Authentik";
        OIDC_LOGOUT_URI = outlineCfg.oidc.logoutUrl;
        OIDC_SCOPES = concatStringsSep " " outlineCfg.oidc.scopes;
        OIDC_TOKEN_URI = outlineCfg.oidc.tokenUrl;
        OIDC_USERNAME_CLAIM = "preferred_username";
        OIDC_USERINFO_URI = outlineCfg.oidc.userInfoUrl;
        PGSSLMODE = "disable";
        PORT = toString cfg.ports.outline;
        REDIS_URL = "redis://127.0.0.1:${toString cfg.ports.outlineRedis}";
        SMTP_DISABLE_STARTTLS = "true";
        SMTP_FROM_EMAIL = "outline@testbed.home.arpa";
        SMTP_HOST = "127.0.0.1";
        SMTP_NAME = "testbed-vm";
        SMTP_PORT = toString cfg.ports.mailpitSmtp;
        SMTP_SECURE = "false";
        URL = outlineCfg.externalUrl;
        WEB_CONCURRENCY = "1";
      };

      environmentFiles = [ (toString outlineCfg.environmentFile) ];

      extraOptions = [
        "--cap-drop=ALL"
        "--health-cmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:${toString cfg.ports.outline}/_health"
        "--health-interval=disable"
        "--health-retries=3"
        "--health-start-period=90s"
        "--health-timeout=10s"
        "--init"
        "--network=host"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
      ];

      volumes = [
        "${outlineCfg.stateDir}:${outlineCfg.stateDir}"
      ];
    };

    systemd.services = {
      outline-postgresql-password = {
        description = "Set Outline PostgreSQL role password from runtime secret";
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

          secret_file=${escapeShellArg outlinePostgresqlPasswordFile}
          if [ ! -r "$secret_file" ]; then
            echo "$secret_file is not readable; refusing to configure Outline PostgreSQL password" >&2
            exit 1
          fi

          IFS= read -r outline_password < "$secret_file" || [ -n "$outline_password" ]
          if [ -z "$outline_password" ]; then
            echo "Outline PostgreSQL password is empty: $secret_file" >&2
            exit 1
          fi

          psql -v ON_ERROR_STOP=1 -v outline_password="$outline_password" -d postgres <<SQL
          ALTER ROLE ${outlineCfg.databaseUser} WITH LOGIN PASSWORD :'outline_password';
          SQL
        '';
      };

      podman-outline = {
        after = [
          "mailpit-testbed.service"
          "network-online.target"
          "outline-postgresql-password.service"
          "postgresql.service"
          "redis-outline.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "mailpit-testbed.service"
          "outline-postgresql-password.service"
          "postgresql.service"
          "redis-outline.service"
          "systemd-tmpfiles-setup.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RestartSec = "30s";
          UMask = "0077";
        };
      };

      redis-outline.serviceConfig = {
        ReadWritePaths = [ (toString "${outlineCfg.stateDir}/redis") ];
        SupplementaryGroups = [ "testbed" ];
      };
    };
  };
}
