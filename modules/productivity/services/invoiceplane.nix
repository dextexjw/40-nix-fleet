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
    appdata
    secretPath
    serviceHostAliases
    serviceHosts
    ;

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

  stateDir = "${appdata}/invoiceplane";
  runtimeRoot = "${stateDir}/www";
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
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.secrets.enable || hasAttr "invoiceplane-db-password" config.sops.secrets;
        message = "invoiceplane-db-password must be declared as a SOPS secret when productivity secrets are enabled.";
      }
    ];

    users.users.invoiceplane = {
      description = "InvoicePlane service user";
      group = "nginx";
      home = stateDir;
      isSystemUser = true;
    };

    services.mysql = {
      dataDir = "${appdata}/mariadb";
      enable = true;
      ensureDatabases = [ "invoiceplane" ];
      ensureUsers = [
        {
          ensurePermissions = {
            "invoiceplane.*" = "ALL PRIVILEGES";
          };
          name = "invoiceplane";
        }
      ];
      package = pkgs.mariadb;
    };

    systemd.services.invoiceplane-mysql-password = {
      description = "Set InvoicePlane MariaDB password from runtime secret";
      after = [
        "mysql.service"
      ];
      requires = [
        "mysql.service"
      ];
      path = [
        pkgs.coreutils
        config.services.mysql.package
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
          "ALTER USER 'invoiceplane'@'localhost' IDENTIFIED BY ",
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

        install -d -m 0750 -o invoiceplane -g nginx '${stateDir}'
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
            -e "s#^IP_URL=.*#IP_URL=http://${serviceHosts.invoiceplane}/#" \
            -e "s#^DB_HOSTNAME=.*#DB_HOSTNAME='localhost'#" \
            -e "s#^DB_USERNAME=.*#DB_USERNAME='invoiceplane'#" \
            -e "s#^DB_DATABASE=.*#DB_DATABASE='invoiceplane'#" \
            -e "s#^DB_PORT=.*#DB_PORT=3306#" \
            -e "s#^REMOVE_INDEXPHP=.*#REMOVE_INDEXPHP=true#" \
            '${runtimeRoot}/ipconfig.php'
        fi

        db_password="$(cat '${dbPasswordFile}')"
        db_password_escaped="$(printf '%s' "$db_password" | sed 's/[\\&|]/\\&/g')"
        sed -i -e "s|^DB_PASSWORD=.*|DB_PASSWORD='$db_password_escaped'|" '${runtimeRoot}/ipconfig.php'

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

    services.nginx.virtualHosts.${serviceHosts.invoiceplane} = {
      extraConfig = ''
        index index.php;
      '';
      root = runtimeRoot;
      serverAliases = serviceHostAliases.invoiceplane;
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
            fastcgi_pass unix:${config.services.phpfpm.pools.invoiceplane.socket};
          '';
        };
        "~ /(application|resources|storage|vendor)/" = {
          extraConfig = "deny all;";
        };
      };
    };

    systemd.services.nginx = {
      after = [ "invoiceplane-prepare.service" ];
      wants = [ "invoiceplane-prepare.service" ];
    };
  };
}
