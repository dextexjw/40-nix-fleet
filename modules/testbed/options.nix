{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.fleet.testbed.stack;
  serviceHostPrefixes = {
    fizzy = "fizzy";
    homebox = "homebox";
    kaneo = "kaneo";
    keeper = "keeper";
    listmonk = "listmonk";
    mailpit = "mailpit";
    plane = "plane";
  };
  mkServiceHostNames =
    domains:
    mapAttrs (
      _name: prefix: map (serviceDomain: "${prefix}.${serviceDomain}") domains
    ) serviceHostPrefixes;
  mkServiceHosts = domains: mapAttrs (_name: names: head names) (mkServiceHostNames domains);
in
{
  options.fleet.testbed.stack = {
    enable = mkEnableOption "testbed-vm application stack";

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
      description = "Canonical internal hostnames for testbed services.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        fizzy = 9010;
        homebox = 7745;
        kaneo = 5173;
        keeper = 3000;
        keeperApi = 3001;
        keeperRedis = 6380;
        listmonk = 9000;
        mailpit = 8025;
        mailpitSmtp = 1025;
        plane = 9020;
        planeAdmin = 9022;
        planeApi = 9025;
        planeLive = 9024;
        planeRabbitmq = 5673;
        planeRedis = 6381;
        planeSpace = 9023;
        planeWeb = 9021;
      };
      description = "LAN-facing or local testbed service ports.";
    };

    fizzy = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Fizzy testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/fizzy-environment";
        description = "Runtime environment file containing SECRET_KEY_BASE.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.fizzy}";
        description = "Canonical external Fizzy URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/basecamp/fizzy@sha256:cdb99bc4e6d896b62ca9afd73a406bfac68e5526c4147f3f9c562f20533e64d2";
        description = "Pinned Fizzy OCI image.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/fizzy";
        description = "Persistent Fizzy state directory.";
      };
    };

    homebox = {
      allowLocalLogin = mkOption {
        type = types.bool;
        default = true;
        description = "Keep Homebox local login available for break-glass access.";
      };

      allowRegistration = mkOption {
        type = types.bool;
        default = false;
        description = "Allow new Homebox accounts to self-register.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address Homebox listens on.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/homebox-environment";
        description = "Runtime environment file containing Homebox secret settings.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.homebox}";
        description = "Canonical external Homebox URL.";
      };

      oidcClientId = mkOption {
        type = types.str;
        default = "homebox";
        description = "Homebox Authentik OIDC client identifier.";
      };

      oidcIssuerUrl = mkOption {
        type = types.str;
        default = "https://auth.jax22.com/application/o/homebox/";
        description = "Homebox Authentik OIDC issuer URL.";
      };

      package = mkOption {
        type = types.package;
        default = pkgs.homebox;
        defaultText = literalExpression "pkgs.homebox";
        description = "Homebox package to run.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/homebox";
        description = "Persistent Homebox state directory.";
      };
    };

    kaneo = {
      databaseName = mkOption {
        type = types.str;
        default = "kaneo";
        description = "PostgreSQL database used by Kaneo.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "kaneo";
        description = "PostgreSQL role used by Kaneo.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Kaneo project-management testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/kaneo-environment";
        description = "Runtime environment file containing Kaneo secrets.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.kaneo}";
        description = "Canonical external Kaneo URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/usekaneo/kaneo@sha256:11f554b96d826cea29d4f1d06b33cdc97b9cb64e1985eba67f1da3418dd1aaeb";
        description = "Pinned Kaneo combined API and web OCI image.";
      };

      oidc = {
        authorizationUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/authorize/";
          description = "Authentik OAuth2 authorization endpoint.";
        };

        clientId = mkOption {
          type = types.str;
          default = "kaneo";
          description = "Kaneo Authentik OIDC client identifier.";
        };

        discoveryUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/kaneo/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by Kaneo.";
        };

        logoutUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/kaneo/end-session/";
          description = "Authentik OIDC logout endpoint used by Kaneo.";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://kaneo.jax22.com/api/auth/oauth2/callback/custom";
          description = "Strict Kaneo OIDC callback URL registered in Authentik.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested by Kaneo.";
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

      s3 = {
        bucket = mkOption {
          type = types.str;
          default = "kaneo-uploads";
          description = "Garage S3 bucket used by Kaneo uploads.";
        };

        endpoint = mkOption {
          type = types.str;
          default = "https://garage.jax22.com";
          description = "Browser-reachable Garage S3 endpoint used by Kaneo.";
        };

        forcePathStyle = mkOption {
          type = types.bool;
          default = true;
          description = "Use path-style S3 URLs for Garage.";
        };

        region = mkOption {
          type = types.str;
          default = "garage";
          description = "Garage S3 region name.";
        };
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/kaneo";
        description = "Small Kaneo runtime working directory; durable app state is PostgreSQL plus Garage S3.";
      };
    };

    keeper = {
      blockPrivateResolution = mkOption {
        type = types.bool;
        default = true;
        description = "Block Keeper outbound fetches from resolving to private or reserved networks.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Keeper calendar sync testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/keeper-environment";
        description = "Runtime environment file containing Keeper secrets and integration settings.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://keeper.jax22.com";
        description = "Canonical external Keeper URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/ridafkih/keeper-services:2.12";
        description = "Pinned Keeper services OCI image.";
      };

      privateResolutionWhitelist = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Hostnames or IP addresses exempt from Keeper private-resolution blocking.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/keeper";
        description = "Persistent Keeper state directory.";
      };
    };

    listmonk = {
      adminEnvironmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/listmonk-environment";
        description = "Runtime environment file containing LISTMONK_ADMIN_USER and LISTMONK_ADMIN_PASSWORD.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Address Listmonk listens on.";
      };

      oidcClientSecretFile = mkOption {
        type = types.path;
        default = "/run/secrets/listmonk-oidc-client-secret";
        description = "Runtime file containing the Listmonk Authentik OIDC client secret.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.listmonk}";
        description = "Canonical external Listmonk URL.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/listmonk";
        description = "Persistent Listmonk state directory.";
      };
    };

    mailpit = {
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address Mailpit UI/API listens on.";
      };

      smtpBindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address Mailpit SMTP capture listens on.";
      };
    };

    plane = {
      adminEmailFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-admin-email";
        description = "Runtime file containing the initial Plane instance admin email.";
      };

      adminPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-admin-password";
        description = "Runtime file containing the initial Plane instance admin password.";
      };

      backendImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-backend@sha256:2da6972c81a0ac797c9d04db448aa5985e1257fc5d9724b165e9c07791e8cc64";
        description = "Pinned Plane backend OCI image.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address the local Plane reverse proxy listens on.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Plane project-management testbed service.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.plane}";
        description = "Canonical external Plane URL.";
      };

      frontendImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-frontend@sha256:20d83ae9257415593a0522b607b3827dde429d8511b1bcf97f6313e55fc60c09";
        description = "Pinned Plane frontend OCI image.";
      };

      adminImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-admin@sha256:82a2b82f34a24b95e2b663327c34d32828d24680aef258f901ebc0adc27542ea";
        description = "Pinned Plane admin OCI image.";
      };

      liveImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-live@sha256:d9ce8992425d9724ccd972f532dd46476b64c53c9e886f0a4eda8915f8b700d2";
        description = "Pinned Plane live collaboration OCI image.";
      };

      garageAccessKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-garage-access-key-id";
        description = "Runtime file containing the Plane Garage access key ID.";
      };

      garageBucket = mkOption {
        type = types.str;
        default = "plane-uploads";
        description = "Garage bucket used by Plane object storage.";
      };

      garageEndpoint = mkOption {
        type = types.str;
        default = "https://garage.jax22.com";
        description = "Browser-reachable Garage S3 endpoint used by Plane.";
      };

      garageRegion = mkOption {
        type = types.str;
        default = "garage";
        description = "Garage S3 region name used by Plane.";
      };

      garageSecretKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-garage-secret-access-key";
        description = "Runtime file containing the Plane Garage secret access key.";
      };

      postgresPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-postgres-password";
        description = "Runtime file containing the Plane PostgreSQL role password.";
      };

      rabbitmqImage = mkOption {
        type = types.str;
        default = "docker.io/rabbitmq@sha256:567378bee7c4b7401bc5165e3ff406c4481ae3cbd9daed4ad3c2821bd97ae3f4";
        description = "Pinned RabbitMQ OCI image used by Plane workers.";
      };

      rabbitmqPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-rabbitmq-password";
        description = "Runtime file containing the Plane RabbitMQ password.";
      };

      secretKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-secret-key";
        description = "Runtime file containing the Plane Django SECRET_KEY.";
      };

      liveServerSecretKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/plane-live-server-secret-key";
        description = "Runtime file containing the Plane live-server shared secret.";
      };

      spaceImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-space@sha256:d03aa511c5292b6feb3119fc8d399e0e2f8c2e5b308c076779691cff54bd3451";
        description = "Pinned Plane Space OCI image.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/plane";
        description = "Persistent Plane state directory.";
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
        default = "/mnt/backups/restic/appdata/testbed-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by testbed-appdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/testbed-appdata-restore-check";
        description = "Temporary target used by testbed-appdata-restore-check.service.";
      };
    };
  };
}
