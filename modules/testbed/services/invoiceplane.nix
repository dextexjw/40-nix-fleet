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
  inherit (testbedLib)
    cfg
    secretPath
    serviceHostAliases
    serviceHosts
    ;

  invoiceplaneCfg = cfg.invoiceplane;
  invoiceplanePackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "invoiceplane";
    version = "1.7.1";

    src = pkgs.fetchurl {
      url = "https://github.com/InvoicePlane/InvoicePlane/releases/download/v1.7.1/v1.7.1.zip";
      hash = "sha256-yju3DNFLM7KJHgYWEzU42r+Ioi1FBjHatbq1kFhXxHE=";
    };

    nativeBuildInputs = [ pkgs.unzip ];

    unpackPhase = ''
      runHook preUnpack
      unzip "$src"
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/invoiceplane"
      cp -a ip/. "$out/share/invoiceplane/"
      runHook postInstall
    '';
  };

  runtimeRoot = "${invoiceplaneCfg.stateDir}/www";
  dbPasswordFile = secretPath "invoiceplane-db-password";
  phpPackage = pkgs.php84.withExtensions (
    { enabled, all }:
    enabled
    ++ (with all; [
      curl
      gd
      intl
      mbstring
      mysqli
      pdo_mysql
      zip
    ])
  );
