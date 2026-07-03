{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.productivity.stack;
  appdata = cfg.appdataRoot;
  serviceHostPrefixes = {
    docs = "docs";
    forgejo = "forgejo";
    freshrss = "freshrss";
    garage = "garage";
    garageWeb = "s3.garage";
    iperf3 = "iperf3";
    memos = "memos";
    netbootxyz = "netbootxyz";
    nextcloud = "nextcloud";
    openspeedtest = "openspeedtest";
    paperless = "paperless";
    privatebin = "privatebin";
    rustdesk = "rustdesk";
    rustfs = "s3.rustfs";
    rustfsConsole = "rustfs";
    searxng = "searxng";
    shlink = "s";
    shlinkWeb = "shlink";
    syncthing = "syncthing";
    vaultwarden = "vaultwarden";
  };
  serviceHostKeys = [
    "forgejo"
    "docs"
    "paperless"
    "freshrss"
    "searxng"
    "privatebin"
    "vaultwarden"
    "syncthing"
    "nextcloud"
    "openspeedtest"
    "iperf3"
    "memos"
    "netbootxyz"
    "rustdesk"
    "garage"
    "garageWeb"
    "rustfs"
    "rustfsConsole"
    "shlink"
    "shlinkWeb"
  ];
  mkServiceHostNames =
    domains:
    mapAttrs (
      _name: prefix: map (serviceDomain: "${prefix}.${serviceDomain}") domains
    ) serviceHostPrefixes;
  mkServiceHosts = domains: mapAttrs (_name: names: head names) (mkServiceHostNames domains);
  mkServiceHostAliases = domains: mapAttrs (_name: names: tail names) (mkServiceHostNames domains);
in
{
  options.fleet.productivity.stack = {
    enable = mkEnableOption "productivity-vm application stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    gatewayAddresses = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Gateway node addresses allowed to reach backend service ports.";
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
        iperf3 = 5201;
        itTools = 8093;
        memos = 5230;
        netbootxyzAsset = 8083;
        netbootxyzTftp = 69;
        netbootxyzWebUi = 3001;
        openspeedtest = 8989;
        rustdeskRelay = 21117;
        rustdeskSignal = 21116;
        rustfsApi = 9000;
        rustfsConsole = 9001;
        searxng = 8087;
        shlink = 8088;
        shlinkWeb = 8089;
        syncthing = 8384;
        vaultwarden = 8222;
      };
      description = "LAN-facing web or API ports for non-nginx productivity services.";
    };

    itTools = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run IT-Tools on productivity-vm.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/corentinth/it-tools@sha256:6f177c156b9466610e0f2093e24668b78da501c66f0054f98bccb582b74ab26b";
        description = "Pinned IT-Tools OCI image reference.";
      };

      resources = {
        cpus = mkOption {
          type = types.str;
          default = "0.5";
          description = "Podman CPU limit for IT-Tools.";
        };

        memory = mkOption {
          type = types.str;
          default = "128m";
          description = "Podman memory limit for IT-Tools.";
        };

        memorySwap = mkOption {
          type = types.str;
          default = "192m";
          description = "Podman total memory plus swap limit for IT-Tools.";
        };
      };
    };

    garage = {
      kaneoUploads = {
        accessKeyIdFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage access key ID used by Kaneo uploads.";
        };

        bucket = mkOption {
          type = types.str;
          default = "kaneo-uploads";
          description = "Garage bucket provisioned for Kaneo uploads.";
        };

        corsAllowedOrigin = mkOption {
          type = types.str;
          default = "https://kaneo.jax22.com";
          description = "Browser origin allowed to upload Kaneo objects through Garage.";
        };

        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Garage bucket and access key used by Kaneo uploads.";
        };

        endpointUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:${toString cfg.ports.garageS3}";
          description = "Local Garage S3 endpoint used by provisioning and validation.";
        };

        keyName = mkOption {
          type = types.str;
          default = "kaneo";
          description = "Garage key name assigned to the Kaneo upload credentials.";
        };

        secretAccessKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage secret access key used by Kaneo uploads.";
        };
      };

      planeUploads = {
        accessKeyIdFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage access key ID used by Plane uploads.";
        };

        bucket = mkOption {
          type = types.str;
          default = "plane-uploads";
          description = "Garage bucket provisioned for Plane uploads.";
        };

        corsAllowedOrigin = mkOption {
          type = types.str;
          default = "https://plane.jax22.com";
          description = "Browser origin allowed to upload Plane objects through Garage.";
        };

        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Garage bucket and access key used by Plane uploads.";
        };

        endpointUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:${toString cfg.ports.garageS3}";
          description = "Local Garage S3 endpoint used by provisioning and validation.";
        };

        keyName = mkOption {
          type = types.str;
          default = "plane";
          description = "Garage key name assigned to the Plane upload credentials.";
        };

        secretAccessKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage secret access key used by Plane uploads.";
        };
      };

      outlineUploads = {
        accessKeyIdFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage access key ID used by Outline uploads.";
        };

        bucket = mkOption {
          type = types.str;
          default = "outline-uploads";
          description = "Garage bucket provisioned for Outline uploads.";
        };

        corsAllowedOrigin = mkOption {
          type = types.str;
          default = "https://outline.jax22.com";
          description = "Browser origin allowed to upload Outline objects through Garage.";
        };

        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Garage bucket and access key used by Outline uploads.";
        };

        endpointUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:${toString cfg.ports.garageS3}";
          description = "Local Garage S3 endpoint used by provisioning and validation.";
        };

        keyName = mkOption {
          type = types.str;
          default = "outline";
          description = "Garage key name assigned to the Outline upload credentials.";
        };

        secretAccessKeyFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing the Garage secret access key used by Outline uploads.";
        };
      };
    };

    netbootxyz = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run netboot.xyz network boot service on productivity-vm.";
      };

      assetBindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address used for the local netboot.xyz asset server listener.";
        example = "10.2.20.114";
      };

      assetPort = mkOption {
        type = types.port;
        default = cfg.ports.netbootxyzAsset;
        description = "Host port mapped to the netboot.xyz container asset server.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/netbootxyz/netbootxyz@sha256:942dfb60d11846b657a54dd36f1addf636b7736f38009223ce328ebc37f54d39";
        description = "Pinned netboot.xyz OCI image reference.";
      };

      menuVersion = mkOption {
        type = types.str;
        default = "2.0.88";
        description = "netboot.xyz menu version used by the container.";
      };

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open netboot.xyz web UI, asset, and TFTP ports.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/netbootxyz";
        description = "Persistent netboot.xyz state directory.";
      };

      tftpBindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address used for the netboot.xyz TFTP listener.";
        example = "10.2.20.114";
      };

      tftpPort = mkOption {
        type = types.port;
        default = cfg.ports.netbootxyzTftp;
        description = "Host UDP port mapped to the netboot.xyz TFTP service.";
      };

      webUiBindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address used for the netboot.xyz web UI listener.";
        example = "10.2.20.114";
      };

      webUiPort = mkOption {
        type = types.port;
        default = cfg.ports.netbootxyzWebUi;
        description = "Host port mapped to the netboot.xyz web configuration UI.";
      };
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

    forgejo = {
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Forgejo Authentik OpenID Connect login source.";
        };

        authName = mkOption {
          type = types.str;
          default = "authentik";
          description = "Forgejo authentication source name. This is part of the OAuth callback path.";
        };

        autoDiscoverUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/forgejo/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by Forgejo.";
        };

        clientId = mkOption {
          type = types.str;
          default = "forgejo";
          description = "OIDC client ID registered in Authentik.";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Forgejo OIDC client secret.";
        };

        iconUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/static/dist/assets/icons/icon.png";
          description = "Icon URL shown on the Forgejo login button.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "email"
            "profile"
          ];
          description = "Additional OIDC scopes requested by Forgejo. Forgejo adds openid implicitly.";
        };
      };
    };

    paperless = {
      oidc = {
        adminEmailFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Authentik admin email promoted to Paperless staff and superuser.";
        };

        adminUsernameFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Paperless admin username promoted to staff and superuser.";
        };

        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Configure Paperless-ngx Authentik OIDC login.";
        };

        clientId = mkOption {
          type = types.str;
          default = "paperless";
          description = "OIDC client ID registered in Authentik.";
        };

        displayName = mkOption {
          type = types.str;
          default = "Authentik";
          description = "Paperless sign-in button label for the OIDC provider.";
        };

        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime env file containing PAPERLESS_SOCIALACCOUNT_PROVIDERS.";
        };

        providerId = mkOption {
          type = types.str;
          default = "authentik";
          description = "Paperless django-allauth OIDC provider ID.";
        };

        scope = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested by Paperless.";
        };

        serverUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/paperless/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by Paperless.";
        };
      };
    };

    memos = {
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Memos Authentik OAuth2 identity provider.";
        };

        adminTokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing a Memos admin personal access token.";
        };

        apiBaseUrl = mkOption {
          type = types.str;
          default = "http://127.0.0.1:${toString cfg.ports.memos}";
          description = "Local Memos API base URL used by the OIDC provisioning unit.";
        };

        authUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/authorize/";
          description = "Authentik OAuth2 authorization endpoint.";
        };

        clientId = mkOption {
          type = types.str;
          default = "memos";
          description = "OIDC client ID registered in Authentik.";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Memos OIDC client secret.";
        };

        displayName = mkOption {
          type = types.str;
          default = "Authentik";
          description = "Memos sign-in button label for the identity provider.";
        };

        fieldMapping = {
          avatarUrl = mkOption {
            type = types.str;
            default = "picture";
            description = "OAuth2 userinfo field mapped to the Memos avatar URL.";
          };

          displayName = mkOption {
            type = types.str;
            default = "name";
            description = "OAuth2 userinfo field mapped to the Memos display name.";
          };

          email = mkOption {
            type = types.str;
            default = "email";
            description = "OAuth2 userinfo field mapped to the Memos email.";
          };

          identifier = mkOption {
            type = types.str;
            default = "sub";
            description = "OAuth2 userinfo field mapped to the Memos external identity.";
          };
        };

        identifierFilter = mkOption {
          type = types.str;
          default = "";
          description = "Optional Memos identifier allow-list regex.";
        };

        providerUid = mkOption {
          type = types.str;
          default = "authentik";
          description = "Stable Memos identity provider UID.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OAuth2 scopes requested by Memos.";
        };

        tokenUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/token/";
          description = "Authentik OAuth2 token endpoint.";
        };

        userInfoUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/userinfo/";
          description = "Authentik OAuth2 userinfo endpoint.";
        };
      };
    };

    nextcloud = {
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Configure Nextcloud Authentik OIDC login with the native user_oidc app.";
        };

        clientId = mkOption {
          type = types.str;
          default = "nextcloud";
          description = "OIDC client ID registered in Authentik.";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Nextcloud OIDC client secret.";
        };

        discoveryUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/nextcloud/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by Nextcloud.";
        };

        mapping = {
          displayName = mkOption {
            type = types.str;
            default = "name";
            description = "OIDC claim mapped to the Nextcloud display name.";
          };

          email = mkOption {
            type = types.str;
            default = "email";
            description = "OIDC claim mapped to the Nextcloud email address.";
          };

          uid = mkOption {
            type = types.str;
            default = "sub";
            description = "OIDC claim mapped to the Nextcloud OIDC user ID.";
          };
        };

        providerId = mkOption {
          type = types.str;
          default = "authentik";
          description = "Stable Nextcloud user_oidc provider identifier used in the login button.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "email"
            "profile"
          ];
          description = "OIDC scopes requested by Nextcloud.";
        };
      };
    };

    rustfs = {
      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Configure RustFS console Authentik OIDC login.";
        };

        clientId = mkOption {
          type = types.str;
          default = "rustfs-console";
          description = "OIDC client ID registered in Authentik.";
        };

        configUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/rustfs-console/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by RustFS.";
        };

        displayName = mkOption {
          type = types.str;
          default = "Authentik";
          description = "RustFS console OIDC provider label.";
        };

        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime env file containing RUSTFS_IDENTITY_OPENID_CLIENT_SECRET_authentik.";
        };

        providerId = mkOption {
          type = types.str;
          default = "authentik";
          description = "RustFS OIDC provider ID.";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://rustfs.jax22.com/rustfs/admin/v3/oidc/callback/authentik";
          description = "Strict RustFS OIDC callback URL registered in Authentik.";
        };

        rolePolicy = mkOption {
          type = types.str;
          default = "rustfs-console-admin";
          description = "RustFS IAM policy assigned to OIDC console sessions.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested by RustFS.";
        };
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = {
    assertions = [
      {
        assertion = !cfg.nextcloud.oidc.enable || cfg.nextcloud.oidc.clientSecretFile != null;
        message = "fleet.productivity.stack.nextcloud.oidc.clientSecretFile must be set when Nextcloud OIDC is enabled.";
      }
      {
        assertion = !cfg.paperless.oidc.enable || cfg.paperless.oidc.environmentFile != null;
        message = "fleet.productivity.stack.paperless.oidc.environmentFile must be set when Paperless OIDC is enabled.";
      }
      {
        assertion = !cfg.paperless.oidc.enable || cfg.paperless.oidc.adminEmailFile != null;
        message = "fleet.productivity.stack.paperless.oidc.adminEmailFile must be set when Paperless OIDC is enabled.";
      }
      {
        assertion = !cfg.paperless.oidc.enable || cfg.paperless.oidc.adminUsernameFile != null;
        message = "fleet.productivity.stack.paperless.oidc.adminUsernameFile must be set when Paperless OIDC is enabled.";
      }
      {
        assertion = !cfg.rustfs.oidc.enable || cfg.rustfs.oidc.environmentFile != null;
        message = "fleet.productivity.stack.rustfs.oidc.environmentFile must be set when RustFS OIDC is enabled.";
      }
      {
        assertion = !cfg.garage.kaneoUploads.enable || cfg.garage.kaneoUploads.accessKeyIdFile != null;
        message = "fleet.productivity.stack.garage.kaneoUploads.accessKeyIdFile must be set when Kaneo Garage uploads are enabled.";
      }
      {
        assertion = !cfg.garage.kaneoUploads.enable || cfg.garage.kaneoUploads.secretAccessKeyFile != null;
        message = "fleet.productivity.stack.garage.kaneoUploads.secretAccessKeyFile must be set when Kaneo Garage uploads are enabled.";
      }
      {
        assertion = !cfg.garage.planeUploads.enable || cfg.garage.planeUploads.accessKeyIdFile != null;
        message = "fleet.productivity.stack.garage.planeUploads.accessKeyIdFile must be set when Plane Garage uploads are enabled.";
      }
      {
        assertion = !cfg.garage.planeUploads.enable || cfg.garage.planeUploads.secretAccessKeyFile != null;
        message = "fleet.productivity.stack.garage.planeUploads.secretAccessKeyFile must be set when Plane Garage uploads are enabled.";
      }
      {
        assertion = !cfg.garage.outlineUploads.enable || cfg.garage.outlineUploads.accessKeyIdFile != null;
        message = "fleet.productivity.stack.garage.outlineUploads.accessKeyIdFile must be set when Outline Garage uploads are enabled.";
      }
      {
        assertion =
          !cfg.garage.outlineUploads.enable || cfg.garage.outlineUploads.secretAccessKeyFile != null;
        message = "fleet.productivity.stack.garage.outlineUploads.secretAccessKeyFile must be set when Outline Garage uploads are enabled.";
      }
    ];
  };
}
