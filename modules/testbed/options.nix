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
    affine = "affine";
    firefly = "firefly";
    fizzy = "fizzy";
    gitea = "gitea";
    homebox = "homebox";
    invoiceplane = "invoiceplane";
    kaneo = "kaneo";
    keeper = "keeper";
    listmonk = "listmonk";
    mailpit = "mailpit";
    outline = "outline";
    plane = "plane";
    postiz = "postiz";
    stirlingPdf = "stirling-pdf";
    sure = "sure";
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
        affine = 3010;
        affineRedis = 6379;
        firefly = 80;
        fizzy = 9010;
        gitea = 9070;
        homebox = 7745;
        invoiceplane = 9060;
        kaneo = 5173;
        keeper = 3000;
        keeperApi = 3001;
        keeperRedis = 6380;
        listmonk = 9000;
        mailpit = 8025;
        mailpitSmtp = 1025;
        metube = 8081;
        outline = 9050;
        outlineRedis = 6383;
        plane = 9020;
        planeAdmin = 9022;
        planeApi = 9025;
        planeLive = 9024;
        planeRabbitmq = 5673;
        planeRedis = 6381;
        planeSpace = 9023;
        planeWeb = 9021;
        postiz = 9040;
        stirlingPdf = 8086;
        sure = 9030;
        sureRedis = 6382;
      };
      description = "LAN-facing or local testbed service ports.";
    };

    affine = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run AFFiNE on testbed-vm.";
      };

      databaseName = mkOption {
        type = types.str;
        default = "affine";
        description = "PostgreSQL database used by AFFiNE.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "affine";
        description = "PostgreSQL role used by AFFiNE.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.affine}";
        description = "Canonical external AFFiNE URL used for generated links.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/toeverything/affine@sha256:725aaceb0ed94d4b832ae6ef9414503291c9b2b4f60bd6f3c7eef571b6149add";
        description = "Pinned AFFiNE OCI image reference.";
      };

      redisDatabase = mkOption {
        type = types.int;
        default = 0;
        description = "Redis database index used by AFFiNE.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/affine";
        description = "Persistent AFFiNE state directory.";
      };

      resources = {
        cpus = mkOption {
          type = types.str;
          default = "1.5";
          description = "Podman CPU limit for the AFFiNE server and migration container.";
        };

        memory = mkOption {
          type = types.str;
          default = "1536m";
          description = "Podman memory limit for the AFFiNE server and migration container.";
        };

        memorySwap = mkOption {
          type = types.str;
          default = "2048m";
          description = "Podman total memory plus swap limit for the AFFiNE server and migration container.";
        };
      };
    };

    firefly = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Firefly III on testbed-vm.";
      };
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

    gitea = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Gitea on testbed-vm.";
      };

      oidc = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Provision the Gitea Authentik OpenID Connect login source.";
        };

        authName = mkOption {
          type = types.str;
          default = "authentik";
          description = "Gitea authentication source name. This is part of the OAuth callback path.";
        };

        autoDiscoverUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/gitea/.well-known/openid-configuration";
          description = "Authentik OIDC discovery URL used by Gitea.";
        };

        clientId = mkOption {
          type = types.str;
          default = "gitea";
          description = "OIDC client ID registered in Authentik.";
        };

        clientSecretFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Runtime file containing the Gitea OIDC client secret.";
        };

        iconUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/static/dist/assets/icons/icon.png";
          description = "Icon URL shown on the Gitea login button.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "email"
            "profile"
          ];
          description = "Additional OIDC scopes requested by Gitea. Gitea adds openid implicitly.";
        };
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

    invoiceplane = {
      adminEmailFile = mkOption {
        type = types.path;
        default = "/run/secrets/invoiceplane-admin-email";
        description = "Runtime file containing the initial InvoicePlane administrator email.";
      };

      adminPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/invoiceplane-admin-password";
        description = "Runtime file containing the initial InvoicePlane administrator password.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address InvoicePlane nginx listens on.";
      };

      databaseName = mkOption {
        type = types.str;
        default = "invoiceplane";
        description = "MariaDB database used by InvoicePlane.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "invoiceplane";
        description = "MariaDB role used by InvoicePlane.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the InvoicePlane invoicing testbed service.";
      };

      encryptionKeyFile = mkOption {
        type = types.path;
        default = "/run/secrets/invoiceplane-encryption-key";
        description = "Runtime file containing the InvoicePlane encryption key.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.invoiceplane}";
        description = "Canonical external InvoicePlane URL without a trailing slash.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/invoiceplane";
        description = "Persistent InvoicePlane runtime state directory.";
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
        default = "ghcr.io/ridafkih/keeper-services@sha256:0d72423e4e60f503f791ae49aa54f2b9fbecd053e4aa6138971d8716413402af";
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

    metube = {
      downloadDir = mkOption {
        type = types.path;
        default = "/mnt/media/downloads/metube";
        description = "NAS-backed directory for completed MeTube downloads, outside the Restic appdata source.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the MeTube video downloader testbed service.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://metube.jax22.com";
        description = "Canonical external MeTube URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/alexta69/metube:2026.07.05@sha256:48c8700bccd51f828606464ad12147b76f5ce7ef1d9ed935bd933f5e8c816fe9";
        description = "Pinned MeTube OCI image.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/metube";
        description = "Persistent MeTube queue and subscription state directory.";
      };

      tempDir = mkOption {
        type = types.path;
        default = "/var/lib/metube-downloads";
        description = "Local VM directory for MeTube temporary and in-progress download files.";
      };
    };

    outline = {
      databaseName = mkOption {
        type = types.str;
        default = "outline";
        description = "PostgreSQL database used by Outline.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "outline";
        description = "PostgreSQL role used by Outline.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Outline knowledge-base testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/outline-environment";
        description = "Runtime environment file containing Outline secrets.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.outline}";
        description = "Canonical external Outline URL.";
      };

      image = mkOption {
        type = types.str;
        default = "docker.io/outlinewiki/outline@sha256:e224dcbe34670bdae8835c32d5abc692d3560dfa262b72fb7232f4d87185aebd";
        description = "Pinned Outline OCI image.";
      };

      oidc = {
        authorizationUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/authorize/";
          description = "Authentik OAuth2 authorization endpoint.";
        };

        clientId = mkOption {
          type = types.str;
          default = "outline";
          description = "Outline Authentik OIDC client identifier.";
        };

        logoutUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/outline/end-session/";
          description = "Authentik OIDC logout endpoint used by Outline.";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://outline.jax22.com/auth/oidc.callback";
          description = "Strict Outline OIDC callback URL registered in Authentik.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested by Outline.";
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
          default = "outline-uploads";
          description = "Garage S3 bucket used by Outline uploads.";
        };

        endpoint = mkOption {
          type = types.str;
          default = "https://garage.jax22.com";
          description = "Browser-reachable Garage S3 endpoint used by Outline.";
        };

        forcePathStyle = mkOption {
          type = types.bool;
          default = true;
          description = "Use path-style S3 URLs for Garage.";
        };

        region = mkOption {
          type = types.str;
          default = "garage";
          description = "Garage S3 region name used by Outline.";
        };
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/outline";
        description = "Persistent Outline runtime and Redis state directory; durable app data is PostgreSQL plus Garage S3.";
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
        default = "docker.io/makeplane/plane-backend@sha256:2cdcb5f778c6ccacebce0e5a751d39fac4a549a44e049a5b110a7623cfdad139";
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
        default = "docker.io/makeplane/plane-frontend@sha256:c178fd85c4588165262cfe748bd103fdeccebbbab827c53e71b9ce32fff84f86";
        description = "Pinned Plane frontend OCI image.";
      };

      adminImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-admin@sha256:ff9219127a2c2c4a4bb066d6a0e25a5fc6a11204cf8484b521dada53d696fe43";
        description = "Pinned Plane admin OCI image.";
      };

      liveImage = mkOption {
        type = types.str;
        default = "docker.io/makeplane/plane-live@sha256:2073b6950a394545ea1db6ed4157e951ad5a6e1881e74f4f9238ace6c35bbf3d";
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
        default = "docker.io/makeplane/plane-space@sha256:e08c2c8741ae6f81a9326dc9201e7e09c0c411b87a20198f9ea9e5cf2fae3488";
        description = "Pinned Plane Space OCI image.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/plane";
        description = "Persistent Plane state directory.";
      };
    };

    postiz = {
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address the Postiz web port is published on.";
      };

      databaseName = mkOption {
        type = types.str;
        default = "postiz";
        description = "PostgreSQL database used by Postiz.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "postiz";
        description = "PostgreSQL role used by Postiz.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Postiz social media scheduling testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/postiz/environment";
        description = "Rendered runtime environment file containing Postiz secrets.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.postiz}";
        description = "Canonical external Postiz URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/gitroomhq/postiz-app@sha256:1d5a5dc6b896747d1483c01dc2562165bd313ad601b32f6cabb7f7dd08a911a9";
        description = "Pinned Postiz OCI image.";
      };

      oidc = {
        authorizationUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/authorize/";
          description = "Authentik OAuth2 authorization endpoint.";
        };

        clientId = mkOption {
          type = types.str;
          default = "postiz";
          description = "Postiz Authentik OIDC client identifier.";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://postiz.jax22.com/settings";
          description = "Strict Postiz OIDC callback URL registered in Authentik.";
        };

        scopes = mkOption {
          type = types.listOf types.str;
          default = [
            "openid"
            "profile"
            "email"
          ];
          description = "OIDC scopes requested by Postiz.";
        };

        tokenUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/token/";
          description = "Authentik OAuth2 token endpoint.";
        };

        url = mkOption {
          type = types.str;
          default = "https://auth.jax22.com";
          description = "Base URL of the Authentik OIDC provider.";
        };

        userInfoUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/userinfo/";
          description = "Authentik OAuth2 userinfo endpoint.";
        };
      };

      postgresEnvironmentFile = mkOption {
        type = types.path;
        default = "/run/postiz/postgres-environment";
        description = "Rendered runtime environment file for the Postiz PostgreSQL container.";
      };

      postgresImage = mkOption {
        type = types.str;
        default = "docker.io/library/postgres@sha256:fe03a7605299a34ddf5e4f285dff78c3d7190a576b3c6b46f2fcff69f4bffd54";
        description = "Pinned PostgreSQL image used by Postiz.";
      };

      redisImage = mkOption {
        type = types.str;
        default = "docker.io/library/redis@sha256:e51cbc16f94b2426e80b9516db174a07d55e882217a1ec1d729b137b32e24e42";
        description = "Pinned Redis image used by Postiz.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/postiz";
        description = "Persistent Postiz state directory.";
      };

      temporal = {
        dynamicConfigDir = mkOption {
          type = types.path;
          default = "/etc/postiz/temporal/dynamicconfig";
          description = "Declarative Temporal dynamic config directory mounted read-only into the Temporal container.";
        };

        elasticsearchImage = mkOption {
          type = types.str;
          default = "docker.io/library/elasticsearch@sha256:9a6443f55243f6acbfeb4a112d15eb3b9aac74bf25e0e39fa19b3ddd3a6879d0";
          description = "Pinned Elasticsearch image used by the Postiz Temporal stack.";
        };

        image = mkOption {
          type = types.str;
          default = "docker.io/temporalio/auto-setup@sha256:607d68caa111338d754771efb876c92dfcdae06d056e4530bb31cd0f37406e6a";
          description = "Pinned Temporal auto-setup image used by Postiz.";
        };

        postgresEnvironmentFile = mkOption {
          type = types.path;
          default = "/run/postiz/temporal-postgres-environment";
          description = "Rendered runtime environment file for the Postiz Temporal PostgreSQL container.";
        };

        postgresImage = mkOption {
          type = types.str;
          default = "docker.io/library/postgres@sha256:fe03a7605299a34ddf5e4f285dff78c3d7190a576b3c6b46f2fcff69f4bffd54";
          description = "Pinned PostgreSQL image used by Postiz Temporal.";
        };

        temporalEnvironmentFile = mkOption {
          type = types.path;
          default = "/run/postiz/temporal-environment";
          description = "Rendered runtime environment file for the Postiz Temporal server.";
        };
      };
    };

    stirlingPdf = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run Stirling PDF on testbed-vm.";
      };
    };

    sure = {
      bindAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address Sure listens on.";
      };

      databaseName = mkOption {
        type = types.str;
        default = "sure";
        description = "PostgreSQL database used by Sure.";
      };

      databaseUser = mkOption {
        type = types.str;
        default = "sure";
        description = "PostgreSQL role used by Sure.";
      };

      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Run the Sure personal finance testbed service.";
      };

      environmentFile = mkOption {
        type = types.path;
        default = "/run/secrets/sure-environment";
        description = "Runtime environment file containing Sure secrets and integration settings.";
      };

      externalUrl = mkOption {
        type = types.str;
        default = "https://${cfg.serviceHosts.sure}";
        description = "Canonical external Sure URL.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/we-promise/sure@sha256:fab5de5d83f3ffc01afa47f1790b9e72938602dd0bcbe6e64b933728b09fdb40";
        description = "Pinned Sure OCI image.";
      };

      oidc = {
        clientId = mkOption {
          type = types.str;
          default = "sure";
          description = "Sure Authentik OIDC client identifier.";
        };

        issuerUrl = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/sure/";
          description = "Sure Authentik OIDC issuer URL.";
        };

        redirectUri = mkOption {
          type = types.str;
          default = "https://sure.jax22.com/auth/openid_connect/callback";
          description = "Strict Sure OIDC callback URL registered in Authentik.";
        };
      };

      postgresPasswordFile = mkOption {
        type = types.path;
        default = "/run/secrets/sure-postgres-password";
        description = "Runtime file containing the Sure PostgreSQL role password.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "${cfg.appdataRoot}/sure";
        description = "Persistent Sure state directory.";
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

      mediaDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/media";
        description = "SMB device for the NAS media share used by MeTube completed downloads.";
      };

      mediaMount = mkOption {
        type = types.path;
        default = "/mnt/media";
        description = "NAS media mount point used by MeTube completed downloads.";
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
