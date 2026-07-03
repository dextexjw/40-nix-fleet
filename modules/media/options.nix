{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.media.stack;
  mediaGluetunControlApiKeyFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-control-api-key.path
    else
      "/run/secrets/media-gluetun-control-api-key";
  mediaGluetunOpenvpnPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-openvpn-password.path
    else
      "/run/secrets/media-gluetun-openvpn-password";
  mediaGluetunOpenvpnUsernameFile =
    if cfg.secrets.enable then
      config.sops.secrets.media-gluetun-openvpn-username.path
    else
      "/run/secrets/media-gluetun-openvpn-username";
  bookorbitEmailEncryptionKeyFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-email-encryption-key.path
    else
      "/run/secrets/bookorbit-email-encryption-key";
  bookorbitAdminPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-admin-password.path
    else
      "/run/secrets/bookorbit-admin-password";
  bookorbitAdminUsernameFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-admin-username.path
    else
      "/run/secrets/bookorbit-admin-username";
  bookorbitJwtSecretFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-jwt-secret.path
    else
      "/run/secrets/bookorbit-jwt-secret";
  bookorbitMigrationEncryptionKeyFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-migration-encryption-key.path
    else
      "/run/secrets/bookorbit-migration-encryption-key";
  bookorbitPostgresPasswordFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-postgres-password.path
    else
      "/run/secrets/bookorbit-postgres-password";
  bookorbitSetupBootstrapTokenFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-setup-bootstrap-token.path
    else
      "/run/secrets/bookorbit-setup-bootstrap-token";
  bookorbitOidcClientSecretFile =
    if cfg.secrets.enable then
      config.sops.secrets.bookorbit-oidc-client-secret.path
    else
      "/run/secrets/bookorbit-oidc-client-secret";
in
{
  options.fleet.media.stack = {
    enable = mkEnableOption "media-vm Jellyfin and ARR stack";

    appdataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single restore-critical application data root.";
    };

    mediaRoot = mkOption {
      type = types.path;
      default = "/mnt/media";
      description = "Mounted media library root.";
    };

    secrets.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Use sops-nix secrets from secrets/secrets.yaml.";
    };

    serviceDomain = mkOption {
      type = types.str;
      default = "h";
      description = "Legacy single internal service domain used for generated route hostnames.";
    };

    serviceDomains = mkOption {
      type = types.nonEmptyListOf types.str;
      default = [ cfg.serviceDomain ];
      description = "Internal service domains used for generated route hostnames, in canonical-first order.";
    };

    libraries = mkOption {
      type = types.attrsOf types.path;
      default = {
        audiobooks = "/mnt/media/Audiobooks";
        books = "/mnt/media/Books";
        calibre = "/mnt/media/Books";
        comics = "/mnt/media/Comics";
        kidsMovies = "/mnt/media/KidsMedia/KidsMovies";
        kidsTv = "/mnt/media/KidsMedia/KidsTVshows";
        movies = "/mnt/media/MOVIES";
        newMovies = "/mnt/media/NewMovies";
        pdfs = "/mnt/media/PDFs";
        podcasts = "/mnt/media/Podcasts";
        tv = "/mnt/media/TVshows";
      };
      description = "Media library paths.";
    };

    downloads = mkOption {
      type = types.attrsOf types.path;
      default = {
        incomplete = "/var/lib/media-downloads";
        root = "/mnt/media/downloads";
        torrents = "/mnt/media/downloads";
        usenet = "/mnt/media/downloads";
      };
      description = "Download paths for torrent and Usenet clients.";
    };

    ports = mkOption {
      type = types.attrsOf types.port;
      default = {
        audiobookshelf = 8000;
        bazarr = 6767;
        bookorbit = 3000;
        jellyfin = 8096;
        kavita = 5000;
        prowlarr = 9696;
        qbittorrent = 8080;
        radarr = 7878;
        sabnzbd = 8085;
        seerr = 5055;
        sonarr = 8989;
      };
      description = "Web UI ports for exposed media services.";
    };

    jellyfin.publishedServerUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional URL Jellyfin advertises to clients during auto-discovery.";
    };

    bookorbit = {
      admin = {
        email = mkOption {
          type = types.str;
          default = "coldkey@jax22.com";
          description = "BookOrbit declarative local superuser email address.";
        };

        name = mkOption {
          type = types.str;
          default = "coldkey";
          description = "BookOrbit declarative local superuser display name.";
        };

        passwordFile = mkOption {
          type = types.path;
          default = bookorbitAdminPasswordFile;
          description = "Runtime secret file containing the BookOrbit local superuser password.";
        };

        usernameFile = mkOption {
          type = types.path;
          default = bookorbitAdminUsernameFile;
          description = "Runtime secret file containing the BookOrbit local superuser username.";
        };
      };

      emailEncryptionKeyFile = mkOption {
        type = types.path;
        default = bookorbitEmailEncryptionKeyFile;
        description = "Runtime secret file containing BookOrbit EMAIL_ENCRYPTION_KEY.";
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/bookorbit/bookorbit@sha256:70bef7bef8b0d0fa938c980b5a128f86bbde656cde04f4ab0549b9b91ebb2e14";
        description = "Pinned BookOrbit OCI image reference.";
      };

      jwtSecretFile = mkOption {
        type = types.path;
        default = bookorbitJwtSecretFile;
        description = "Runtime secret file containing BookOrbit JWT_SECRET.";
      };

      migrationEncryptionKeyFile = mkOption {
        type = types.path;
        default = bookorbitMigrationEncryptionKeyFile;
        description = "Runtime secret file containing BookOrbit MIGRATION_ENCRYPTION_KEY.";
      };

      postgresPasswordFile = mkOption {
        type = types.path;
        default = bookorbitPostgresPasswordFile;
        description = "Runtime secret file containing the BookOrbit PostgreSQL role password.";
      };

      setupBootstrapTokenFile = mkOption {
        type = types.path;
        default = bookorbitSetupBootstrapTokenFile;
        description = "Runtime secret file containing BookOrbit SETUP_BOOTSTRAP_TOKEN.";
      };

      oidc = {
        allowLocalLinking = mkOption {
          type = types.bool;
          default = true;
          description = "Allow BookOrbit OIDC logins to link to existing local accounts.";
        };

        autoProvision = mkOption {
          type = types.bool;
          default = true;
          description = "Allow BookOrbit to auto-provision users from OIDC claims.";
        };

        claimMapping = mkOption {
          type = types.attrsOf types.str;
          default = {
            email = "email";
            groups = "groups";
            name = "name";
            username = "preferred_username";
          };
          description = "BookOrbit OIDC claim mapping.";
        };

        clientId = mkOption {
          type = types.str;
          default = "bookorbit";
          description = "BookOrbit Authentik OIDC client ID.";
        };

        clientSecretFile = mkOption {
          type = types.path;
          default = bookorbitOidcClientSecretFile;
          description = "Runtime secret file containing the BookOrbit OIDC client secret.";
        };

        defaultPermissionNames = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "BookOrbit permissions granted to newly auto-provisioned OIDC users.";
        };

        displayName = mkOption {
          type = types.str;
          default = "Authentik";
          description = "BookOrbit OIDC provider display name.";
        };

        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Configure BookOrbit's in-app Authentik OIDC provider declaratively.";
        };

        issuerUri = mkOption {
          type = types.str;
          default = "https://auth.jax22.com/application/o/bookorbit/";
          description = "BookOrbit Authentik OIDC issuer URI.";
        };

        scopes = mkOption {
          type = types.nonEmptyListOf types.str;
          default = [
            "openid"
            "profile"
            "email"
            "groups"
          ];
          description = "BookOrbit OIDC scopes.";
        };

        slug = mkOption {
          type = types.str;
          default = "authentik";
          description = "BookOrbit OIDC provider slug.";
        };
      };
    };

    qbittorrent.image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/qbittorrent@sha256:163f3384db6cba9f68eaa83ca5f4209298b6029ba2d07b5e67562d0715baf5b9";
      description = "Pinned qBittorrent OCI image reference.";
    };

    sabnzbd.image = mkOption {
      type = types.str;
      default = "lscr.io/linuxserver/sabnzbd@sha256:30cc2eb9e1c8b7c5bb90dbf3c7abb0e66643c21c3710e273a82d2f36239e176d";
      description = "Pinned SABnzbd OCI image reference.";
    };

    gluetun = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Route MediaVM download clients through a dedicated Gluetun container.";
      };

      bindAddress = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Host address used for MediaVM Gluetun-published service ports.";
      };

      controlServer = {
        apiKeyFile = mkOption {
          type = types.path;
          default = mediaGluetunControlApiKeyFile;
          description = "Runtime secret file containing the MediaVM Gluetun control server API key.";
        };

        port = mkOption {
          type = types.port;
          default = 8000;
          description = "Container-only Gluetun HTTP control server port.";
        };
      };

      image = mkOption {
        type = types.str;
        default = "ghcr.io/qdm12/gluetun@sha256:2f33c71e5e164fcd51a962cb950134df25155593edf0c3e1201f888d027049b4";
        description = "Pinned Gluetun OCI image reference.";
      };

      openvpnPasswordFile = mkOption {
        type = types.path;
        default = mediaGluetunOpenvpnPasswordFile;
        description = "Runtime secret file containing the MediaVM PIA OpenVPN password.";
      };

      openvpnUsernameFile = mkOption {
        type = types.path;
        default = mediaGluetunOpenvpnUsernameFile;
        description = "Runtime secret file containing the MediaVM PIA OpenVPN username.";
      };

      provider = mkOption {
        type = types.str;
        default = "private internet access";
        description = "Gluetun VPN service provider name.";
      };

      qbittorrentWebUi.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Publish qBittorrent WebUI through the MediaVM Gluetun container.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "/srv/appsdata/gluetun";
        description = "Persistent MediaVM Gluetun state directory.";
      };

      vpnPortForwarding = mkOption {
        type = types.bool;
        default = false;
        description = "Enable PIA VPN port forwarding.";
      };

      vpnType = mkOption {
        type = types.enum [ "openvpn" ];
        default = "openvpn";
        description = "Gluetun VPN protocol.";
      };

      webUi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Run the MediaVM Gluetun WebUI sidecar container.";
        };

        image = mkOption {
          type = types.str;
          default = "docker.io/scuzza/gluetun-webui@sha256:7f38c188ada9b21b585dcb28175c3d74e64c12d959bd979b7f106e4240f6c807";
          description = "Pinned Gluetun WebUI OCI image reference.";
        };

        name = mkOption {
          type = types.str;
          default = "MediaVM Gluetun";
          description = "Display name for the MediaVM Gluetun instance.";
        };

        port = mkOption {
          type = types.port;
          default = 3001;
          description = "Host and container port for the MediaVM Gluetun WebUI.";
        };

        trustProxy = mkOption {
          type = types.bool;
          default = false;
          description = "Allow Gluetun WebUI to trust reverse proxy forwarding headers.";
        };
      };
    };

    smb = {
      mediaDevice = mkOption {
        type = types.str;
        default = "//nas.home.arpa/media";
        description = "SMB device for the media share.";
      };

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
        default = "/mnt/backups/restic/appdata/media-stack-vm";
        description = "Restic repository path.";
      };

      source = mkOption {
        type = types.path;
        default = "/srv/appsdata";
        description = "Path backed up by appsdata-backup.service.";
      };

      restoreCheckTarget = mkOption {
        type = types.path;
        default = "/var/tmp/appsdata-restore-check";
        description = "Temporary target used by appsdata-restore-check.service.";
      };
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================
}
