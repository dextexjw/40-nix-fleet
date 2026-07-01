#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
REPOSITORY="/mnt/backups/restic/appdata/testbed-vm"
SOURCE="/srv/appsdata"
TAG="appsdata"
SNAPSHOT="${1:-}"
SERVICES="podman-fizzy homebox podman-kaneo podman-keeper listmonk mailpit-testbed redis-keeper postgresql"

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

remote_script="$(
  cat <<SCRIPT
set -euo pipefail

repository='${REPOSITORY}'
source_path='${SOURCE}'
tag='${TAG}'
services='${SERVICES}'
requested_snapshot='${SNAPSHOT}'

export RESTIC_REPOSITORY="\$repository"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password

echo 'Stopping testbed services before appdata restore...'
systemctl stop testbed-appdata-backup.timer kaneo-postgresql-password.service listmonk-oidc-config.service \$services || true

echo 'Mounting /mnt/backups...'
findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups

if [ ! -r "\$RESTIC_PASSWORD_FILE" ]; then
  echo "\$RESTIC_PASSWORD_FILE is not readable; cannot inspect or restore appdata" >&2
  systemctl start \$services
  systemctl start testbed-appdata-backup.timer
  exit 1
fi

if [ ! -d "\$repository/data" ]; then
  echo "No initialized Restic repository found at \$repository; continuing as a fresh system."
  systemctl start \$services
  systemctl start testbed-appdata-backup.timer
  exit 0
fi

if ! restic snapshots --host '${HOST}' --path "\$source_path" --tag "\$tag" >/tmp/testbed-appdata-snapshots.txt; then
  echo 'Unable to inspect Restic snapshots; leaving testbed services stopped for investigation.' >&2
  cat /tmp/testbed-appdata-snapshots.txt >&2 || true
  exit 1
fi

snapshot_ids="\$(awk '/^[[:xdigit:]]{8}[[:space:]]/ { print \$1 }' /tmp/testbed-appdata-snapshots.txt)"
snapshot_count="\$(printf '%s\n' "\$snapshot_ids" | sed '/^$/d' | wc -l)"

if [ "\$snapshot_count" -eq 0 ]; then
  echo "No matching Restic snapshot found for host=${HOST}, path=\$source_path, tag=\$tag; continuing as a fresh system."
  systemctl start \$services
  systemctl start testbed-appdata-backup.timer
  exit 0
fi

cat /tmp/testbed-appdata-snapshots.txt

if [ -n "\$requested_snapshot" ]; then
  snapshot="\$requested_snapshot"
  if ! printf '%s\n' "\$snapshot_ids" | grep -Fxq "\$snapshot"; then
    echo "Requested snapshot \$snapshot is not in the matching snapshot list above; leaving testbed services stopped for investigation." >&2
    exit 1
  fi
elif [ "\$snapshot_count" -eq 1 ]; then
  snapshot="\$snapshot_ids"
else
  echo "Multiple matching snapshots exist; refusing to guess which one to restore." >&2
  echo "Rerun with an explicit snapshot ID, for example: scripts/testbed-vm/restore-testbed-appdata.sh \$(printf '%s\n' "\$snapshot_ids" | tail -n 1)" >&2
  systemctl start \$services
  systemctl start testbed-appdata-backup.timer
  exit 2
fi

restore_stamp="\$(date +%Y%m%d-%H%M%S)"
current_backup="/srv/appsdata.pre-restore-\$snapshot-\$restore_stamp"
if [ -e "\$source_path" ]; then
  echo "Moving existing \$source_path to \$current_backup before restore..."
  mv "\$source_path" "\$current_backup"
fi

echo "Restoring appdata snapshot \$snapshot to /..."
restic restore "\$snapshot" \
  --host '${HOST}' \
  --path "\$source_path" \
  --tag "\$tag" \
  --target / \
  --verify

echo 'Normalizing restored ownership for rebuilt host users...'
chown root:root "\$source_path"
chmod 0755 "\$source_path"
[ -d "\$source_path/listmonk" ] && chown -R listmonk:listmonk "\$source_path/listmonk"
[ -d "\$source_path/homebox" ] && chown -R homebox:homebox "\$source_path/homebox"
[ -d "\$source_path/fizzy" ] && chown -R 1000:1000 "\$source_path/fizzy"
[ -d "\$source_path/kaneo" ] && chown -R root:testbed "\$source_path/kaneo"
[ -d "\$source_path/keeper" ] && chown -R root:root "\$source_path/keeper"
[ -d "\$source_path/keeper/redis" ] && chown -R redis-keeper:redis-keeper "\$source_path/keeper/redis"
[ -d "\$source_path/postgresql" ] && chown -R postgres:postgres "\$source_path/postgresql"
[ -d "\$source_path/postgresql-dumps" ] && chown -R postgres:postgres "\$source_path/postgresql-dumps"
find "\$source_path" -type f -name '*.pid' -delete

echo 'Reapplying declared directories and restarting testbed services...'
systemd-tmpfiles --create
systemctl start postgresql
systemctl start redis-keeper
systemctl start kaneo-postgresql-password
systemctl start keeper-postgresql-password
systemctl start mailpit-testbed listmonk homebox podman-kaneo podman-keeper podman-fizzy
systemctl start listmonk-oidc-config.service
systemctl start testbed-appdata-backup.timer
systemctl start testbed-appdata-restore-check.service

echo 'testbed-vm appdata restore flow complete.'
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
