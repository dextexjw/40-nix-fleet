#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
TAG="appsdata"
SNAPSHOT="${1:-}"
SERVICES="gitea forgejo nginx paperless-scheduler paperless-task-queue paperless-consumer paperless-web freshrss-updater phpfpm-freshrss searx vaultwarden phpfpm-privatebin syncthing stirling-pdf phpfpm-firefly-iii phpfpm-nextcloud garage podman-memos podman-shlink podman-shlink-web podman-rustfs ntfy-sh"

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

echo 'Stopping productivity services before appdata restore...'
systemctl stop productivity-appdata-backup.timer \$services

echo 'Mounting /mnt/backups...'
findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups

if [ ! -r "\$RESTIC_PASSWORD_FILE" ]; then
  echo "\$RESTIC_PASSWORD_FILE is not readable; cannot inspect or restore appdata" >&2
  systemctl start postgresql \$services
  systemctl start productivity-appdata-backup.timer
  exit 1
fi

if [ ! -d "\$repository/data" ]; then
  echo "No initialized Restic repository found at \$repository; continuing as a fresh system."
  systemctl start postgresql \$services
  systemctl start productivity-appdata-backup.timer
  exit 0
fi

if ! restic snapshots --host '${HOST}' --path "\$source_path" --tag "\$tag" >/tmp/productivity-appdata-snapshots.txt; then
  echo 'Unable to inspect Restic snapshots; leaving productivity services stopped for investigation.' >&2
  cat /tmp/productivity-appdata-snapshots.txt >&2 || true
  exit 1
fi

snapshot_ids="\$(awk '/^[[:xdigit:]]{8}[[:space:]]/ { print \$1 }' /tmp/productivity-appdata-snapshots.txt)"
snapshot_count="\$(printf '%s\n' "\$snapshot_ids" | sed '/^$/d' | wc -l)"

if [ "\$snapshot_count" -eq 0 ]; then
  echo "No matching Restic snapshot found for host=${HOST}, path=\$source_path, tag=\$tag; continuing as a fresh system."
  systemctl start postgresql \$services
  systemctl start productivity-appdata-backup.timer
  exit 0
fi

cat /tmp/productivity-appdata-snapshots.txt

if [ -n "\$requested_snapshot" ]; then
  snapshot="\$requested_snapshot"
  if ! printf '%s\n' "\$snapshot_ids" | grep -Fxq "\$snapshot"; then
    echo "Requested snapshot \$snapshot is not in the matching snapshot list above; leaving productivity services stopped for investigation." >&2
    exit 1
  fi
elif [ "\$snapshot_count" -eq 1 ]; then
  snapshot="\$snapshot_ids"
else
  echo "Multiple matching snapshots exist; refusing to guess which one to restore." >&2
  echo "Rerun with an explicit snapshot ID, for example: scripts/productivity-vm/restore-productivity-appdata.sh \$(printf '%s\n' "\$snapshot_ids" | tail -n 1)" >&2
  echo "Tip: after a rebuild, avoid tiny fresh-system snapshots and choose the last known good appdata snapshot." >&2
  systemctl start postgresql \$services
  systemctl start productivity-appdata-backup.timer
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
[ -d "\$source_path/gitea" ] && chown -R gitea:gitea "\$source_path/gitea"
[ -d "\$source_path/forgejo" ] && chown -R forgejo:forgejo "\$source_path/forgejo"
[ -d "\$source_path/paperless" ] && chown -R paperless:paperless "\$source_path/paperless"
[ -d "\$source_path/freshrss" ] && chown -R freshrss:freshrss "\$source_path/freshrss"
[ -d "\$source_path/privatebin" ] && chown -R privatebin:privatebin "\$source_path/privatebin"
[ -d "\$source_path/firefly-iii" ] && chown -R firefly-iii:firefly-iii "\$source_path/firefly-iii"
[ -d "\$source_path/nextcloud" ] && chown -R nextcloud:nextcloud "\$source_path/nextcloud"
[ -d "\$source_path/vaultwarden" ] && chown -R vaultwarden:vaultwarden "\$source_path/vaultwarden"
[ -d "\$source_path/syncthing" ] && chown -R syncthing:syncthing "\$source_path/syncthing"
[ -d "\$source_path/stirling-pdf" ] && chown -R stirling-pdf:stirling-pdf "\$source_path/stirling-pdf"
[ -d "\$source_path/garage" ] && chown -R garage:garage "\$source_path/garage"
[ -d "\$source_path/memos" ] && chown -R 10002:10002 "\$source_path/memos"
[ -d "\$source_path/memos-backups" ] && chown -R 10002:10002 "\$source_path/memos-backups"
[ -d "\$source_path/rustfs" ] && chown -R 10001:10001 "\$source_path/rustfs"
[ -d "\$source_path/shlink" ] && chown -R root:productivity "\$source_path/shlink"
[ -d "\$source_path/ntfy" ] && chown -R ntfy-sh:ntfy-sh "\$source_path/ntfy"
[ -d "\$source_path/postgresql" ] && chown -R postgres:postgres "\$source_path/postgresql"
[ -d "\$source_path/postgresql-dumps" ] && chown -R postgres:postgres "\$source_path/postgresql-dumps"
find "\$source_path" -type f -name '*.pid' -delete

echo 'Reapplying declared directories and restarting productivity services...'
systemd-tmpfiles --create
systemctl start postgresql
systemctl start \$services
systemctl start productivity-appdata-backup.timer
systemctl start productivity-appdata-restore-check.service

echo 'productivity-vm appdata restore flow complete.'
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
