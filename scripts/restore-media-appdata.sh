#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="media-vm"
REPOSITORY="/mnt/backups/restic/appdata/media-stack-vm"
SOURCE="/srv/appsdata"
TAG="appsdata"
SERVICES="jellyfin audiobookshelf kavita radarr sonarr prowlarr bazarr podman-media-gluetun-webui podman-media-qbittorrent podman-media-sabnzbd podman-media-gluetun seerr flaresolverr"
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

echo 'Stopping media services before appdata restore...'
systemctl stop appsdata-backup.timer \$services

echo 'Mounting /mnt/backups...'
findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups

if [ ! -r "\$RESTIC_PASSWORD_FILE" ]; then
  echo "\$RESTIC_PASSWORD_FILE is not readable; cannot inspect or restore appdata" >&2
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 1
fi

if [ ! -d "\$repository/data" ]; then
  echo "No initialized Restic repository found at \$repository; continuing as a fresh system."
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 0
fi

if ! restic snapshots --host '${HOST}' --path "\$source_path" --tag "\$tag" >/tmp/appsdata-snapshots.txt; then
  echo 'Unable to inspect Restic snapshots; leaving media services stopped for investigation.' >&2
  cat /tmp/appsdata-snapshots.txt >&2 || true
  exit 1
fi

snapshot_ids="\$(awk '/^[[:xdigit:]]{8}[[:space:]]/ { print \$1 }' /tmp/appsdata-snapshots.txt)"
snapshot_count="\$(printf '%s\n' "\$snapshot_ids" | sed '/^$/d' | wc -l)"

if [ "\$snapshot_count" -eq 0 ]; then
  echo "No matching Restic snapshot found for host=${HOST}, path=\$source_path, tag=\$tag; continuing as a fresh system."
  systemctl start \$services
  systemctl start appsdata-backup.timer
  exit 0
fi

cat /tmp/appsdata-snapshots.txt

if [ -n "\$requested_snapshot" ]; then
  snapshot="\$requested_snapshot"
  if ! printf '%s\n' "\$snapshot_ids" | grep -Fxq "\$snapshot"; then
    echo "Requested snapshot \$snapshot is not in the matching snapshot list above; leaving media services stopped for investigation." >&2
    exit 1
  fi
elif [ "\$snapshot_count" -eq 1 ]; then
  snapshot="\$snapshot_ids"
else
  echo "Multiple matching snapshots exist; refusing to guess which one to restore." >&2
  echo "Rerun with an explicit snapshot ID, for example: scripts/restore-media-appdata.sh \$(printf '%s\n' "\$snapshot_ids" | tail -n 1)" >&2
  echo "Tip: after a rebuild, avoid tiny fresh-system snapshots and choose the last known good appdata snapshot." >&2
  systemctl start \$services
  systemctl start appsdata-backup.timer
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
chown root:media "\$source_path"
chmod 0770 "\$source_path"
[ -d "\$source_path/jellyfin" ] && chown -R jellyfin:media "\$source_path/jellyfin"
[ -d "\$source_path/audiobookshelf" ] && chown -R audiobookshelf:media "\$source_path/audiobookshelf"
[ -d "\$source_path/kavita" ] && chown -R kavita:kavita "\$source_path/kavita"
[ -d "\$source_path/radarr" ] && chown -R radarr:media "\$source_path/radarr"
[ -d "\$source_path/sonarr" ] && chown -R sonarr:media "\$source_path/sonarr"
if [ -d "\$source_path/prowlarr" ]; then
  if [ -e "\$source_path/prowlarr/config.xml" ]; then
    prowlarr_owner="\$(stat -c '%u:%g' "\$source_path/prowlarr/config.xml")"
    chown -R "\$prowlarr_owner" "\$source_path/prowlarr"
  else
    echo 'Prowlarr config.xml is unavailable; leaving contents as restored and repairing the top directory for DynamicUser startup.'
  fi
  chown nobody:nogroup "\$source_path/prowlarr"
  chmod 0700 "\$source_path/prowlarr"
fi
[ -d "\$source_path/bazarr" ] && chown -R bazarr:media "\$source_path/bazarr"
[ -d "\$source_path/qbittorrent" ] && chown -R qbittorrent:media "\$source_path/qbittorrent"
[ -d "\$source_path/gluetun" ] && chown -R root:media "\$source_path/gluetun"
[ -d "\$source_path/sabnzbd" ] && chown -R sabnzbd:media "\$source_path/sabnzbd"
if [ -d "\$source_path/jellyseerr" ] && [ ! -e "\$source_path/seerr" ]; then
  mv "\$source_path/jellyseerr" "\$source_path/seerr"
fi
[ -d "\$source_path/seerr" ] && chown -R seerr:media "\$source_path/seerr"
[ -d "\$source_path/flaresolverr" ] && chown -R root:media "\$source_path/flaresolverr"
[ -d "\$source_path/monitoring" ] && chown -R root:media "\$source_path/monitoring"
find "\$source_path" -type f \( -name '*.pid' -o -name 'plexmediaserver.pid' \) -delete

echo 'Reapplying declared directories and restarting media services...'
systemd-tmpfiles --create
if [ -d "\$source_path/prowlarr" ]; then
  chown nobody:nogroup "\$source_path/prowlarr"
  chmod 0700 "\$source_path/prowlarr"
fi
systemctl restart media-gluetun-control-auth-config.service
systemctl restart kavita-token-key.service
systemctl start \$services
systemctl start appsdata-backup.timer
systemctl start appsdata-restore-check.service

echo 'media-vm appdata restore flow complete.'
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
