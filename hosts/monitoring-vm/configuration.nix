{
  config,
  lib,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.monitoring-vm;
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
    ../../modules/monitoring/stack.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "monitoring-vm";
  networking.domain = host.domain;
  users.motd = "monitoring-vm: Checkmate, Beszel, host agents, and appdata backups";

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
      checkmate-environment = {
        restartUnits = [ "podman-checkmate.service" ];
      };
      restic-password = {
        restartUnits = [ "monitoring-appdata-backup.service" ];
      };
      smb-credentials = { };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "monitoring"
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.monitoring.stack = {
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
        Domains = [
          host.domain
          "~${host.domain}"
        ];
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
