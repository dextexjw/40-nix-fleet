{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.media-vm;
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
    ../../modules/media/stack.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  networking.hostName = "media-vm";
  networking.domain = host.domain;
  users.motd = "media-vm: Jellyfin, Audiobookshelf, Kavita, ARR stack, downloads, and appdata backups";

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
      media-gluetun-control-api-key.restartUnits = [
        "media-gluetun-control-auth-config.service"
        "podman-media-gluetun.service"
        "podman-media-gluetun-webui.service"
      ];
      media-gluetun-openvpn-password.restartUnits = [ "podman-media-gluetun.service" ];
      media-gluetun-openvpn-username.restartUnits = [ "podman-media-gluetun.service" ];
      qbittorrent-webui-password.restartUnits = [ "podman-media-qbittorrent.service" ];
      qbittorrent-webui-username.restartUnits = [ "podman-media-qbittorrent.service" ];
      restic-password = { };
      smb-credentials = { };
    };
  };

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  users.users.${host.user} = {
    extraGroups = [
      "media"
      "systemd-journal"
    ];
    hashedPasswordFile = lib.mkIf secretsEnabled config.sops.secrets.admin-password-hash.path;
  };

  # ============================================================================
  # SERVICES
  # ============================================================================

  fleet.media.stack = {
    enable = true;
    gluetun = {
      controlServer.apiKeyFile =
        if secretsEnabled then
          config.sops.secrets.media-gluetun-control-api-key.path
        else
          "/run/secrets/media-gluetun-control-api-key";
      openvpnPasswordFile =
        if secretsEnabled then
          config.sops.secrets.media-gluetun-openvpn-password.path
        else
          "/run/secrets/media-gluetun-openvpn-password";
      openvpnUsernameFile =
        if secretsEnabled then
          config.sops.secrets.media-gluetun-openvpn-username.path
        else
          "/run/secrets/media-gluetun-openvpn-username";
    };
    jellyfin.publishedServerUrl = "http://${host.ip}:8096";
    secrets.enable = secretsEnabled;
    smb = {
      backupDevice = "//nas.home.arpa/backups";
      mediaDevice = "//nas.home.arpa/media";
    };
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
