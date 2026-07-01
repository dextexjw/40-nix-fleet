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
  users.motd = "testbed-vm: Fizzy project board testbed, Homebox inventory testbed, Kaneo project-management testbed, Keeper calendar sync testbed, Listmonk newsletter testbed, Mailpit SMTP capture, and appdata backups";

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
      homebox-api-key-pepper = {
        restartUnits = [ "homebox.service" ];
      };
      homebox-oidc-client-secret = {
        restartUnits = [ "homebox.service" ];
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
    kaneo.environmentFile =
      if secretsEnabled then
        config.sops.templates."kaneo-environment".path
      else
        "/run/secrets/kaneo-environment";
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
    mailpit.bindAddress = host.ip;
    secrets.enable = secretsEnabled;
    inherit serviceDomains;
    smb.backupDevice = "//10.2.10.10/backups";
  };
}
