#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
SNAPSHOT="${1:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"
command -v base64 >/dev/null 2>&1 || die "base64 is missing"

if [ -n "$SNAPSHOT" ] && [[ ! "$SNAPSHOT" =~ ^[[:xdigit:]]{8,64}$ ]]; then
  die "snapshot id must be 8-64 hexadecimal characters"
fi

cd "$ROOT"

remote_script="$({ cat <<'SCRIPT'
set -euo pipefail

repository=/mnt/backups/restic/appdata/testbed-vm
source_path=/srv/appsdata
tag=appsdata
requested_snapshot=__SNAPSHOT__

# shellcheck source=/dev/null
source /etc/fleet/testbed-recovery.sh

active_units=()
snapshots_file=
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "${#active_units[@]}" -gt 0 ]; then
    systemctl start --no-block "${active_units[@]}" || true
  fi
  [ -z "$snapshots_file" ] || rm -f "$snapshots_file"
  systemctl start testbed-appdata-backup.timer || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

export RESTIC_REPOSITORY="$repository"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password

systemctl stop testbed-appdata-backup.timer
for unit in "${RECOVERY_QUIESCE_UNITS[@]}"; do
  if systemctl is-active --quiet "$unit"; then
    active_units+=("$unit")
  fi
done
systemctl stop "${RECOVERY_QUIESCE_UNITS[@]}"

findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups
test -r "$RESTIC_PASSWORD_FILE" || { echo "$RESTIC_PASSWORD_FILE is not readable" >&2; exit 1; }

if [ ! -d "$repository/data" ]; then
  echo "No initialized Restic repository found; continuing as a fresh system."
  exit 0
fi

snapshots_file=$(mktemp /tmp/testbed-appdata-snapshots.XXXXXX)
restic snapshots --host testbed-vm --path "$source_path" --tag "$tag" >"$snapshots_file"
snapshot_ids=$(awk '/^[[:xdigit:]]{8}[[:space:]]/ { print $1 }' "$snapshots_file")
snapshot_count=$(printf '%s\n' "$snapshot_ids" | sed '/^$/d' | wc -l)

if [ "$snapshot_count" -eq 0 ]; then
  echo "No matching Restic snapshot found; continuing as a fresh system."
  exit 0
fi
cat "$snapshots_file"

if [ -n "$requested_snapshot" ]; then
  snapshot="$requested_snapshot"
  printf '%s\n' "$snapshot_ids" | grep -Fxq "$snapshot" || {
    echo "Requested snapshot $snapshot is not in the matching snapshot list." >&2
    exit 1
  }
elif [ "$snapshot_count" -eq 1 ]; then
  snapshot="$snapshot_ids"
else
  echo "Multiple matching snapshots exist; refusing to guess which one to restore." >&2
  exit 2
fi

restore_stamp=$(date +%Y%m%d-%H%M%S)
current_backup="/srv/appsdata.pre-restore-$snapshot-$restore_stamp"
if [ -e "$source_path" ]; then
  mv "$source_path" "$current_backup"
fi

restic restore "$snapshot" --host testbed-vm --path "$source_path" --tag "$tag" --target / --verify

chown root:root "$source_path"
chmod 0755 "$source_path"
for ownership in "${RECOVERY_OWNERSHIP[@]}"; do
  IFS='|' read -r path user group mode <<<"$ownership"
  if [ -d "$path" ]; then
    chown -R "$user:$group" "$path"
    chmod "$mode" "$path"
  fi
done
[ -d "$source_path/postgresql" ] && chown -R postgres:postgres "$source_path/postgresql"
[ -d "$source_path/postgresql-dumps" ] && chown -R postgres:postgres "$source_path/postgresql-dumps"
[ -d "$source_path/mariadb" ] && chown -R mysql:mysql "$source_path/mariadb"
[ -d "$source_path/mariadb-dumps" ] && chown -R root:root "$source_path/mariadb-dumps"
find "$source_path" -type f -name '*.pid' -delete

systemd-tmpfiles --create
for unit in "${RECOVERY_RESTART_UNITS[@]}"; do
  systemctl start "$unit"
done
systemctl start testbed-appdata-restore-check.service

trap - EXIT HUP INT TERM
rm -f "$snapshots_file"
systemctl start testbed-appdata-backup.timer
echo 'testbed-vm appdata restore flow complete.'
SCRIPT
} | sed "s/__SNAPSHOT__/${SNAPSHOT}/")"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"
colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
