{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  gatewayCluster = import ../../lib/gateway-cluster.nix { inherit hosts; };
  host = hosts.testbed-vm;
  serviceDomains = (import ../../lib/service-domains.nix).all;
  serviceDomain = builtins.head serviceDomains;
  exposure = import ../../lib/exposure.nix {
    inherit lib;
    root = ../..;
  };
  exposureCatalog = exposure.load {
    inherit hosts serviceDomain serviceDomains;
  };
  routeServices = builtins.filter (service: service ? route) exposureCatalog.serviceEntries;
  routeHosts = lib.unique (lib.concatMap (service: service.route.hosts) routeServices);
  secretsFile = ../../secrets/secrets.yaml;
  secretsEnabled = builtins.pathExists secretsFile;
in
{
  # ============================================================================
  # IMPORTS
  # ============================================================================

  imports = [
    ../common.nix
    ./hardware-configuration.nix
    ../../modules/testbed
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  fleet.host.name = "testbed-vm";
  users.motd = "testbed-vm: Fizzy project board testbed, Homebox inventory testbed, InvoicePlane invoicing testbed, Kaneo project-management testbed, Keeper calendar sync testbed, Listmonk newsletter testbed, MeTube video downloader testbed, Outline knowledge-base testbed, Plane project-management testbed, Postiz social media scheduling testbed, Sure personal finance testbed, Mailpit SMTP capture, and appdata backups";

  networking.hosts.${gatewayCluster.clientAddress} = routeHosts;

  # ============================================================================
  # SECRETS
  # ============================================================================

  sops = lib.mkIf secretsEnabled {
    defaultSopsFile = secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      admin-password-hash = {
        neededForUsers = true;
      };
      affine-environment = {
        restartUnits = [
          "affine-postgresql-password.service"
          "podman-affine.service"
        ];
      };
      beszel-agent-key = {
        owner = "beszel-agent";
        group = "beszel-agent";
        mode = "0400";
        restartUnits = [ "beszel-agent.service" ];
      };
      beszel-agent-token = {
        owner = "beszel-agent";
        group = "beszel-agent";
        mode = "0400";
        restartUnits = [ "beszel-agent.service" ];
      };
      checkmate-capture-environment = {
        restartUnits = [ "checkmate-capture.service" ];
      };
      fizzy-secret-key-base = {
        restartUnits = [ "podman-fizzy.service" ];
      };
      firefly-app-key = {
        owner = "firefly-iii";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "phpfpm-firefly-iii.service" ];
      };
      gitea-oidc-client-secret = {
        owner = "gitea";
        group = "gitea";
        mode = "0400";
        restartUnits = [ "gitea-oidc-config.service" ];
      };
      homebox-api-key-pepper = {
        restartUnits = [ "homebox.service" ];
      };
      homebox-oidc-client-secret = {
        restartUnits = [ "homebox.service" ];
      };
      invoiceplane-admin-email = {
        owner = "invoiceplane";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "invoiceplane-bootstrap.service" ];
      };
      invoiceplane-admin-password = {
        owner = "invoiceplane";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "invoiceplane-bootstrap.service" ];
      };
      invoiceplane-db-password = {
        restartUnits = [
          "invoiceplane-mysql-password.service"
          "invoiceplane-bootstrap.service"
          "phpfpm-invoiceplane.service"
        ];
      };
      invoiceplane-encryption-key = {
        owner = "invoiceplane";
        group = "nginx";
        mode = "0400";
        restartUnits = [
          "invoiceplane-prepare.service"
          "phpfpm-invoiceplane.service"
        ];
      };
      kaneo-auth-secret = {
        restartUnits = [ "podman-kaneo.service" ];
      };
      kaneo-garage-access-key-id = {
        restartUnits = [ "podman-kaneo.service" ];
      };
      kaneo-garage-secret-access-key = {
        restartUnits = [ "podman-kaneo.service" ];
      };
      kaneo-oidc-client-secret = {
        restartUnits = [ "podman-kaneo.service" ];
      };
      kaneo-postgres-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [
          "kaneo-postgresql-password.service"
          "podman-kaneo.service"
        ];
      };
      karakeep-meili-master-key = {
        restartUnits = [ "podman-karakeep-meilisearch.service" ];
      };
      karakeep-nextauth-secret = {
        restartUnits = [ "podman-karakeep.service" ];
      };
      karakeep-oidc-client-secret = {
        restartUnits = [ "podman-karakeep.service" ];
      };
      keeper-better-auth-secret = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-encryption-key = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-google-client-id = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-google-client-secret = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-microsoft-client-id = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-microsoft-client-secret = {
        restartUnits = [ "podman-keeper.service" ];
      };
      keeper-postgres-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [
          "keeper-postgresql-password.service"
          "podman-keeper.service"
        ];
      };
      listmonk-admin-password = {
        restartUnits = [ "listmonk.service" ];
      };
      listmonk-admin-username = {
        restartUnits = [ "listmonk.service" ];
      };
      listmonk-oidc-client-secret = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [ "listmonk-oidc-config.service" ];
      };
      outline-garage-access-key-id = {
        restartUnits = [ "podman-outline.service" ];
      };
      outline-garage-secret-access-key = {
        restartUnits = [ "podman-outline.service" ];
      };
      outline-oidc-client-secret = {
        restartUnits = [ "podman-outline.service" ];
      };
      outline-postgres-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [
          "outline-postgresql-password.service"
          "podman-outline.service"
        ];
      };
      outline-secret-key = {
        restartUnits = [ "podman-outline.service" ];
      };
      outline-utils-secret = {
        restartUnits = [ "podman-outline.service" ];
      };
      plane-admin-email = {
        restartUnits = [ "plane-admin-bootstrap.service" ];
      };
      plane-admin-password = {
        restartUnits = [ "plane-admin-bootstrap.service" ];
      };
      plane-live-server-secret-key = {
        restartUnits = [
          "plane-environment.service"
          "podman-plane-api.service"
          "podman-plane-live.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      plane-garage-access-key-id = {
        restartUnits = [
          "plane-environment.service"
          "podman-plane-api.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      plane-garage-secret-access-key = {
        restartUnits = [
          "plane-environment.service"
          "podman-plane-api.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      plane-postgres-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [
          "plane-environment.service"
          "plane-postgresql-password.service"
          "podman-plane-api.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      plane-rabbitmq-password = {
        restartUnits = [
          "plane-environment.service"
          "plane-rabbitmq-config.service"
          "podman-plane-api.service"
          "podman-plane-rabbitmq.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      plane-secret-key = {
        restartUnits = [
          "plane-environment.service"
          "podman-plane-api.service"
          "podman-plane-worker.service"
          "podman-plane-beat-worker.service"
        ];
      };
      postiz-jwt-secret = {
        restartUnits = [
          "postiz-environment.service"
          "podman-postiz.service"
        ];
      };
      postiz-oidc-client-secret = {
        restartUnits = [
          "postiz-environment.service"
          "podman-postiz.service"
        ];
      };
      postiz-postgres-password = {
        restartUnits = [
          "postiz-environment.service"
          "podman-postiz-postgres.service"
          "podman-postiz.service"
        ];
      };
      postiz-temporal-postgres-password = {
        restartUnits = [
          "postiz-environment.service"
          "podman-postiz-temporal-postgres.service"
          "podman-postiz-temporal.service"
          "podman-postiz.service"
        ];
      };
      sure-oidc-client-secret = {
        restartUnits = [
          "podman-sure-web.service"
          "podman-sure-worker.service"
        ];
      };
      sure-postgres-password = {
        owner = "postgres";
        group = "postgres";
        mode = "0400";
        restartUnits = [
          "sure-postgresql-password.service"
          "podman-sure-web.service"
          "podman-sure-worker.service"
        ];
      };
      sure-secret-key-base = {
        restartUnits = [
          "podman-sure-web.service"
          "podman-sure-worker.service"
        ];
      };
      restic-password = {
        restartUnits = [ "testbed-appdata-backup.service" ];
      };
      smb-credentials = { };
    };
    templates."fizzy-environment" = {
      content = ''
        SECRET_KEY_BASE='${config.sops.placeholder."fizzy-secret-key-base"}'
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "podman-fizzy.service" ];
    };
    templates."listmonk-environment" = {
      content = ''
        LISTMONK_ADMIN_USER='${config.sops.placeholder."listmonk-admin-username"}'
        LISTMONK_ADMIN_PASSWORD='${config.sops.placeholder."listmonk-admin-password"}'
      '';
      owner = "listmonk";
      group = "listmonk";
      mode = "0400";
      restartUnits = [ "listmonk.service" ];
    };
    templates."homebox-environment" = {
      content = ''
        HBOX_AUTH_API_KEY_PEPPER='${config.sops.placeholder."homebox-api-key-pepper"}'
        HBOX_OIDC_CLIENT_SECRET='${config.sops.placeholder."homebox-oidc-client-secret"}'
      '';
      owner = "homebox";
      group = "homebox";
      mode = "0400";
      restartUnits = [ "homebox.service" ];
    };
    templates."kaneo-environment" = {
      content = ''
        AUTH_SECRET=${config.sops.placeholder."kaneo-auth-secret"}
        CUSTOM_OAUTH_CLIENT_SECRET=${config.sops.placeholder."kaneo-oidc-client-secret"}
        POSTGRES_PASSWORD=${config.sops.placeholder."kaneo-postgres-password"}
        S3_ACCESS_KEY_ID=${config.sops.placeholder."kaneo-garage-access-key-id"}
        S3_SECRET_ACCESS_KEY=${config.sops.placeholder."kaneo-garage-secret-access-key"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "podman-kaneo.service" ];
    };
    templates."karakeep-environment" = {
      content = ''
        MEILI_MASTER_KEY=${config.sops.placeholder."karakeep-meili-master-key"}
        NEXTAUTH_SECRET=${config.sops.placeholder."karakeep-nextauth-secret"}
        OAUTH_CLIENT_SECRET=${config.sops.placeholder."karakeep-oidc-client-secret"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [
        "podman-karakeep.service"
        "podman-karakeep-meilisearch.service"
      ];
    };
    templates."outline-environment" = {
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."outline-garage-access-key-id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."outline-garage-secret-access-key"}
        DATABASE_URL=postgres://outline:${
          config.sops.placeholder."outline-postgres-password"
        }@127.0.0.1:5432/outline
        OIDC_CLIENT_SECRET=${config.sops.placeholder."outline-oidc-client-secret"}
        SECRET_KEY=${config.sops.placeholder."outline-secret-key"}
        UTILS_SECRET=${config.sops.placeholder."outline-utils-secret"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "podman-outline.service" ];
    };
    templates."keeper-environment" = {
      content = ''
        BETTER_AUTH_SECRET=${config.sops.placeholder."keeper-better-auth-secret"}
        BETTER_AUTH_URL=https://keeper.jax22.com
        DATABASE_URL=postgresql://keeper:${
          config.sops.placeholder."keeper-postgres-password"
        }@127.0.0.1:5432/keeper
        ENCRYPTION_KEY=${config.sops.placeholder."keeper-encryption-key"}
        GOOGLE_CLIENT_ID=${config.sops.placeholder."keeper-google-client-id"}
        GOOGLE_CLIENT_SECRET=${config.sops.placeholder."keeper-google-client-secret"}
        MICROSOFT_CLIENT_ID=${config.sops.placeholder."keeper-microsoft-client-id"}
        MICROSOFT_CLIENT_SECRET=${config.sops.placeholder."keeper-microsoft-client-secret"}
        REDIS_URL=redis://127.0.0.1:${toString config.fleet.testbed.stack.ports.keeperRedis}
        TRUSTED_ORIGINS=https://keeper.jax22.com
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "podman-keeper.service" ];
    };
    templates."sure-environment" = {
      content = ''
        OIDC_CLIENT_SECRET='${config.sops.placeholder."sure-oidc-client-secret"}'
        POSTGRES_PASSWORD='${config.sops.placeholder."sure-postgres-password"}'
        SECRET_KEY_BASE='${config.sops.placeholder."sure-secret-key-base"}'
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [
        "podman-sure-web.service"
        "podman-sure-worker.service"
      ];
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "systemd-journal"
      "testbed"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.testbed.stack = {
    enable = true;
    gatewayAddresses = gatewayCluster.addresses;
    fizzy.environmentFile =
      if secretsEnabled then
        config.sops.templates."fizzy-environment".path
      else
        "/run/secrets/fizzy-environment";
    homebox = {
      bindAddress = host.ip;
      environmentFile =
        if secretsEnabled then
          config.sops.templates."homebox-environment".path
        else
          "/run/secrets/homebox-environment";
    };
    invoiceplane = {
      adminEmailFile =
        if secretsEnabled then
          config.sops.secrets.invoiceplane-admin-email.path
        else
          "/run/secrets/invoiceplane-admin-email";
      adminPasswordFile =
        if secretsEnabled then
          config.sops.secrets.invoiceplane-admin-password.path
        else
          "/run/secrets/invoiceplane-admin-password";
      bindAddress = host.ip;
      encryptionKeyFile =
        if secretsEnabled then
          config.sops.secrets.invoiceplane-encryption-key.path
        else
          "/run/secrets/invoiceplane-encryption-key";
    };
    kaneo.environmentFile =
      if secretsEnabled then
        config.sops.templates."kaneo-environment".path
      else
        "/run/secrets/kaneo-environment";
    karakeep.environmentFile =
      if secretsEnabled then
        config.sops.templates."karakeep-environment".path
      else
        "/run/secrets/karakeep-environment";
    gitea.oidc = lib.mkIf secretsEnabled {
      enable = true;
      clientSecretFile = config.sops.secrets.gitea-oidc-client-secret.path;
    };
    keeper.environmentFile =
      if secretsEnabled then
        config.sops.templates."keeper-environment".path
      else
        "/run/secrets/keeper-environment";
    listmonk = {
      adminEnvironmentFile =
        if secretsEnabled then
          config.sops.templates."listmonk-environment".path
        else
          "/run/secrets/listmonk-environment";
      bindAddress = host.ip;
      oidcClientSecretFile =
        if secretsEnabled then
          config.sops.secrets.listmonk-oidc-client-secret.path
        else
          "/run/secrets/listmonk-oidc-client-secret";
    };
    mailpit = {
      bindAddress = host.ip;
      smtpBindAddress = "0.0.0.0";
    };
    outline.environmentFile =
      if secretsEnabled then
        config.sops.templates."outline-environment".path
      else
        "/run/secrets/outline-environment";
    plane.bindAddress = host.ip;
    postiz.bindAddress = host.ip;
    secrets.enable = secretsEnabled;
    sure = {
      bindAddress = host.ip;
      environmentFile =
        if secretsEnabled then
          config.sops.templates."sure-environment".path
        else
          "/run/secrets/sure-environment";
      postgresPasswordFile =
        if secretsEnabled then
          config.sops.secrets.sure-postgres-password.path
        else
          "/run/secrets/sure-postgres-password";
    };
    inherit serviceDomains;
    smb.backupDevice = "//10.2.10.10/backups";
    smb.mediaDevice = "//nas.home.arpa/media";
  };
}
