{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

with lib;

let
  testbedLib = import ./lib.nix {
    inherit config lib pkgs;
  };
  inherit (testbedLib) cfg appdata resticPasswordFile;
  recoveryApplications = attrValues config.fleet.testbed.recovery.applications;
  backupGuardedServices = unique (
    concatMap (application: application.quiesceUnits) recoveryApplications
  );
  backupRestartOrder = unique (
    concatMap (application: application.restartUnits) recoveryApplications
  );
  backupDumpUnits = unique (
    concatMap (application: map (dump: dump.unit) application.databaseDumps) recoveryApplications
  );
  restoreCheckPaths = unique (
    concatMap (application: map toString application.durablePaths) recoveryApplications
  );
in
{
  config = mkIf cfg.enable {
    systemd.services.testbed-postgresql-dump = {
      description = "Dump testbed-vm PostgreSQL databases before backup";
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

    systemd.services.testbed-mariadb-dump = {
      description = "Dump testbed-vm MariaDB databases before backup";
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

    systemd.services.testbed-appdata-backup = {
      description = "Back up testbed-vm /srv/appsdata with restic";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      path = [
        pkgs.coreutils
        pkgs.restic
        pkgs.util-linux
      ];
      serviceConfig = {
        CacheDirectory = "restic-testbed-appdata";
        Type = "oneshot";
        User = "root";
        Group = "root";
        TimeoutStopSec = "10min";
      };
      script = ''
        set -euo pipefail

        active_services=
        cleanup() {
          status=$?
          trap - EXIT HUP INT TERM

          restart_services=
          queue_restart() {
            case " $active_services " in
              *" $1 "*) restart_services="$restart_services $1" ;;
            esac
          }

          for service in ${concatStringsSep " " backupRestartOrder}; do
            queue_restart "$service"
          done
          if [ -n "$restart_services" ]; then
            systemctl reset-failed $restart_services || true
            systemctl start --no-block $restart_services || true
          fi
          exit "$status"
        }
        trap cleanup EXIT
        trap 'exit 129' HUP
        trap 'exit 130' INT
        trap 'exit 143' TERM

        stop_pending=
        for service in ${concatStringsSep " " backupGuardedServices}; do
          if systemctl is-active --quiet "$service"; then
            active_services="$active_services $service"
            stop_pending="$stop_pending $service"
            systemctl stop --no-block "$service"
          fi
        done

        for dump_unit in ${concatStringsSep " " backupDumpUnits}; do
          systemctl start "$dump_unit"
        done

        for service in $stop_pending; do
          for attempt in $(seq 1 60); do
            if ! systemctl is-active --quiet "$service"; then
              break
            fi
            sleep 1
          done
          if systemctl is-active --quiet "$service"; then
            echo "$service did not stop within 60 seconds; refusing to run backup"
            exit 1
          fi
        done

        if ! findmnt -rn --target '${cfg.smb.backupMount}' >/dev/null; then
          echo '${cfg.smb.backupMount} is not mounted; refusing to run backup'
          exit 1
        fi

        export RESTIC_PASSWORD_FILE='${resticPasswordFile}'
        export RESTIC_REPOSITORY='${cfg.backup.repository}'
        export RESTIC_CACHE_DIR=/var/cache/restic-testbed-appdata

        if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
          echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup"
          exit 1
        fi

        mkdir -p "$RESTIC_REPOSITORY"
        if [ ! -e "$RESTIC_REPOSITORY/config" ]; then
          restic init
        else
          restic snapshots \
            --host testbed-vm \
            --path '${cfg.backup.source}' \
            --tag appsdata \
            --latest 1 \
            --retry-lock 30m \
            >/dev/null
        fi

        restic backup '${cfg.backup.source}' \
          --host testbed-vm \
          --one-file-system \
          --exclude-caches \
          --retry-lock 30m \
          --tag appsdata
        restic forget \
          --host testbed-vm \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --path '${cfg.backup.source}' \
          --prune \
          --retry-lock 30m \
          --tag appsdata

      '';
    };

    systemd.services.testbed-appdata-restore-check = {
      description = "Verify testbed-vm /srv/appsdata can be restored from restic";
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
        CacheDirectory = "restic-testbed-appdata";
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
        export RESTIC_CACHE_DIR=/var/cache/restic-testbed-appdata

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
          --host testbed-vm \
          --path '${cfg.backup.source}' \
          --tag appsdata \
          --target "$restore_root" \
          --verify \
          --retry-lock 30m

        test -d "$restore_root${cfg.backup.source}"
        for durable_path in ${escapeShellArgs restoreCheckPaths}; do
          test -d "$restore_root$durable_path"
        done
      '';
    };

    systemd.timers.testbed-appdata-backup = {
      description = "Nightly testbed-vm appdata backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "03:30";
        Persistent = true;
        RandomizedDelaySec = "30m";
        Unit = "testbed-appdata-backup.service";
      };
    };
  };
}
