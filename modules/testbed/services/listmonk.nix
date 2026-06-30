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

  listmonkCfg = cfg.listmonk;
  oidcProviderUrl = "https://auth.jax22.com/application/o/listmonk/";
in
{
  config = mkIf cfg.enable {
    users.groups.listmonk = { };
    users.users.listmonk = {
      isSystemUser = true;
      group = "listmonk";
      home = toString listmonkCfg.stateDir;
    };

    services.mailhog = {
      enable = true;
      storage = "maildir";
      smtpPort = cfg.ports.mailhogSmtp;
      apiPort = cfg.ports.mailhog;
      uiPort = cfg.ports.mailhog;
    };

    services.postgresql = {
      enable = true;
      dataDir = "${cfg.appdataRoot}/postgresql/${config.services.postgresql.package.psqlSchema}";
    };

    services.listmonk = {
      enable = true;
      secretFile = toString listmonkCfg.adminEnvironmentFile;
      database = {
        createLocally = true;
        mutableSettings = false;
        settings = {
          "app.root_url" = listmonkCfg.externalUrl;
          "app.site_name" = "Listmonk";
          "app.from_email" = "listmonk@testbed.home.arpa";
          "app.notify_emails" = [ "admin@jax22.com" ];
          "app.check_updates" = false;
          "upload.provider" = "filesystem";
          "upload.filesystem.upload_path" = "${listmonkCfg.stateDir}/uploads";
          "upload.filesystem.upload_uri" = "/uploads";
          smtp = [
            {
              enabled = true;
              host = "127.0.0.1";
              port = cfg.ports.mailhogSmtp;
              tls_type = "none";
            }
          ];
        };
      };
      settings = {
        app = {
          address = "${listmonkCfg.bindAddress}:${toString cfg.ports.listmonk}";
          admin_username = "";
          admin_password = "";
        };
      };
    };

    systemd.services.listmonk = {
      after = [
        "mailhog.service"
        "network-online.target"
        "postgresql.service"
        "systemd-tmpfiles-setup.service"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "postgresql.service"
        "systemd-tmpfiles-setup.service"
      ];
      serviceConfig = {
        DynamicUser = mkForce false;
        Environment = [ "STATE_DIRECTORY=${cfg.appdataRoot}" ];
        ReadWritePaths = [ (toString listmonkCfg.stateDir) ];
        StateDirectory = mkForce [ ];
        UMask = mkForce "0077";
        WorkingDirectory = toString listmonkCfg.stateDir;
      };
    };

    systemd.services.listmonk-oidc-config = {
      description = "Configure Listmonk Authentik OIDC settings";
      after = [
        "listmonk.service"
        "postgresql.service"
      ];
      wants = [ "listmonk.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [
        pkgs.coreutils
        config.services.postgresql.package
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail

        secret_file=${escapeShellArg (toString listmonkCfg.oidcClientSecretFile)}
        if [ ! -r "$secret_file" ]; then
          echo "$secret_file is not readable; refusing to configure Listmonk OIDC" >&2
          exit 1
        fi

        IFS= read -r client_secret < "$secret_file" || [ -n "$client_secret" ]
        case "$client_secret" in
          *$'\n'*|*$'\r'*)
            echo "Listmonk OIDC client secret must be a single line: $secret_file" >&2
            exit 1
            ;;
        esac
        if [ -z "$client_secret" ]; then
          echo "Listmonk OIDC client secret is empty: $secret_file" >&2
          exit 1
        fi

        for attempt in $(seq 1 60); do
          if psql -d listmonk -tAc "select 1 from settings where key = 'security.oidc'" >/dev/null 2>&1; then
            break
          fi
          sleep 2
        done

        psql -d listmonk -v ON_ERROR_STOP=1 \
          -v provider_url=${escapeShellArg oidcProviderUrl} \
          -v client_secret="$client_secret" <<'SQL'
        WITH role AS (
          SELECT id
            FROM roles
           WHERE type = 'user'
             AND name = 'Super Admin'
           ORDER BY id
           LIMIT 1
        )
        UPDATE settings
           SET value = jsonb_build_object(
             'enabled', true,
             'provider_url', :'provider_url',
             'provider_name', 'Authentik',
             'client_id', 'listmonk',
             'client_secret', :'client_secret',
             'auto_create_users', true,
             'default_user_role_id', (SELECT id FROM role),
             'default_list_role_id', NULL
           )
         WHERE key = 'security.oidc';
        SQL
      '';
    };
  };
}
