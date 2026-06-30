{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.fleet.testbed.stack;
  serviceHostPrefixes = {
    listmonk = "listmonk";
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
        listmonk = 9000;
        mailhog = 8025;
        mailhogSmtp = 1025;
      };
      description = "LAN-facing or local testbed service ports.";
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
