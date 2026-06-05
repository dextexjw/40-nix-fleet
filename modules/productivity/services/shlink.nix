{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ../lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg secretPath serviceHosts;
in
{
  config = mkIf cfg.enable {
    virtualisation.oci-containers.containers.shlink = {
      image = "docker.io/shlinkio/shlink@sha256:1af04c6e180c09428e9fa7d2a52b39accecb0bc3ff4fc5264122add7b6f0a922";
      pull = "missing";

      environment = {
        CORS_ALLOW_ORIGIN = "http://${serviceHosts.shlinkWeb}";
        DB_DRIVER = "postgres";
        DB_HOST = "127.0.0.1";
        DB_NAME = "shlink";
        DB_PORT = "5432";
        DB_USER = "shlink";
        DEFAULT_DOMAIN = serviceHosts.shlink;
        IS_HTTPS_ENABLED = "false";
        LOGS_FORMAT = "json";
        PORT = toString cfg.ports.shlink;
        TIMEZONE = config.time.timeZone;
      };
      environmentFiles = [ (secretPath "shlink-environment") ];

      extraOptions = [
        "--cap-drop=ALL"
        "--network=host"
        "--security-opt=no-new-privileges"
      ];
    };

    virtualisation.oci-containers.containers.shlink-web = {
      image = "docker.io/shlinkio/shlink-web-client@sha256:bb5013171288cba8686588f142f3d6729e586828f7a2a93a9ac1ac66724a47ff";
      pull = "missing";

      dependsOn = [ "shlink" ];

      extraOptions = [
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
      ];

      ports = [
        "0.0.0.0:${toString cfg.ports.shlinkWeb}:8080/tcp"
      ];
    };

    systemd.services.shlink-postgresql-password = {
      description = "Set Shlink PostgreSQL password from runtime secret";
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
      ];
      serviceConfig = {
        EnvironmentFile = secretPath "shlink-environment";
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail

        : "''${DB_PASSWORD:?missing DB_PASSWORD in shlink-environment}"

        psql -v ON_ERROR_STOP=1 -v shlink_password="$DB_PASSWORD" -d postgres <<'SQL'
        ALTER ROLE shlink WITH LOGIN PASSWORD :'shlink_password';
        SQL
      '';
    };

    systemd.services.podman-shlink = {
      after = [
        "network-online.target"
        "postgresql.service"
        "postgresql-setup.service"
        "shlink-postgresql-password.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "shlink-postgresql-password.service" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.podman-shlink-web = {
      after = [
        "network-online.target"
        "podman-shlink.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };
  };
}
