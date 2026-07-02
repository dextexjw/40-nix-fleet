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
  inherit (productivityLib)
    cfg
    appdata
    memosGid
    memosUid
    resticPasswordFile
    ;
  launcherCfg = cfg.onDemandLauncher;
  onDemandBundles = mapAttrsToList (id: bundle: {
    inherit id;
    inherit (bundle) startUnits statusUnits;
  }) launcherCfg.bundles;
  onDemandStopUnits = unique (concatMap (bundle: bundle.stopUnits) (attrValues launcherCfg.bundles));
  onDemandStateCommands = concatStringsSep "\n" (
    map (
      bundle:
      let
        statusCheck = concatStringsSep " || " (
          map (unit: "systemctl is-active --quiet ${escapeShellArg unit}") bundle.statusUnits
        );
      in
      ''
        if ${if statusCheck == "" then "false" else statusCheck}; then
          printf '%s\n' ${escapeShellArg bundle.id} >> "$state_file"
        fi
      ''
    ) onDemandBundles
  );
  onDemandStopCommands = concatStringsSep "\n" (
    map (unit: "systemctl stop ${escapeShellArg unit} || true") onDemandStopUnits
  );
  onDemandResumeCases = concatStringsSep "\n" (
    map (bundle: ''
      ${bundle.id})
        ${concatStringsSep "\n          " (
          map (unit: "systemctl start ${escapeShellArg unit} || true") bundle.startUnits
        )}
        ;;
    '') onDemandBundles
  );
in
{
  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.restic
      pkgs.garage
      pkgs.sqlite
      config.services.paperless.manage
    ];

    systemd.services.productivity-memos-sqlite-backup = {
      description = "Create a consistent Memos SQLite backup before appdata backup";
      after = [ "podman-memos.service" ];
      path = [
        pkgs.coreutils
        pkgs.sqlite
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
        set -euo pipefail

        db='${appdata}/memos/memos_prod.db'
        backup_dir='${appdata}/memos-backups'

        install -d -m 0750 -o ${toString memosUid} -g ${toString memosGid} "$backup_dir"

        if [ ! -s "$db" ]; then
          echo "$db does not exist yet; skipping Memos SQLite backup"
          exit 0
        fi

        tmp="$(mktemp "$backup_dir/.latest.XXXXXX.db")"
        trap 'rm -f "$tmp"' EXIT

        sqlite3 "$db" ".backup '$tmp'"
        chown ${toString memosUid}:${toString memosGid} "$tmp"
        chmod 0640 "$tmp"
        mv "$tmp" "$backup_dir/latest.db"
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

    systemd.services.productivity-consistency-backup = {
      description = "Run productivity-vm backup with on-demand apps quiesced";
      after = [
        "network-online.target"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [ "network-online.target" ];
      requires = [ "${utils.escapeSystemdPath cfg.smb.backupMount}.mount" ];
      path = [
        pkgs.coreutils
        pkgs.systemd
        pkgs.util-linux
      ];
      serviceConfig = {
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

        lock_path='${toString launcherCfg.maintenanceLock}'
        lock_dir="$(dirname "$lock_path")"
        state_file="$lock_dir/backup-on-demand-apps"

        install -d -m 0755 -o root -g root "$lock_dir"
        : > "$state_file"
        chmod 0600 "$state_file"
        printf '%s\n' 'consistency-first backup is running' > "$lock_path"

        resume_on_demand_apps() {
          set +e
          if [ -s "$state_file" ]; then
            while IFS= read -r app; do
              case "$app" in
                ${onDemandResumeCases}
              esac
            done < "$state_file"
          fi
          rm -f -- "$state_file" "$lock_path"
        }
        trap resume_on_demand_apps EXIT

        ${onDemandStateCommands}

        ${onDemandStopCommands}

        systemctl start productivity-postgresql-dump.service
        systemctl start productivity-memos-sqlite-backup.service
        systemctl start productivity-appdata-backup.service
      '';
    };

    systemd.services.productivity-appdata-backup = {
      description = "Back up productivity-vm /srv/appsdata with restic";
      after = [
        "network-online.target"
        "productivity-memos-sqlite-backup.service"
        "productivity-postgresql-dump.service"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
      wants = [
        "network-online.target"
        "productivity-memos-sqlite-backup.service"
        "productivity-postgresql-dump.service"
      ];
      requires = [
        "productivity-memos-sqlite-backup.service"
        "productivity-postgresql-dump.service"
        "${utils.escapeSystemdPath cfg.smb.backupMount}.mount"
      ];
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
        Unit = "productivity-consistency-backup.service";
      };
    };
  };
}
