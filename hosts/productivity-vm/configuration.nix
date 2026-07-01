{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  gatewayCluster = import ../../lib/gateway-cluster.nix { inherit hosts; };
  host = hosts.productivity-vm;
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
    ../../modules/productivity
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  fleet.host.name = "productivity-vm";
  users.motd = "productivity-vm: AFFiNE, Git, docs, paperless, RSS, search, vault, files, S3, netboot.xyz, and appdata backups";

  networking.hosts.${gatewayCluster.clientAddress} = routeHosts;

  # ============================================================================
  # SECRETS
  # ============================================================================

  sops = lib.mkIf secretsEnabled {
    defaultSopsFile = secretsFile;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets = {
      affine-environment = {
        restartUnits = [
          "affine-postgresql-password.service"
          "podman-affine.service"
        ];
      };
      admin-password-hash = {
        neededForUsers = true;
      };
      authentik-bootstrap-email = {
        owner = "paperless";
        group = "paperless";
        mode = "0400";
        restartUnits = [ "paperless-oidc-superuser.service" ];
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
      firefly-app-key = {
        owner = "firefly-iii";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "phpfpm-firefly-iii.service" ];
      };
      freshrss-admin-username = {
        owner = "freshrss";
        group = "freshrss";
        mode = "0400";
        restartUnits = [ "freshrss-config.service" ];
      };
      freshrss-admin-password = {
        owner = "freshrss";
        group = "freshrss";
        mode = "0400";
        restartUnits = [ "freshrss-config.service" ];
      };
      forgejo-oidc-client-secret = {
        owner = "forgejo";
        group = "forgejo";
        mode = "0400";
        restartUnits = [ "forgejo-oidc-config.service" ];
      };
      gitea-oidc-client-secret = {
        owner = "gitea";
        group = "gitea";
        mode = "0400";
        restartUnits = [ "gitea-oidc-config.service" ];
      };
      garage-admin-token = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };
      kaneo-garage-access-key-id = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage-kaneo-bucket.service" ];
      };
      kaneo-garage-secret-access-key = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage-kaneo-bucket.service" ];
      };
      garage-metrics-token = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };
      garage-rpc-secret = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
      };
      invoiceplane-db-password = {
        restartUnits = [
          "invoiceplane-mysql-password.service"
          "phpfpm-invoiceplane.service"
        ];
      };
      memos-admin-pat = {
        owner = "memos";
        group = "memos";
        mode = "0400";
        restartUnits = [ "memos-oidc-config.service" ];
      };
      memos-oidc-client-secret = {
        owner = "memos";
        group = "memos";
        mode = "0400";
        restartUnits = [ "memos-oidc-config.service" ];
      };
      nextcloud-admin-password = {
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [
          "nextcloud-admin-user.service"
          "nextcloud-setup.service"
        ];
      };
      nextcloud-admin-username = {
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-admin-user.service" ];
      };
      nextcloud-oidc-client-secret = {
        owner = "nextcloud";
        group = "nextcloud";
        mode = "0400";
        restartUnits = [ "nextcloud-oidc-config.service" ];
      };
      paperless-admin-password = {
        restartUnits = [ "paperless-scheduler.service" ];
      };
      paperless-admin-username = {
        owner = "paperless";
        group = "paperless";
        mode = "0400";
        restartUnits = [
          "paperless-consumer.service"
          "paperless-oidc-superuser.service"
          "paperless-scheduler.service"
          "paperless-task-queue.service"
          "paperless-web.service"
        ];
      };
      paperless-oidc-client-secret = {
        owner = "paperless";
        group = "paperless";
        mode = "0400";
        restartUnits = [
          "paperless-consumer.service"
          "paperless-scheduler.service"
          "paperless-task-queue.service"
          "paperless-web.service"
        ];
      };
      restic-password = {
        restartUnits = [ "productivity-appdata-backup.service" ];
      };
      rustfs-environment = {
        restartUnits = [ "podman-rustfs.service" ];
      };
      rustfs-oidc-client-secret = {
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [
          "podman-rustfs.service"
          "rustfs-oidc-policy.service"
        ];
      };
      searxng-environment = {
        restartUnits = [
          "searx-init.service"
          "searx.service"
        ];
      };
      shlink-environment = {
        restartUnits = [
          "shlink-postgresql-password.service"
          "podman-shlink.service"
        ];
      };
      smb-credentials = { };
      syncthing-gui-password = {
        owner = "syncthing";
        group = "syncthing";
        mode = "0400";
        restartUnits = [ "syncthing.service" ];
      };
      syncthing-gui-username = {
        owner = "syncthing";
        group = "syncthing";
        mode = "0400";
        restartUnits = [ "syncthing-gui-username.service" ];
      };
      vaultwarden-environment = {
        restartUnits = [ "vaultwarden.service" ];
      };
    };
    templates."paperless-oidc-environment" = {
      content = ''
        PAPERLESS_ADMIN_USER='${config.sops.placeholder."paperless-admin-username"}'
        PAPERLESS_SOCIALACCOUNT_PROVIDERS='${
          builtins.toJSON {
            openid_connect = {
              OAUTH_PKCE_ENABLED = true;
              APPS = [
                {
                  provider_id = "authentik";
                  name = "Authentik";
                  client_id = "paperless";
                  secret = config.sops.placeholder."paperless-oidc-client-secret";
                  settings = {
                    server_url = "https://auth.jax22.com/application/o/paperless/.well-known/openid-configuration";
                    fetch_userinfo = true;
                  };
                }
              ];
              SCOPE = [
                "openid"
                "profile"
                "email"
              ];
            };
          }
        }'
      '';
      owner = "paperless";
      group = "paperless";
      mode = "0400";
      restartUnits = [
        "paperless-consumer.service"
        "paperless-scheduler.service"
        "paperless-task-queue.service"
        "paperless-web.service"
      ];
    };
    templates."rustfs-oidc-environment" = {
      content = ''
        RUSTFS_IDENTITY_OPENID_CLIENT_SECRET_authentik=${
          config.sops.placeholder."rustfs-oidc-client-secret"
        }
      '';
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [
        "podman-rustfs.service"
        "rustfs-oidc-policy.service"
      ];
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "productivity"
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SYSTEM
  # ============================================================================

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.productivity.stack = {
    enable = true;
    secrets.enable = secretsEnabled;
    inherit serviceDomains;
    forgejo.oidc = lib.mkIf secretsEnabled {
      enable = true;
      clientSecretFile = config.sops.secrets.forgejo-oidc-client-secret.path;
    };
    gitea.oidc = lib.mkIf secretsEnabled {
      enable = true;
      clientSecretFile = config.sops.secrets.gitea-oidc-client-secret.path;
    };
    garage.kaneoUploads = lib.mkIf secretsEnabled {
      enable = true;
      accessKeyIdFile = config.sops.secrets.kaneo-garage-access-key-id.path;
      secretAccessKeyFile = config.sops.secrets.kaneo-garage-secret-access-key.path;
    };
    memos.oidc = lib.mkIf secretsEnabled {
      enable = true;
      adminTokenFile = config.sops.secrets.memos-admin-pat.path;
      clientSecretFile = config.sops.secrets.memos-oidc-client-secret.path;
    };
    onDemandLauncher.gatewayAddresses = gatewayCluster.addresses;
    netbootxyz = {
      enable = true;
      assetBindAddress = host.ip;
      tftpBindAddress = host.ip;
      webUiBindAddress = host.ip;
    };
    paperless.oidc = lib.mkIf secretsEnabled {
      adminEmailFile = config.sops.secrets.authentik-bootstrap-email.path;
      adminUsernameFile = config.sops.secrets.paperless-admin-username.path;
      enable = true;
      environmentFile = config.sops.templates."paperless-oidc-environment".path;
    };
    nextcloud.oidc = lib.mkIf secretsEnabled {
      enable = true;
      clientSecretFile = config.sops.secrets.nextcloud-oidc-client-secret.path;
    };
    rustfs.oidc = lib.mkIf secretsEnabled {
      enable = true;
      environmentFile = config.sops.templates."rustfs-oidc-environment".path;
    };
    smb.backupDevice = "//nas.home.arpa/backups";
  };

}
