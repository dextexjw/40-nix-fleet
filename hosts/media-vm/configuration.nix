{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ../../hosts.nix;
  host = hosts.media-vm;
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
    ../../modules/media
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================

  fleet.host.name = "media-vm";
  users.motd = "media-vm: Jellyfin, Audiobookshelf, Kavita, BookOrbit, ARR stack, downloads, and appdata backups";

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
      bookorbit-email-encryption-key = {
        owner = "bookorbit";
        group = "media";
        mode = "0400";
        restartUnits = [ "podman-media-bookorbit.service" ];
      };
      bookorbit-jwt-secret = {
        owner = "bookorbit";
        group = "media";
        mode = "0400";
        restartUnits = [ "podman-media-bookorbit.service" ];
      };
      bookorbit-migration-encryption-key = {
        owner = "bookorbit";
        group = "media";
        mode = "0400";
        restartUnits = [ "podman-media-bookorbit.service" ];
      };
      bookorbit-postgres-password = {
        owner = "postgres";
        group = "media";
        mode = "0440";
        restartUnits = [
          "bookorbit-postgresql-password.service"
          "podman-media-bookorbit.service"
        ];
      };
      bookorbit-setup-bootstrap-token = {
        owner = "bookorbit";
        group = "media";
        mode = "0400";
        restartUnits = [ "podman-media-bookorbit.service" ];
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
    bookorbit = {
      emailEncryptionKeyFile =
        if secretsEnabled then
          config.sops.secrets.bookorbit-email-encryption-key.path
        else
          "/run/secrets/bookorbit-email-encryption-key";
      jwtSecretFile =
        if secretsEnabled then
          config.sops.secrets.bookorbit-jwt-secret.path
        else
          "/run/secrets/bookorbit-jwt-secret";
      migrationEncryptionKeyFile =
        if secretsEnabled then
          config.sops.secrets.bookorbit-migration-encryption-key.path
        else
          "/run/secrets/bookorbit-migration-encryption-key";
      postgresPasswordFile =
        if secretsEnabled then
          config.sops.secrets.bookorbit-postgres-password.path
        else
          "/run/secrets/bookorbit-postgres-password";
      setupBootstrapTokenFile =
        if secretsEnabled then
          config.sops.secrets.bookorbit-setup-bootstrap-token.path
        else
          "/run/secrets/bookorbit-setup-bootstrap-token";
    };
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
    inherit serviceDomains;
  };

}
