{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.productivity-vm;
  serviceDomains = (import ../../lib/service-domains.nix).all;
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

  networking.hostName = "productivity-vm";
  networking.domain = host.domain;
  users.motd = "productivity-vm: Git, docs, paperless, RSS, search, vault, files, S3, notifications, and appdata backups";

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
      firefly-app-key = {
        owner = "firefly-iii";
        group = "nginx";
        mode = "0400";
        restartUnits = [ "phpfpm-firefly-iii.service" ];
      };
      freshrss-admin-password = {
        owner = "freshrss";
        group = "freshrss";
        mode = "0400";
        restartUnits = [ "freshrss-config.service" ];
      };
      garage-admin-token = {
        owner = "garage";
        group = "garage";
        mode = "0400";
        restartUnits = [ "garage.service" ];
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
      nextcloud-admin-password = {
        restartUnits = [ "nextcloud-setup.service" ];
      };
      paperless-admin-password = {
        restartUnits = [ "paperless-scheduler.service" ];
      };
      restic-password = {
        restartUnits = [ "productivity-appdata-backup.service" ];
      };
      rustfs-environment = {
        restartUnits = [ "podman-rustfs.service" ];
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
      vaultwarden-environment = {
        restartUnits = [ "vaultwarden.service" ];
      };
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
  # SERVICES
  # ============================================================================

  fleet.productivity.stack = {
    enable = true;
    secrets.enable = secretsEnabled;
    inherit serviceDomains;
    smb.backupDevice = "//nas.home.arpa/backups";
  };

  # ============================================================================
  # NETWORKING & FIREWALL
  # ============================================================================

  networking.networkmanager.enable = lib.mkForce false;
  networking.useDHCP = lib.mkForce false;
  systemd.network = {
    enable = true;
    networks."10-lan" = {
      matchConfig.Name = [
        "en*"
        "eth*"
      ];
      networkConfig = {
        Address = "${host.ip}/24";
        DNS = host.nameservers;
        Domains = host.domain;
        Gateway = host.gateway;
      };
    };
  };

  # ============================================================================
  # BOOTLOADER
  # ============================================================================

  boot.loader.grub.enable = true;
  boot.loader.grub.device = host.vm.disk;
  boot.loader.grub.useOSProber = true;

  # ============================================================================
  # SYSTEM
  # ============================================================================

  time.timeZone = host.timezone;
  system.stateVersion = "25.11";
}
