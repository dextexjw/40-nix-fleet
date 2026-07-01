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

  kaneoCfg = cfg.kaneo;
  kaneoPostgresqlPasswordFile = testbedLib.secretPath "kaneo-postgres-password";
in
{
  config = mkIf (cfg.enable && kaneoCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "kaneo-postgres-password" config.sops.secrets;
        message = "kaneo-postgres-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ kaneoCfg.databaseName ];
      ensureUsers = [
        {
          name = kaneoCfg.databaseUser;
          ensureDBOwnership = true;
        }
      ];
      authentication = mkAfter ''
        host ${kaneoCfg.databaseName} ${kaneoCfg.databaseUser} 127.0.0.1/32 scram-sha-256
      '';
      settings.listen_addresses = mkForce "127.0.0.1";
    };

    virtualisation.oci-containers.containers.kaneo = {
      image = kaneoCfg.image;
      pull = "missing";

      environment = {
        CUSTOM_AUTH_PKCE = "true";
        CUSTOM_OAUTH_AUTHORIZATION_URL = kaneoCfg.oidc.authorizationUrl;
        CUSTOM_OAUTH_AUTO_LOGIN = "false";
        CUSTOM_OAUTH_CLIENT_ID = kaneoCfg.oidc.clientId;
        CUSTOM_OAUTH_DISCOVERY_URL = kaneoCfg.oidc.discoveryUrl;
        CUSTOM_OAUTH_LOGOUT_URL = kaneoCfg.oidc.logoutUrl;
        CUSTOM_OAUTH_RESPONSE_TYPE = "code";
        CUSTOM_OAUTH_SCOPES = concatStringsSep "," kaneoCfg.oidc.scopes;
        CUSTOM_OAUTH_TOKEN_URL = kaneoCfg.oidc.tokenUrl;
        CUSTOM_OAUTH_USER_INFO_URL = kaneoCfg.oidc.userInfoUrl;
        DISABLE_GUEST_ACCESS = "true";
        DISABLE_PASSWORD_REGISTRATION = "true";
        DISABLE_REGISTRATION = "false";
        HOME = toString kaneoCfg.stateDir;
        KANEO_CLIENT_URL = kaneoCfg.externalUrl;
        POSTGRES_DB = kaneoCfg.databaseName;
        POSTGRES_HOST = "127.0.0.1";
        POSTGRES_PORT = "5432";
        POSTGRES_USER = kaneoCfg.databaseUser;
        S3_BUCKET = kaneoCfg.s3.bucket;
        S3_ENDPOINT = kaneoCfg.s3.endpoint;
        S3_FORCE_PATH_STYLE = boolToString kaneoCfg.s3.forcePathStyle;
        S3_REGION = kaneoCfg.s3.region;
        SMTP_FROM = "kaneo@testbed.home.arpa";
        SMTP_HOST = "127.0.0.1";
        SMTP_IGNORE_TLS = "true";
        SMTP_PORT = toString cfg.ports.mailpitSmtp;
        SMTP_REQUIRE_TLS = "false";
        SMTP_SECURE = "false";
        TMPDIR = "${kaneoCfg.stateDir}/tmp";
      };

      environmentFiles = [ (toString kaneoCfg.environmentFile) ];

      extraOptions = [
        "--cap-drop=ALL"
        "--health-cmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:${toString cfg.ports.kaneo}/api/health"
        "--health-interval=disable"
        "--health-retries=3"
        "--health-start-period=60s"
        "--health-timeout=10s"
        "--init"
        "--network=host"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp:rw,noexec,nosuid,size=256m"
      ];

      volumes = [
        "${kaneoCfg.stateDir}:${kaneoCfg.stateDir}"
      ];
    };

    systemd.services = {
      kaneo-postgresql-password = {
        description = "Set Kaneo PostgreSQL role password from runtime secret";
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

          secret_file=${escapeShellArg kaneoPostgresqlPasswordFile}
          if [ ! -r "$secret_file" ]; then
            echo "$secret_file is not readable; refusing to configure Kaneo PostgreSQL password" >&2
            exit 1
          fi

          IFS= read -r kaneo_password < "$secret_file" || [ -n "$kaneo_password" ]
          if [ -z "$kaneo_password" ]; then
            echo "Kaneo PostgreSQL password is empty: $secret_file" >&2
            exit 1
          fi

          psql -v ON_ERROR_STOP=1 -v kaneo_password="$kaneo_password" -d postgres <<'SQL'
          ALTER ROLE kaneo WITH LOGIN PASSWORD :'kaneo_password';
          SQL
        '';
      };

      podman-kaneo = {
        after = [
          "kaneo-postgresql-password.service"
          "mailpit-testbed.service"
          "network-online.target"
          "postgresql.service"
          "systemd-tmpfiles-setup.service"
        ];
        requires = [
          "kaneo-postgresql-password.service"
          "mailpit-testbed.service"
          "postgresql.service"
          "systemd-tmpfiles-setup.service"
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
