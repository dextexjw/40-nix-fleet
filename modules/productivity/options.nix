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
    firefly = "firefly";
    forgejo = "forgejo";
    freshrss = "freshrss";
    garage = "garage";
    garageWeb = "garage-web";
    gitea = "gitea";
    invoiceplane = "invoiceplane";
    iperf3 = "iperf3";
    memos = "memos";
    nextcloud = "nextcloud";
    ntfy = "ntfy";
    openspeedtest = "openspeedtest";
    paperless = "paperless";
    privatebin = "privatebin";
    rustdesk = "rustdesk";
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
    "openspeedtest"
    "invoiceplane"
    "iperf3"
    "memos"
    "rustdesk"
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
        iperf3 = 5201;
        memos = 5230;
        ntfy = 2586;
        openspeedtest = 8989;
        rustdeskRelay = 21117;
        rustdeskSignal = 21116;
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

}
