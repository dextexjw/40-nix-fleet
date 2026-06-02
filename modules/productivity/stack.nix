{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.productivity.stack;
  appdata = cfg.appdataRoot;
  serviceHostPrefixes = {
    docs = "docs";
    firefly = "firefly";
    forgejo = "forgejo";
    freshrss = "freshrss";
    garage = "garage";
    garageWeb = "garage-web";
    gitea = "gitea";
    nextcloud = "nextcloud";
    ntfy = "ntfy";
    paperless = "paperless";
    privatebin = "privatebin";
    rustfs = "rustfs";
    rustfsConsole = "rustfs-console";
    searxng = "searxng";
    shlink = "s";
    shlinkWeb = "shlink";
    stirlingPdf = "stirling-pdf";
    syncthing = "syncthing";
    vaultwarden = "vaultwarden";
  };
  serviceHostKeys = [
    "gitea"
    "forgejo"
    "docs"
    "paperless"
    "freshrss"
    "searxng"
    "privatebin"
    "vaultwarden"
    "syncthing"
    "stirlingPdf"
    "firefly"
    "nextcloud"
    "garage"
    "garageWeb"
    "rustfs"
    "rustfsConsole"
    "shlink"
    "shlinkWeb"
    "ntfy"
  ];
  mkServiceHostNames =
    domains:
    mapAttrs (
      _name: prefix:
      map (serviceDomain: "${prefix}.${serviceDomain}") domains
    ) serviceHostPrefixes;
  mkServiceHosts = domains: mapAttrs (_name: names: head names) (mkServiceHostNames domains);
  mkServiceHostAliases = domains: mapAttrs (_name: names: tail names) (mkServiceHostNames domains);
  serviceHosts = cfg.serviceHosts;
  serviceHostAliases = mkServiceHostAliases cfg.serviceDomains;
  serviceRouteLines = concatStringsSep "\n" (
    concatMap (
      serviceKey:
      map (hostName: "        http://${hostName}") ([ serviceHosts.${serviceKey} ] ++ serviceHostAliases.${serviceKey})
    ) serviceHostKeys
  );
  rustfsGid = 10001;
  rustfsUid = 10001;

  secretPath =
    name:
    if cfg.secrets.enable then
      config.sops.secrets.${name}.path
    else
      "/run/secrets/${name}";

  smbCredentialsFile = secretPath "smb-credentials";
  resticPasswordFile = secretPath "restic-password";

  garageEnvironmentFile = pkgs.writeText "garage.env" ''
    GARAGE_LOG_TO_JOURNALD=true
  '';

  mkdocsEnv = pkgs.python3.withPackages (
    pythonPackages: with pythonPackages; [
      mkdocs
      mkdocs-material
    ]
  );

  mkdocsRoot = "${appdata}/mkdocs";
  mkdocsConfig = pkgs.writeText "mkdocs.yml" ''
    site_name: Homelab Knowledge Base
    site_url: http://${serviceHosts.docs}/
    theme:
      name: material
    nav:
      - Home: index.md
  '';
  mkdocsIndex = pkgs.writeText "index.md" ''
    # Homelab Knowledge Base

    This internal documentation site is backed by Material for MkDocs.
  '';

  systemdMountOptions = filter (
    option:
    option != "_netdev"
    && option != "noauto"
    && option != "nofail"
    && !(hasPrefix "x-systemd." option)
  ) cfg.smb.mountOptions;

  appsdataDirs = [
    appdata
  ];

  statefulServices = [
    "gitea.service"
    "forgejo.service"
    "nginx.service"
    "paperless-scheduler.service"
    "paperless-task-queue.service"
    "paperless-consumer.service"
    "paperless-web.service"
    "freshrss-config.service"
    "freshrss-updater.service"
    "phpfpm-freshrss.service"
    "searx.service"
    "vaultwarden.service"
    "phpfpm-privatebin.service"
    "syncthing.service"
    "stirling-pdf.service"
    "phpfpm-firefly-iii.service"
    "firefly-iii-cron.timer"
    "phpfpm-nextcloud.service"
    "garage.service"
    "podman-shlink.service"
    "podman-shlink-web.service"
    "podman-rustfs.service"
    "ntfy-sh.service"
  ];
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.productivity.stack = {
    enable = mkEnableOption "productivity-vm application stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use sops-nix secrets from secrets/secrets.yaml.";
    };

    serviceDomain = mkOption {
      type = types.str;
      default = "h";
      description = "Legacy single internal service domain used for route hostnames.";
    };

    serviceDomains = mkOption {
      type = types.nonEmptyListOf types.str;
      default = [ cfg.serviceDomain ];
      description = "Internal service domains used for route hostnames, in canonical-first order.";
    };

    serviceHosts = mkOption {
      type = types.attrsOf types.str;
      default = mkServiceHosts cfg.serviceDomains;
      description = "Canonical internal hostnames for productivity services.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        forgejo = 3002;
        garageAdmin = 3903;
        garageRpc = 3901;
        garageS3 = 3900;
        garageWeb = 3902;
        gitea = 3000;
        ntfy = 2586;
        rustfsApi = 9000;
        rustfsConsole = 9001;
        searxng = 8087;
        shlink = 8088;
        shlinkWeb = 8089;
        stirlingPdf = 8086;
        syncthing = 8384;
        vaultwarden = 8222;
      };
      description = "LAN-facing web or API ports for non-nginx productivity services.";
    };

    smb = {
      backupDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/backups";
        description = "SMB device for the backup share.";
      };

      backupMount = mkOption {
        type = types.path;
        default = "/mnt/backups";
        description = "Backup SMB mount point.";
      };

      mountOptions = mkOption {
        type = types.listOf types.str;
        default = [
          "vers=3.0"
          "noauto"
          "nofail"
          "x-systemd.automount"
          "x-systemd.after=network-online.target"
          "x-systemd.idle-timeout=60"
          "x-systemd.mount-timeout=30s"
          "x-systemd.requires=network-online.target"
          "_netdev"
        ];
        description = "Systemd-aware CIFS mount options.";
      };
    };

    backup = {
      repository = mkOption {
        type = types.path;
        default = "/mnt/backups/restic/appdata/productivity-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by productivity-appdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/productivity-appdata-restore-check";
        description = "Temporary target used by productivity-appdata-restore-check.service.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    # --------------------------------------------------------------------------
    # USERS, GROUPS, DIRECTORIES, AND MOUNTS
    # --------------------------------------------------------------------------

    boot.supportedFilesystems.cifs = true;

    users.groups.productivity = { };
    users.groups.garage = { };
    users.groups.stirling-pdf = { };

    users.users.garage = {
      isSystemUser = true;
      group = "garage";
      home = "${appdata}/garage";
    };

    users.users.stirling-pdf = {
      isSystemUser = true;
      group = "stirling-pdf";
      home = "${appdata}/stirling-pdf";
    };

    systemd.tmpfiles.rules =
      (map (path: "d '${path}' 0755 root root - -") appsdataDirs)
      ++ [
        "d '${appdata}/firefly-iii' 0750 firefly-iii nginx - -"
        "z '${appdata}/firefly-iii' 0750 firefly-iii nginx - -"
        "d '${appdata}/forgejo' 0750 forgejo forgejo - -"
        "z '${appdata}/forgejo' 0750 forgejo forgejo - -"
        "d '${appdata}/freshrss' 0750 freshrss freshrss - -"
        "z '${appdata}/freshrss' 0750 freshrss freshrss - -"
        "d '${appdata}/garage' 0750 garage garage - -"
        "z '${appdata}/garage' 0750 garage garage - -"
        "d '${appdata}/garage/data' 0750 garage garage - -"
        "z '${appdata}/garage/data' 0750 garage garage - -"
        "d '${appdata}/garage/meta' 0750 garage garage - -"
        "z '${appdata}/garage/meta' 0750 garage garage - -"
        "d '${appdata}/garage/snapshots' 0750 garage garage - -"
        "z '${appdata}/garage/snapshots' 0750 garage garage - -"
        "d '${appdata}/gitea' 0750 gitea gitea - -"
        "z '${appdata}/gitea' 0750 gitea gitea - -"
        "d '${appdata}/mkdocs' 0775 root productivity - -"
        "z '${appdata}/mkdocs' 0775 root productivity - -"
        "d '${appdata}/mkdocs/docs' 0775 root productivity - -"
        "z '${appdata}/mkdocs/docs' 0775 root productivity - -"
        "d '${appdata}/mkdocs/site' 0775 root productivity - -"
        "z '${appdata}/mkdocs/site' 0775 root productivity - -"
        "d '${appdata}/nextcloud' 0750 nextcloud nextcloud - -"
        "z '${appdata}/nextcloud' 0750 nextcloud nextcloud - -"
        "d '${appdata}/ntfy' 0750 ntfy-sh ntfy-sh - -"
        "z '${appdata}/ntfy' 0750 ntfy-sh ntfy-sh - -"
        "d '${appdata}/ntfy/attachments' 0750 ntfy-sh ntfy-sh - -"
        "z '${appdata}/ntfy/attachments' 0750 ntfy-sh ntfy-sh - -"
        "d '${appdata}/paperless' 0750 paperless paperless - -"
        "z '${appdata}/paperless' 0750 paperless paperless - -"
        "d '${appdata}/paperless/consume' 0750 paperless paperless - -"
        "z '${appdata}/paperless/consume' 0750 paperless paperless - -"
        "d '${appdata}/paperless/media' 0750 paperless paperless - -"
        "z '${appdata}/paperless/media' 0750 paperless paperless - -"
        "d '${appdata}/postgresql' 0750 postgres postgres - -"
        "z '${appdata}/postgresql' 0750 postgres postgres - -"
        "d '${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
        "z '${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}' 0750 postgres postgres - -"
        "d '${appdata}/postgresql-dumps' 0700 postgres postgres - -"
        "z '${appdata}/postgresql-dumps' 0700 postgres postgres - -"
        "d '${appdata}/privatebin' 0750 privatebin nginx - -"
        "z '${appdata}/privatebin' 0750 privatebin nginx - -"
        "d '${appdata}/rustfs' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
        "z '${appdata}/rustfs' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
        "d '${appdata}/rustfs/data' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
        "z '${appdata}/rustfs/data' 0750 ${toString rustfsUid} ${toString rustfsGid} - -"
        "d '${appdata}/searxng' 0750 searx searx - -"
        "z '${appdata}/searxng' 0750 searx searx - -"
        "d '${appdata}/shlink' 0750 root productivity - -"
        "z '${appdata}/shlink' 0750 root productivity - -"
        "d '${appdata}/stirling-pdf' 0750 stirling-pdf stirling-pdf - -"
        "z '${appdata}/stirling-pdf' 0750 stirling-pdf stirling-pdf - -"
        "d '${appdata}/syncthing' 0750 syncthing syncthing - -"
        "z '${appdata}/syncthing' 0750 syncthing syncthing - -"
        "d '${appdata}/vaultwarden' 0750 vaultwarden vaultwarden - -"
        "z '${appdata}/vaultwarden' 0750 vaultwarden vaultwarden - -"
      ];

    systemd.automounts = [
      {
        where = toString cfg.smb.backupMount;
        wantedBy = [ "multi-user.target" ];
        automountConfig.TimeoutIdleSec = "60s";
      }
    ];

    systemd.mounts = [
      {
        description = "Backup SMB share";
        what = cfg.smb.backupDevice;
        where = toString cfg.smb.backupMount;
        type = "cifs";
        options = concatStringsSep "," (
          systemdMountOptions
          ++ [
            "credentials=${smbCredentialsFile}"
            "dir_mode=0750"
            "file_mode=0640"
            "forcegid"
            "gid=productivity"
          ]
        );
        after = [ "network-online.target" ];
        before = [ "umount.target" ];
        conflicts = [ "umount.target" ];
        requires = [ "network-online.target" ];
        unitConfig.DefaultDependencies = false;
        mountConfig.TimeoutSec = "30s";
      }
    ];

    # --------------------------------------------------------------------------
    # SHARED DATABASE
    # --------------------------------------------------------------------------

    services.postgresql = {
      enable = true;
      dataDir = "${appdata}/postgresql/${config.services.postgresql.package.psqlSchema}";
      ensureDatabases = [ "shlink" ];
      ensureUsers = [
        {
          name = "shlink";
          ensureDBOwnership = true;
        }
      ];
    };

    # --------------------------------------------------------------------------
    # PRODUCTIVITY SERVICES
    # --------------------------------------------------------------------------

    services.gitea = {
      enable = true;
      appName = "Fleet Git";
      lfs.enable = true;
      stateDir = "${appdata}/gitea";
      database = {
        type = "postgres";
        createDatabase = true;
      };
      dump = {
        enable = true;
        backupDir = "${appdata}/gitea/dump";
        type = "tar.zst";
      };
      settings = {
        repository.DEFAULT_BRANCH = "main";
        server = {
          DOMAIN = serviceHosts.gitea;
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.ports.gitea;
          ROOT_URL = "http://${serviceHosts.gitea}/";
          SSH_PORT = 22;
        };
        service = {
          DISABLE_REGISTRATION = true;
          REQUIRE_SIGNIN_VIEW = false;
        };
      };
    };

    services.forgejo = {
      enable = true;
      package = pkgs.forgejo;
      lfs.enable = true;
      stateDir = "${appdata}/forgejo";
      database = {
        type = "postgres";
        createDatabase = true;
      };
      dump = {
        enable = true;
        backupDir = "${appdata}/forgejo/dump";
        type = "tar.zst";
      };
      settings = {
        DEFAULT.APP_NAME = "Fleet Forgejo";
        repository.DEFAULT_BRANCH = "main";
        server = {
          DOMAIN = serviceHosts.forgejo;
          HTTP_ADDR = "0.0.0.0";
          HTTP_PORT = cfg.ports.forgejo;
          ROOT_URL = "http://${serviceHosts.forgejo}/";
          SSH_PORT = 22;
        };
        service = {
          DISABLE_REGISTRATION = true;
          REQUIRE_SIGNIN_VIEW = false;
        };
      };
    };

    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      configureNginx = true;
      consumptionDir = "${appdata}/paperless/consume";
      dataDir = "${appdata}/paperless";
      database.createLocally = true;
      domain = serviceHosts.paperless;
      mediaDir = "${appdata}/paperless/media";
      passwordFile = secretPath "paperless-admin-password";
      settings = {
        PAPERLESS_ADMIN_USER = "smoke";
        PAPERLESS_ALLOWED_HOSTS = concatStringsSep "," ([ serviceHosts.paperless ] ++ serviceHostAliases.paperless);
        PAPERLESS_OCR_LANGUAGE = "eng";
        PAPERLESS_URL = mkForce "http://${serviceHosts.paperless}";
      };
    };

    services.freshrss = {
      enable = true;
      api.enable = true;
      authType = "form";
      baseUrl = "http://${serviceHosts.freshrss}";
      dataDir = "${appdata}/freshrss";
      defaultUser = "smoke";
      passwordFile = secretPath "freshrss-admin-password";
      virtualHost = serviceHosts.freshrss;
      webserver = "nginx";
    };

    services.searx = {
      enable = true;
      domain = serviceHosts.searxng;
      environmentFile = secretPath "searxng-environment";
      openFirewall = true;
      redisCreateLocally = true;
      settings = {
        search.safe_search = 1;
        server = {
          base_url = "http://${serviceHosts.searxng}/";
          bind_address = "0.0.0.0";
          limiter = false;
          port = cfg.ports.searxng;
          secret_key = "$SEARXNG_SECRET_KEY";
        };
        ui.static_use_hash = true;
      };
    };

    services.privatebin = {
      enable = true;
      dataDir = "${appdata}/privatebin";
      enableNginx = true;
      virtualHost = serviceHosts.privatebin;
      settings = {
        main = {
          name = "Fleet PrivateBin";
          discussion = false;
          fileupload = false;
          qrcode = true;
          sizelimit = 10485760;
        };
        expire.default = "1week";
      };
    };

    services.syncthing = {
      enable = true;
      configDir = "${appdata}/syncthing/.config/syncthing";
      dataDir = "${appdata}/syncthing";
      guiAddress = "0.0.0.0:${toString cfg.ports.syncthing}";
      guiPasswordFile = secretPath "syncthing-gui-password";
      openDefaultPorts = true;
      overrideDevices = false;
      overrideFolders = false;
      settings = {
        gui = {
          user = "smoke";
          theme = "black";
        };
        options.urAccepted = -1;
      };
    };

    services.stirling-pdf = {
      enable = true;
      environment = {
        SERVER_ADDRESS = "0.0.0.0";
        SERVER_PORT = cfg.ports.stirlingPdf;
        SYSTEM_DEFAULTLOCALE = "en-US";
        UI_APPNAME = "Fleet PDF";
      };
    };

    services.firefly-iii = {
      enable = true;
      dataDir = "${appdata}/firefly-iii";
      enableNginx = true;
      virtualHost = serviceHosts.firefly;
      settings = {
        APP_ENV = "production";
        APP_KEY_FILE = secretPath "firefly-app-key";
        APP_URL = "http://${serviceHosts.firefly}";
        DB_CONNECTION = "sqlite";
      };
    };

    services.nextcloud = {
      enable = true;
      configureRedis = true;
      database.createLocally = true;
      datadir = "${appdata}/nextcloud";
      home = "${appdata}/nextcloud";
      hostName = serviceHosts.nextcloud;
      https = false;
      package = pkgs.nextcloud32;
      config = {
        adminpassFile = secretPath "nextcloud-admin-password";
        adminuser = "smoke";
        dbtype = "pgsql";
      };
      settings = {
        overwrite.cli.url = "http://${serviceHosts.nextcloud}";
        overwriteprotocol = "http";
        trusted_domains = serviceHostAliases.nextcloud;
      };
    };

    services.vaultwarden = {
      enable = true;
      configurePostgres = true;
      dbBackend = "postgresql";
      environmentFile = [ (secretPath "vaultwarden-environment") ];
      config = {
        DATA_FOLDER = "${appdata}/vaultwarden";
        DOMAIN = "http://${serviceHosts.vaultwarden}";
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = cfg.ports.vaultwarden;
        SIGNUPS_ALLOWED = false;
        WEB_VAULT_ENABLED = true;
      };
    };

    services.garage = {
      enable = true;
      environmentFile = garageEnvironmentFile;
      package = pkgs.garage;
      settings = {
        replication_factor = 1;
        consistency_mode = "consistent";
        metadata_dir = "${appdata}/garage/meta";
        data_dir = "${appdata}/garage/data";
        metadata_snapshots_dir = "${appdata}/garage/snapshots";
        db_engine = "lmdb";
        rpc_bind_addr = "0.0.0.0:${toString cfg.ports.garageRpc}";
        rpc_public_addr = "127.0.0.1:${toString cfg.ports.garageRpc}";
        rpc_secret_file = secretPath "garage-rpc-secret";
        s3_api = {
          api_bind_addr = "0.0.0.0:${toString cfg.ports.garageS3}";
          root_domain = ".${serviceHosts.garage}";
          s3_region = "garage";
        };
        s3_web = {
          bind_addr = "0.0.0.0:${toString cfg.ports.garageWeb}";
          root_domain = ".${serviceHosts.garageWeb}";
        };
        admin = {
          admin_token_file = secretPath "garage-admin-token";
          api_bind_addr = "127.0.0.1:${toString cfg.ports.garageAdmin}";
          metrics_require_token = true;
          metrics_token_file = secretPath "garage-metrics-token";
        };
      };
    };

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://${serviceHosts.ntfy}";
        listen-http = "0.0.0.0:${toString cfg.ports.ntfy}";
        auth-file = "${appdata}/ntfy/user.db";
        attachment-cache-dir = "${appdata}/ntfy/attachments";
        cache-file = "${appdata}/ntfy/cache.db";
      };
    };

    virtualisation.oci-containers.backend = "podman";
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

    virtualisation.oci-containers.containers.rustfs = {
      image = "docker.io/rustfs/rustfs@sha256:029bab58b7cfca8b3b3483d49ac073075f555d7cc50abdd706d7df74bf6ec432";
      pull = "missing";

      environment = {
        RUSTFS_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsApi}";
        RUSTFS_CONSOLE_ADDRESS = "0.0.0.0:${toString cfg.ports.rustfsConsole}";
        RUSTFS_CONSOLE_ENABLE = "true";
        RUSTFS_SERVER_DOMAINS = serviceHosts.rustfs;
        RUSTFS_VOLUMES = "/data";
      };
      environmentFiles = [ (secretPath "rustfs-environment") ];

      extraOptions = [
        "--cap-drop=ALL"
        "--health-cmd=sh -c 'curl -f http://127.0.0.1:${toString cfg.ports.rustfsApi}/health && curl -f http://127.0.0.1:${toString cfg.ports.rustfsConsole}/rustfs/console/health'"
        "--health-interval=30s"
        "--health-retries=3"
        "--health-start-period=40s"
        "--health-timeout=10s"
        "--security-opt=no-new-privileges"
      ];

      podman.sdnotify = "healthy";

      ports = [
        "0.0.0.0:${toString cfg.ports.rustfsApi}:${toString cfg.ports.rustfsApi}/tcp"
        "0.0.0.0:${toString cfg.ports.rustfsConsole}:${toString cfg.ports.rustfsConsole}/tcp"
      ];

      volumes = [
        "${appdata}/rustfs/data:/data"
      ];
    };

    # --------------------------------------------------------------------------
    # MATERIAL FOR MKDOCS
    # --------------------------------------------------------------------------

    systemd.services.mkdocs-material-init = {
      description = "Initialize Material for MkDocs source tree";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        pkgs.coreutils
      ];
      script = ''
        set -euo pipefail

        install -d -m 0775 -o root -g productivity '${mkdocsRoot}/docs'
        install -d -m 0775 -o root -g productivity '${mkdocsRoot}/site'

        if [ ! -f '${mkdocsRoot}/mkdocs.yml' ]; then
          install -m 0664 -o root -g productivity ${mkdocsConfig} '${mkdocsRoot}/mkdocs.yml'
        fi

        if [ ! -f '${mkdocsRoot}/docs/index.md' ]; then
          install -m 0664 -o root -g productivity ${mkdocsIndex} '${mkdocsRoot}/docs/index.md'
        fi
      '';
    };

    systemd.services.mkdocs-material-build = {
      description = "Build Material for MkDocs static site";
      wantedBy = [ "multi-user.target" ];
      requires = [ "mkdocs-material-init.service" ];
      after = [ "mkdocs-material-init.service" ];
      path = [
        mkdocsEnv
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "productivity";
      };
      script = ''
        set -euo pipefail

        mkdocs build \
          --clean \
          --config-file '${mkdocsRoot}/mkdocs.yml' \
          --site-dir '${mkdocsRoot}/site'

        chgrp -R productivity '${mkdocsRoot}/site'
        chmod -R g=u '${mkdocsRoot}/site'
      '';
    };

    systemd.paths.mkdocs-material-build = {
      description = "Rebuild Material for MkDocs when source changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = [
          "${mkdocsRoot}/docs"
          "${mkdocsRoot}/mkdocs.yml"
        ];
        Unit = "mkdocs-material-build.service";
      };
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      virtualHosts.${serviceHosts.docs} = {
        root = "${mkdocsRoot}/site";
        serverAliases = serviceHostAliases.docs;
        locations."/".tryFiles = "$uri $uri/ /index.html";
      };
    };

    services.nginx.virtualHosts.${serviceHosts.paperless} = {
      forceSSL = mkForce false;
      serverAliases = serviceHostAliases.paperless;
    };
    services.nginx.virtualHosts.${serviceHosts.freshrss}.serverAliases = serviceHostAliases.freshrss;
    services.nginx.virtualHosts.${serviceHosts.privatebin}.serverAliases = serviceHostAliases.privatebin;
    services.nginx.virtualHosts.${serviceHosts.firefly}.serverAliases = serviceHostAliases.firefly;
    services.nginx.virtualHosts.${serviceHosts.nextcloud}.serverAliases = serviceHostAliases.nextcloud;

    # --------------------------------------------------------------------------
    # SERVICE OVERRIDES FOR /srv/appdata AND LAN ROUTING
    # --------------------------------------------------------------------------

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

    systemd.services.garage.serviceConfig = {
      DynamicUser = mkForce false;
      User = "garage";
      Group = "garage";
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

    systemd.services.podman-rustfs = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig.RestartSec = "30s";
    };

    systemd.services.ntfy-sh.serviceConfig = {
      DynamicUser = mkForce false;
      ReadWritePaths = [ "${appdata}/ntfy" ];
      StateDirectory = mkForce "";
    };

    systemd.services.stirling-pdf.serviceConfig = {
      DynamicUser = mkForce false;
      Group = "stirling-pdf";
      ReadWritePaths = [ "${appdata}/stirling-pdf" ];
      StateDirectory = mkForce "";
      User = "stirling-pdf";
      WorkingDirectory = mkForce "${appdata}/stirling-pdf";
    };

    systemd.services.stirling-pdf.environment.HOME = mkForce "${appdata}/stirling-pdf";

    systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [ "${appdata}/vaultwarden" ];

    systemd.services.nginx = {
      wants = [ "mkdocs-material-build.service" ];
      after = [ "mkdocs-material-build.service" ];
    };

    # --------------------------------------------------------------------------
    # BACKUPS
    # --------------------------------------------------------------------------

    environment.systemPackages = [
      pkgs.restic
      pkgs.garage
      config.services.paperless.manage
    ];

    systemd.services.productivity-postgresql-dump = {
      description = "Dump productivity-vm PostgreSQL databases before backup";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      path = [
        pkgs.coreutils
        pkgs.gzip
        config.services.postgresql.package
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail

        install -d -m 0700 -o postgres -g postgres '${appdata}/postgresql-dumps'
        tmp="$(mktemp '${appdata}/postgresql-dumps/.dump.XXXXXX.sql.gz')"
        trap 'rm -f "$tmp"' EXIT

        pg_dumpall --clean --if-exists | gzip -9 > "$tmp"
        chmod 0600 "$tmp"
        mv "$tmp" '${appdata}/postgresql-dumps/latest.sql.gz'
        trap - EXIT
      '';
    };

    systemd.services.productivity-appdata-backup = {
      description = "Back up productivity-vm /srv/appsdata with restic";
      after = [
        "network-online.target"
        "productivity-postgresql-dump.service"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [
        "network-online.target"
        "productivity-postgresql-dump.service"
      ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-productivity-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-productivity-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host productivity-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host productivity-vm \
          --one-file-system \
          --exclude-caches \
          --exclude '${appdata}/nextcloud/data/*/files_trashbin' \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host productivity-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata
      '';
    };

    systemd.services.productivity-appdata-restore-check = {
      description = "Verify productivity-vm /srv/appsdata can be restored from restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-productivity-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-productivity-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.backup.restoreCheckTarget}'
        case "$restore_parent" in
          /tmp/*|/var/tmp/*) ;;
          *)
            echo "restore check target must be under /tmp or /var/tmp: $restore_parent"
            exit 1
            ;;
        esac

        rm -rf -- "$restore_parent"
        install -d -m 0700 -o root -g root "$restore_parent"
        restore_root="$(mktemp -d "$restore_parent/run.XXXXXX")"
        cleanup() {
          rm -rf -- "$restore_root"
        }
        trap cleanup EXIT

        restic check --retry-lock 30m
        restic restore latest \
          --host productivity-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.backup.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        first_entry="$(find "$restored_source" -mindepth 1 -maxdepth 1 -print -quit)"
        if [ -z "$first_entry" ]; then
          echo "restore completed but $restored_source is empty"
          exit 1
        fi
      '';
    };

    systemd.timers.productivity-appdata-backup = {
      description = "Daily productivity-vm /srv/appsdata restic backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "productivity-appdata-backup.service";
      };
    };

    # --------------------------------------------------------------------------
    # FIREWALL
    # --------------------------------------------------------------------------

    networking.firewall.allowedTCPPorts = [
      80
      cfg.ports.forgejo
      cfg.ports.garageS3
      cfg.ports.garageWeb
      cfg.ports.gitea
      cfg.ports.ntfy
      cfg.ports.rustfsApi
      cfg.ports.rustfsConsole
      cfg.ports.searxng
      cfg.ports.shlink
      cfg.ports.shlinkWeb
      cfg.ports.stirlingPdf
      cfg.ports.syncthing
      cfg.ports.vaultwarden
    ];

    # --------------------------------------------------------------------------
    # RECOVERY NOTES ON THE HOST
    # --------------------------------------------------------------------------

    environment.etc."fleet/productivity-vm.md".text = ''
      productivity-vm service model
      =============================

      productivity-vm runs Gitea, Forgejo, Material for MkDocs, Paperless-ngx,
      FreshRSS, SearXNG, Vaultwarden, PrivateBin, Syncthing, Stirling PDF,
      Firefly III, Nextcloud, Shlink, Garage, RustFS, ntfy, nginx, PostgreSQL, and
      Restic appdata backups.

      Persistent state root:
        ${appdata}

      Backup repository:
        ${cfg.backup.repository}

      Password file:
        ${resticPasswordFile}

      Internal routes through gateway-vm:
${serviceRouteLines}

      Direct LAN ports:
        Gitea: ${toString cfg.ports.gitea}
        Forgejo: ${toString cfg.ports.forgejo}
        SearXNG: ${toString cfg.ports.searxng}
        Vaultwarden: ${toString cfg.ports.vaultwarden}
        Syncthing GUI: ${toString cfg.ports.syncthing}
        Stirling PDF: ${toString cfg.ports.stirlingPdf}
        Garage S3 API: ${toString cfg.ports.garageS3}
        Garage static web: ${toString cfg.ports.garageWeb}
        RustFS S3 API: ${toString cfg.ports.rustfsApi}
        RustFS console: ${toString cfg.ports.rustfsConsole}
        Shlink API and redirect service: ${toString cfg.ports.shlink}
        Shlink Web Client: ${toString cfg.ports.shlinkWeb}
        ntfy: ${toString cfg.ports.ntfy}
        nginx-backed services: 80

      Backup validation:
        mount ${cfg.smb.backupMount}
        systemctl start productivity-appdata-backup.service
        systemctl start productivity-appdata-restore-check.service
        systemctl status productivity-appdata-backup.service productivity-appdata-restore-check.service

      Restore outline:
        1. Deploy productivity-vm once to create users, secrets, mounts, and units.
        2. Stop productivity-appdata-backup.timer and stateful services.
        3. Mount ${cfg.smb.backupMount}.
        4. Choose a productivity-vm/appsdata snapshot ID.
        5. Restore the snapshot to / with restic --verify.
        6. Run systemd-tmpfiles --create.
        7. Restart PostgreSQL and the stateful services.

      Services stopped during consistency-first manual backup:
        ${concatStringsSep " " statefulServices}

      Garage is standalone S3 in this pass. It does not back Nextcloud primary
      storage. ${serviceHosts.garage} is the authenticated S3 API, so anonymous
      browser requests to / should return AccessDenied. ${serviceHosts.garageWeb}
      is the static
      website endpoint; buckets must still be created and enabled for website
      hosting with the upstream Garage CLI before serving content. Garage
      bucket virtual-host style remains canonical on ${serviceHosts.garage} and
      ${serviceHosts.garageWeb}; the .h names are only routed named endpoints.

      RustFS is a separate S3-compatible object store in this pass. It does not
      share Garage buckets or credentials. ${serviceHosts.rustfs} is the S3 API
      and ${serviceHosts.rustfsConsole} is the RustFS console. RustFS
      virtual-host style remains canonical on ${serviceHosts.rustfs}; the .h
      name is only a routed named endpoint.

      Shlink uses the PostgreSQL database named shlink and the short-link route
      ${serviceHosts.shlink}. The local Shlink Web Client is served at
      ${serviceHosts.shlinkWeb}. Retrieve the API key from the encrypted
      shlink-environment secret and add http://${serviceHosts.shlink} as a server
      in the web client; do not publish the API key in web client static
      configuration.
    '';
  };
}