in
{
  config = mkIf (cfg.enable && invoiceplaneCfg.enable) {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "invoiceplane-db-password" config.sops.secrets;
        message = "invoiceplane-db-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "invoiceplane-admin-email" config.sops.secrets;
        message = "invoiceplane-admin-email must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "invoiceplane-admin-password" config.sops.secrets;
        message = "invoiceplane-admin-password must be declared as a SOPS secret when testbed secrets are enabled.";
      }
      {
        assertion = !cfg.secrets.enable || hasAttr "invoiceplane-encryption-key" config.sops.secrets;
        message = "invoiceplane-encryption-key must be declared as a SOPS secret when testbed secrets are enabled.";
      }
    ];

    users.users.invoiceplane = {
      description = "InvoicePlane service user";
      group = "nginx";
      home = toString invoiceplaneCfg.stateDir;
      isSystemUser = true;
    };

    services.mysql = {
      dataDir = "${cfg.appdataRoot}/mariadb";
      enable = true;
      ensureDatabases = [ invoiceplaneCfg.databaseName ];
      ensureUsers = [
        {
          ensurePermissions = {
            "${invoiceplaneCfg.databaseName}.*" = "ALL PRIVILEGES";
          };
          name = invoiceplaneCfg.databaseUser;
        }
      ];
      package = pkgs.mariadb;
    };

    systemd.services.invoiceplane-mysql-password = {
      description = "Set InvoicePlane MariaDB password from runtime secret";
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
      path = [
        config.services.mysql.package
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        password_hex="$(od -An -tx1 -v '${dbPasswordFile}' | tr -d ' \n')"
        mysql --protocol=socket <<SQL
        SET @invoiceplane_password = CONVERT(UNHEX('$password_hex') USING utf8mb4);
        SET @invoiceplane_sql = CONCAT(
          "ALTER USER '${invoiceplaneCfg.databaseUser}'@'localhost' IDENTIFIED BY ",
          QUOTE(@invoiceplane_password)
        );
        PREPARE invoiceplane_stmt FROM @invoiceplane_sql;
        EXECUTE invoiceplane_stmt;
        DEALLOCATE PREPARE invoiceplane_stmt;
        FLUSH PRIVILEGES;
        SQL
      '';
    };

    systemd.services.invoiceplane-prepare = {
      description = "Prepare InvoicePlane runtime tree";
      after = [ "invoiceplane-mysql-password.service" ];
      requires = [ "invoiceplane-mysql-password.service" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnused
        pkgs.rsync
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        install -d -m 0750 -o invoiceplane -g nginx '${invoiceplaneCfg.stateDir}'
        install -d -m 0750 -o invoiceplane -g nginx '${runtimeRoot}'

        rsync -a --delete \
          --exclude ipconfig.php \
          --exclude uploads \
          --exclude application/logs \
          --exclude storage \
          '${invoiceplanePackage}/share/invoiceplane/' '${runtimeRoot}/'

        if [ ! -f '${runtimeRoot}/ipconfig.php' ]; then
          cp '${invoiceplanePackage}/share/invoiceplane/ipconfig.php.example' '${runtimeRoot}/ipconfig.php'
          sed -i \
            -e "s#^DISABLE_SETUP=.*#DISABLE_SETUP=false#" \
            -e "s#^SETUP_COMPLETED=.*#SETUP_COMPLETED=false#" \
            '${runtimeRoot}/ipconfig.php'
        fi

        db_password="$(cat '${dbPasswordFile}')"
        db_password_escaped="$(printf '%s' "$db_password" | sed 's/[\\&|]/\\&/g')"
        encryption_key="$(cat '${invoiceplaneCfg.encryptionKeyFile}')"
        encryption_key_escaped="$(printf '%s' "$encryption_key" | sed 's/[\\&|]/\\&/g')"

        sed -i \
          -e "s#^IP_URL=.*#IP_URL=${invoiceplaneCfg.externalUrl}/#" \
          -e "s#^DB_HOSTNAME=.*#DB_HOSTNAME='localhost'#" \
          -e "s#^DB_USERNAME=.*#DB_USERNAME='${invoiceplaneCfg.databaseUser}'#" \
          -e "s|^DB_PASSWORD=.*|DB_PASSWORD='$db_password_escaped'|" \
          -e "s#^DB_DATABASE=.*#DB_DATABASE='${invoiceplaneCfg.databaseName}'#" \
          -e "s#^DB_PORT=.*#DB_PORT=3306#" \
          -e "s#^REMOVE_INDEXPHP=.*#REMOVE_INDEXPHP=true#" \
          -e "s|^ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$encryption_key_escaped|" \
          '${runtimeRoot}/ipconfig.php'

        install -d -m 0750 -o invoiceplane -g nginx \
          '${runtimeRoot}/application/logs' \
          '${runtimeRoot}/storage/logs' \
          '${runtimeRoot}/storage/framework/cache/data' \
          '${runtimeRoot}/storage/framework/sessions' \
          '${runtimeRoot}/uploads/archive' \
          '${runtimeRoot}/uploads/customer_files' \
          '${runtimeRoot}/uploads/import' \
          '${runtimeRoot}/uploads/temp/mpdf'

        chown -R invoiceplane:nginx \
          '${runtimeRoot}/application/logs' \
          '${runtimeRoot}/storage' \
          '${runtimeRoot}/uploads' \
          '${runtimeRoot}/ipconfig.php'

        find '${runtimeRoot}/application/logs' '${runtimeRoot}/storage' '${runtimeRoot}/uploads' -type d -exec chmod 0750 {} +
        find '${runtimeRoot}/application/logs' '${runtimeRoot}/storage' '${runtimeRoot}/uploads' -type f -exec chmod 0640 {} +
        chmod 0640 '${runtimeRoot}/ipconfig.php'
      '';
    };

    services.phpfpm.pools.invoiceplane = {
      inherit phpPackage;
      group = "nginx";
      phpOptions = ''
        date.timezone = ${config.time.timeZone}
        upload_max_filesize = 64M
        post_max_size = 64M
      '';
      settings = {
        "catch_workers_output" = true;
        "listen.group" = "nginx";
        "listen.mode" = "0660";
        "listen.owner" = "nginx";
        "pm" = "dynamic";
        "pm.max_children" = 10;
        "pm.max_spare_servers" = 3;
        "pm.min_spare_servers" = 1;
        "pm.start_servers" = 2;
      };
      user = "invoiceplane";
    };

    systemd.services.phpfpm-invoiceplane = {
      after = [
        "invoiceplane-prepare.service"
        "mysql.service"
      ];
      requires = [
        "invoiceplane-prepare.service"
        "mysql.service"
      ];
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      virtualHosts.${serviceHosts.invoiceplane} = {
        listen = [
          {
            addr = invoiceplaneCfg.bindAddress;
            port = cfg.ports.invoiceplane;
          }
        ];
        root = runtimeRoot;
        serverAliases = serviceHostAliases.invoiceplane;
        extraConfig = ''
          index index.php;
        '';
        locations = {
          "/" = {
            tryFiles = "$uri $uri/ /index.php$is_args$args";
          };
          "~ [^/]\\.php(/|$)" = {
            extraConfig = ''
              include ${pkgs.nginx}/conf/fastcgi_params;
              fastcgi_split_path_info ^(.+?\.php)(/.*)$;
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              fastcgi_param PATH_INFO $fastcgi_path_info;
              fastcgi_param HTTP_PROXY "";
              fastcgi_param HTTPS on;
              fastcgi_param HTTP_X_FORWARDED_PROTO https;
              fastcgi_pass unix:${config.services.phpfpm.pools.invoiceplane.socket};
            '';
          };
          "~ /(application|resources|storage|vendor)/" = {
            extraConfig = "deny all;";
          };
        };
      };
    };

    systemd.services.invoiceplane-bootstrap = {
      description = "Bootstrap InvoicePlane database and admin account";
      after = [
        "invoiceplane-prepare.service"
        "mysql.service"
        "nginx.service"
        "phpfpm-invoiceplane.service"
      ];
      requires = [
        "invoiceplane-prepare.service"
        "mysql.service"
        "nginx.service"
        "phpfpm-invoiceplane.service"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [
        config.services.mysql.package
        pkgs.coreutils
        pkgs.curl
        pkgs.gnugrep
        pkgs.gnused
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        versions_table="$(mysql --batch --skip-column-names --protocol=socket information_schema -e "SELECT COUNT(*) FROM tables WHERE table_schema='${invoiceplaneCfg.databaseName}' AND table_name='ip_versions';")"
        users_table="$(mysql --batch --skip-column-names --protocol=socket information_schema -e "SELECT COUNT(*) FROM tables WHERE table_schema='${invoiceplaneCfg.databaseName}' AND table_name='ip_users';")"
        versions_count=0
        users_count=0

        if [ "$versions_table" = 1 ]; then
          versions_count="$(mysql --batch --skip-column-names --protocol=socket '${invoiceplaneCfg.databaseName}' -e 'SELECT COUNT(*) FROM ip_versions;')"
        fi
        if [ "$users_table" = 1 ]; then
          users_count="$(mysql --batch --skip-column-names --protocol=socket '${invoiceplaneCfg.databaseName}' -e 'SELECT COUNT(*) FROM ip_users;')"
        fi

        if [ "$versions_table" = 1 ] && [ "$users_table" = 1 ] && [ "$versions_count" -gt 0 ] && [ "$users_count" -gt 0 ]; then
          sed -i \
            -e "s#^IP_URL=.*#IP_URL=${invoiceplaneCfg.externalUrl}/#" \
            -e "s#^DISABLE_SETUP=.*#DISABLE_SETUP=true#" \
            -e "s#^SETUP_COMPLETED=.*#SETUP_COMPLETED=true#" \
            '${runtimeRoot}/ipconfig.php'
          exit 0
        fi

        if [ "$versions_table" != 0 ] || [ "$users_table" != 0 ] || [ "$versions_count" != 0 ] || [ "$users_count" != 0 ]; then
          echo "InvoicePlane database is partially initialized; refusing to guess bootstrap state" >&2
          exit 1
        fi

        admin_email="$(cat '${invoiceplaneCfg.adminEmailFile}')"
        admin_password="$(cat '${invoiceplaneCfg.adminPasswordFile}')"
        if [ -z "$admin_email" ] || [ -z "$admin_password" ]; then
          echo "InvoicePlane admin bootstrap secrets must be non-empty" >&2
          exit 1
        fi

        jar="$(mktemp)"
        body="$(mktemp)"
        admin_email_form="$(mktemp)"
        admin_password_form="$(mktemp)"
        admin_password_verify_form="$(mktemp)"
        db_password_form="$(mktemp)"
        cleanup() {
          rm -f "$jar" "$body" "$admin_email_form" "$admin_password_form" "$admin_password_verify_form" "$db_password_form"
        }
        trap cleanup EXIT

        printf '%s' "$admin_email" > "$admin_email_form"
        printf '%s' "$admin_password" > "$admin_password_form"
        printf '%s' "$admin_password" > "$admin_password_verify_form"
        cat '${dbPasswordFile}' > "$db_password_form"

        base="http://${invoiceplaneCfg.bindAddress}:${toString cfg.ports.invoiceplane}"
        host_header='Host: ${serviceHosts.invoiceplane}'

        get() {
          curl -fsS --max-time 20 -b "$jar" -c "$jar" -H "$host_header" "$base$1" -o "$body"
        }

        token() {
          sed -n 's/.*name="_ip_csrf" value="\([^"]*\)".*/\1/p' "$body" | tail -n 1
        }

        post() {
          csrf="$(token)"
          if [ -z "$csrf" ]; then
            echo "InvoicePlane setup page did not contain a CSRF token" >&2
            exit 1
          fi
          path="$1"
          shift
          curl -fsS --max-time 20 -b "$jar" -c "$jar" -H "$host_header" \
            --data-urlencode "_ip_csrf=$csrf" "$@" "$base$path" -o "$body"
        }

        get /setup/language
        post /setup/language --data-urlencode ip_lang=english --data-urlencode btn_continue=1
        get /setup/prerequisites
        post /setup/prerequisites --data-urlencode btn_continue=1
        get /setup/configure_database
        post /setup/configure_database \
          --data-urlencode db_hostname=localhost \
          --data-urlencode db_username='${invoiceplaneCfg.databaseUser}' \
          --data-urlencode "db_password@$db_password_form" \
          --data-urlencode db_database='${invoiceplaneCfg.databaseName}' \
          --data-urlencode db_port=3306
        get /setup/configure_database
        post /setup/configure_database --data-urlencode btn_continue=1
        get /setup/install_tables
        post /setup/install_tables --data-urlencode btn_continue=1
        get /setup/upgrade_tables
        post /setup/upgrade_tables --data-urlencode btn_continue=1
        get /setup/create_user
        post /setup/create_user \
          --data-urlencode user_type=1 \
          --data-urlencode "user_email@$admin_email_form" \
          --data-urlencode user_name='Fleet Admin' \
          --data-urlencode "user_password@$admin_password_form" \
          --data-urlencode "user_passwordv@$admin_password_verify_form" \
          --data-urlencode user_language=english
        get /setup/calculation_info
        post /setup/calculation_info --data-urlencode btn_agree=1
        get /setup/complete

        versions_count="$(mysql --batch --skip-column-names --protocol=socket '${invoiceplaneCfg.databaseName}' -e 'SELECT COUNT(*) FROM ip_versions;')"
        users_count="$(mysql --batch --skip-column-names --protocol=socket '${invoiceplaneCfg.databaseName}' -e 'SELECT COUNT(*) FROM ip_users;')"
        if [ "$versions_count" -eq 0 ] || [ "$users_count" -eq 0 ]; then
          echo "InvoicePlane bootstrap did not create expected schema and admin user" >&2
          exit 1
        fi

        sed -i \
          -e "s#^IP_URL=.*#IP_URL=${invoiceplaneCfg.externalUrl}/#" \
          -e "s#^DISABLE_SETUP=.*#DISABLE_SETUP=true#" \
          -e "s#^SETUP_COMPLETED=.*#SETUP_COMPLETED=true#" \
          '${runtimeRoot}/ipconfig.php'
      '';
    };

    systemd.services.nginx = {
      after = [ "invoiceplane-prepare.service" ];
      wants = [ "invoiceplane-prepare.service" ];
    };
  };
}
