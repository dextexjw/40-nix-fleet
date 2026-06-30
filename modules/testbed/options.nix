{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.testbed.stack;
  serviceHostPrefixes = {
    fizzy = "fizzy";
    listmonk = "listmonk";
    mailpit = "mailpit";
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
        listmonk = 9000;
        mailpit = 8025;
        mailpitSmtp = 1025;
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
        description = "Address Mailpit UI/API listens on. SMTP remains loopback-only.";
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
