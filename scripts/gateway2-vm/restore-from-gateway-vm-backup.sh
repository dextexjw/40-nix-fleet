#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="gateway2-vm"
SOURCE_HOST="gateway-vm"
SOURCE_REPOSITORY="/mnt/backup/restic/appdata/gateway-vm"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

need base64
need colmena

cd "$ROOT"

remote_script="$(
  cat <<'SCRIPT'
set -euo pipefail

source_repository='/mnt/backup/restic/appdata/gateway-vm'
source_host='gateway-vm'
source_path='/srv/appsdata'
tag='appsdata'
archive_root='/srv'
stopped_services=()

unit_exists() {
  local unit="$1"

  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "^${unit}[[:space:]]"
}

stop_if_active() {
  local unit="$1"

  if ! unit_exists "$unit"; then
    printf '  %s not installed; skipping\n' "$unit"
    return 0
  fi

  if systemctl is-active --quiet "$unit"; then
    stopped_services+=("$unit")
    printf '  %s will be restarted after restore\n' "$unit"
  else
    printf '  %s is not active; leaving it stopped\n' "$unit"
  fi
}

printf 'Mounting /mnt/backup...\n'
if ! getent hosts nas.home.arpa >/dev/null; then
  echo 'nas.home.arpa does not resolve on gateway2-vm; refusing to restore state' >&2
  exit 1
fi

systemctl reset-failed mnt-backup.mount mnt-backup.automount 2>/dev/null || true
if ! findmnt -rn --mountpoint /mnt/backup >/dev/null; then
  systemctl start mnt-backup.mount
fi
if ! findmnt -rn --mountpoint /mnt/backup >/dev/null; then
  echo '/mnt/backup is not mounted; refusing to restore state' >&2
  exit 1
fi

export RESTIC_REPOSITORY="$source_repository"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
export RESTIC_CACHE_DIR=/var/cache/restic-gateway-appsdata

if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
  echo "$RESTIC_PASSWORD_FILE is not readable; refusing to restore state" >&2
  exit 1
fi

printf 'Checking latest gateway-vm appdata snapshot...\n'
restic snapshots \
  --host "$source_host" \
  --path "$source_path" \
  --tag "$tag" \
  --latest 1 \
  --retry-lock 30m

printf 'Stopping Gateway2 services before restore...\n'
systemctl stop gateway-state-backup.timer 2>/dev/null || true
for unit in traefik.service authentik-worker.service authentik-server.service redis-authentik.service postgresql.service podman-gluetun-webui.service podman-gluetun.service technitium-dns-server.service tailscaled.service netbird.service; do
  stop_if_active "$unit"
done

if [ "${#stopped_services[@]}" -gt 0 ]; then
  systemctl stop "${stopped_services[@]}"
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
if [ -e "$source_path" ]; then
  archive_path="$archive_root/appsdata.pre-gateway-vm-restore.$timestamp"
  printf 'Archiving existing %s to %s...\n' "$source_path" "$archive_path"
  mv "$source_path" "$archive_path"
fi

printf 'Restoring latest gateway-vm appdata snapshot to /...\n'
restic restore latest \
  --host "$source_host" \
  --path "$source_path" \
  --tag "$tag" \
  --target / \
  --verify \
  --retry-lock 30m

printf 'Resetting node-unique mesh identity state...\n'
rm -rf -- "$source_path/tailscale" "$source_path/netbird"

printf 'Recreating declared directories and permissions...\n'
systemd-tmpfiles --create

printf 'Starting Gateway2 services after restore...\n'
for unit in postgresql.service redis-authentik.service authentik-server.service authentik-worker.service traefik.service homepage-dashboard.service technitium-dns-server.service podman-gluetun.service podman-gluetun-webui.service tailscaled.service netbird.service; do
  if unit_exists "$unit"; then
    systemctl start "$unit"
  fi
done
systemctl start gateway-state-backup.timer

printf 'Running Gateway2 backup and restore validation against its own repository...\n'
systemctl start gateway-state-backup.service
systemctl start gateway-state-restore-check.service
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

printf 'Restoring %s from latest %s appdata backup...\n' "$HOST" "$SOURCE_HOST"
printf 'Source repository: %s\n' "$SOURCE_REPOSITORY"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"

"$ROOT/scripts/gateway2-vm/test-gateway2-services.sh"
