{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  productivityLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (productivityLib) cfg appdata resticPasswordFile;
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.restic
      pkgs.garage
      config.services.mysql.package
      config.services.paperless.manage
    ];

    systemd.services.productivity-mariadb-dump = {
      description = "Dump productivity-vm MariaDB databases before backup";
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
      path = [
        pkgs.coreutils
        pkgs.gzip
        config.services.mysql.package
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        install -d -m 0700 -o root -g root '${appdata}/mariadb-dumps'
        tmp="$(mktemp '${appdata}/mariadb-dumps/.dump.XXXXXX.sql.gz')"
        trap 'rm -f "$tmp"' EXIT

        mariadb-dump --protocol=socket --all-databases --single-transaction --quick | gzip -9 > "$tmp"
        chmod 0600 "$tmp"
        mv "$tmp" '${appdata}/mariadb-dumps/latest.sql.gz'
        trap - EXIT
      '';
    };

    systemd.services.productivity-postgresql-dump = {
      description = "Dump productivity-vm PostgreSQL databases before backup";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      path = [
        pkgs.coreutils
        pkgs.gzip
        config.services.postgresql.package
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
      };
      script = ''
        set -euo pipefail

        install -d -m 0700 -o postgres -g postgres '${appdata}/postgresql-dumps'
        tmp="$(mktemp '${appdata}/postgresql-dumps/.dump.XXXXXX.sql.gz')"
        trap 'rm -f "$tmp"' EXIT

        pg_dumpall --clean --if-exists | gzip -9 > "$tmp"
        chmod 0600 "$tmp"
        mv "$tmp" '${appdata}/postgresql-dumps/latest.sql.gz'
        trap - EXIT
      '';
    };

    systemd.services.productivity-appdata-backup = {
      description = "Back up productivity-vm /srv/appsdata with restic";
      after = [
        "network-online.target"
        "productivity-mariadb-dump.service"
        "productivity-postgresql-dump.service"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [
        "network-online.target"
        "productivity-mariadb-dump.service"
        "productivity-postgresql-dump.service"
      ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-productivity-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-productivity-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host productivity-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host productivity-vm \
          --one-file-system \
          --exclude-caches \
          --exclude '${appdata}/nextcloud/data/*/files_trashbin' \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host productivity-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata
      '';
    };

    systemd.services.productivity-appdata-restore-check = {
      description = "Verify productivity-vm /srv/appsdata can be restored from restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-productivity-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run restore check'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-productivity-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run restore check"
          exit 1
        fi

        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          echo "$RESTIC_REPOSITORY is not an initialized restic repository"
          exit 1
        fi

        restore_parent='${cfg.backup.restoreCheckTarget}'
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
          --host productivity-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        restored_source="$restore_root${cfg.backup.source}"
        if [ ! -d "$restored_source" ]; then
          echo "restore completed but $restored_source is missing"
          exit 1
        fi

        first_entry="$(find "$restored_source" -mindepth 1 -maxdepth 1 -print -quit)"
        if [ -z "$first_entry" ]; then
          echo "restore completed but $restored_source is empty"
          exit 1
        fi
      '';
    };

    systemd.timers.productivity-appdata-backup = {
      description = "Daily productivity-vm /srv/appsdata restic backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "productivity-appdata-backup.service";
      };
    };
  };
}
