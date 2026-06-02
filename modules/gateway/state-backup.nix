{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  cfg = config.fleet.gateway.stateBackup;
  appdata = cfg.appDataRoot;
  mountUnit = path: "${utils.escapeSystemdPath path}.mount";
  netbirdEnabled = config.fleet.gateway.netbird.enable or false;
in
{
  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  options.fleet.gateway.stateBackup = {
    enable = mkEnableOption "gateway-vm state backups";

    backupDevice = mkOption {
      type = types.str;
      default = "//nas.home.arpa/backups";
      description = "SMB share used for gateway state backups.";
    };

    appDataRoot = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Authoritative root for gateway service state.";
    };

    credentialsFile = mkOption {
      type = types.path;
      description = "Runtime SMB credentials file.";
      example = "/run/secrets/smb-credentials";
    };

    mountPoint = mkOption {
      type = types.path;
      default = "/mnt/backup";
      description = "Mount point for gateway backup storage.";
    };

    passwordFile = mkOption {
      type = types.path;
      description = "Runtime Restic password file.";
      example = "/run/secrets/restic-password";
    };

    source = mkOption {
      type = types.path;
      default = "/srv/appsdata";
      description = "Single appdata source included in Restic backups.";
    };

    repository = mkOption {
      type = types.str;
      default = "/mnt/backup/restic/appdata/gateway-vm";
      description = "Restic repository path for gateway state.";
    };

    tag = mkOption {
      type = types.str;
      default = "appsdata";
      description = "Restic tag used for gateway appdata snapshots.";
    };

    retention = mkOption {
      type = types.str;
      default = "--keep-daily 14 --keep-weekly 8 --keep-monthly 6";
      description = "Restic forget/prune retention flags.";
    };

    restoreCheckTarget = mkOption {
      type = types.path;
      default = "/var/tmp/gateway-state-restore-check";
      description = "Non-destructive restore-check target.";
    };

    timerCalendar = mkOption {
      type = types.str;
      default = "daily";
      description = "systemd calendar for gateway state backups.";
    };
  };

  # ============================================================================
  # MODULE IMPLEMENTATION
  # ============================================================================

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.restic ];

    fileSystems."/var/lib/netbird" = {
      device = "${appdata}/netbird";
      fsType = "none";
      options = [ "bind" ];
    };

    fileSystems."/var/lib/tailscale" = {
      device = "${appdata}/tailscale";
      fsType = "none";
      options = [ "bind" ];
    };

    fileSystems."/var/lib/traefik" = {
      device = "${appdata}/traefik";
      fsType = "none";
      options = [ "bind" ];
    };

    fileSystems."/var/lib/private/technitium-dns-server" = {
      device = "${appdata}/technitium-dns-server";
      fsType = "none";
      options = [ "bind" ];
    };

    fileSystems.${cfg.mountPoint} = {
      device = cfg.backupDevice;
      fsType = "cifs";
      options = [
        "credentials=${cfg.credentialsFile}"
        "dir_mode=0700"
        "file_mode=0600"
        "gid=0"
        "iocharset=utf8"
        "nofail"
        "noauto"
        "uid=0"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
      ];
    };

    system.activationScripts.gatewayAppsdataMigration = ''
      set -euo pipefail

      migrate_gateway_state() {
        local legacy="$1"
        local target="$2"

        mkdir -p "$target"

        if [ -d "$legacy" ] && ! mountpoint -q "$legacy" && [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
          cp -aT "$legacy" "$target"
        fi

        mkdir -p "$legacy"
      }

      mkdir -p "${appdata}"
      migrate_gateway_state /var/lib/netbird "${appdata}/netbird"
      migrate_gateway_state /var/lib/tailscale "${appdata}/tailscale"
      migrate_gateway_state /var/lib/traefik "${appdata}/traefik"
      migrate_gateway_state /var/lib/private/technitium-dns-server "${appdata}/technitium-dns-server"
    '';

    systemd.tmpfiles.rules = [
      "d ${appdata} 0755 root root - -"
      "d ${appdata}/gluetun 0700 root root - -"
      "d ${appdata}/netbird 0700 root root - -"
      "d ${appdata}/tailscale 0700 root root - -"
      "d ${appdata}/technitium-dns-server 0755 root root - -"
      "d ${appdata}/traefik 0700 traefik traefik - -"
      "f ${appdata}/traefik/acme.json 0600 traefik traefik - -"
      "d ${cfg.restoreCheckTarget} 0700 root root - -"
    ];

    systemd.services.netbird = mkIf netbirdEnabled {
      after = [ (mountUnit "/var/lib/netbird") ];
      requires = [ (mountUnit "/var/lib/netbird") ];
    };

    systemd.services.tailscaled = {
      after = [ (mountUnit "/var/lib/tailscale") ];
      requires = [ (mountUnit "/var/lib/tailscale") ];
    };

    systemd.services.traefik = {
      after = [ (mountUnit "/var/lib/traefik") ];
      requires = [ (mountUnit "/var/lib/traefik") ];
    };

    systemd.services.technitium-dns-server = {
      after = [ (mountUnit "/var/lib/private/technitium-dns-server") ];
      requires = [ (mountUnit "/var/lib/private/technitium-dns-server") ];
    };

    systemd.services.gateway-state-backup = {
      description = "Back up gateway-vm /srv/appsdata";
      after = [
        "network-online.target"
        (mountUnit cfg.mountPoint)
      ];
      requires = [ (mountUnit cfg.mountPoint) ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        CacheDirectory = "restic-gateway-appsdata";
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.mountPoint}' >/dev/null; then
          echo '${cfg.mountPoint} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${cfg.passwordFile}'
        export RESTIC_REPOSITORY='${cfg.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-gateway-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host gateway-vm \
            --path '${cfg.source}' \
            --tag '${cfg.tag}' \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.source}' \
          --host gateway-vm \
          --one-file-system \
          --exclude-caches \
          --retry-lock 30m \
          --tag '${cfg.tag}'

        restic forget \
          --host gateway-vm \
          --path '${cfg.source}' \
          --prune \
          --retry-lock 30m \
          --tag '${cfg.tag}' \
          ${cfg.retention}
      '';
    };

    systemd.timers.gateway-state-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.timerCalendar;
        Persistent = true;
        Unit = "gateway-state-backup.service";
      };
    };

    systemd.services.gateway-state-restore-check = {
      description = "Validate gateway-vm /srv/appsdata Restic restore";
      after = [
        "network-online.target"
        (mountUnit cfg.mountPoint)
      ];
      requires = [ (mountUnit cfg.mountPoint) ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        CacheDirectory = "restic-gateway-appsdata";
        Type = "oneshot";
        User = "root";
      };
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.mountPoint}' >/dev/null; then
          echo '${cfg.mountPoint} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${cfg.passwordFile}'
        export RESTIC_REPOSITORY='${cfg.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-gateway-appsdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.restoreCheckTarget}'
        case "$restore_parent" in
          /tmp/*|/var/tmp/*) ;;
          *)
            echo "restore check target must be under /tmp or /var/tmp: $restore_parent"
            exit 1
            ;;
        esac

        rm -rf -- "$restore_parent"
        install -d -m 0700 -o root -g root "$restore_parent"
        restore_root="$(mktemp -d "$restore_parent/run.XXXXXX")"
        cleanup() {
          rm -rf -- "$restore_root"
        }
        trap cleanup EXIT

        restic check --retry-lock 30m
        restic restore latest \
          --host gateway-vm \
          --path '${cfg.source}' \
          --tag '${cfg.tag}' \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        for service_dir in gluetun netbird tailscale technitium-dns-server traefik; do
          if [ ! -d "$restored_source/$service_dir" ]; then
            echo "restore completed but $restored_source/$service_dir is missing"
            exit 1
          fi
        done
      '';
    };
  };
}
