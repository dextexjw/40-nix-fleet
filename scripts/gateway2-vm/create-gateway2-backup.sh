#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="gateway2-vm"

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

repository='/mnt/backup/restic/appdata/gateway2-vm'
source_path='/srv/appsdata'
tag='appsdata'
stopped_services=()

unit_exists() {
  local unit="$1"

  systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q "^${unit}[[:space:]]"
}

cleanup() {
  local status="$?"
  local restart_status=0

  set +e

  printf 'Restarting Gateway services and backup timer...\n'
  if [ "${#stopped_services[@]}" -gt 0 ]; then
    systemctl start --no-block "${stopped_services[@]}"
    restart_status="$?"
    if [ "$status" -eq 0 ] && [ "$restart_status" -ne 0 ]; then
      status="$restart_status"
    fi
  fi

  systemctl start gateway-state-backup.timer
  restart_status="$?"
  if [ "$status" -eq 0 ] && [ "$restart_status" -ne 0 ]; then
    status="$restart_status"
  fi

  exit "$status"
}

printf 'Mounting /mnt/backup...\n'
if ! getent hosts nas.home.arpa >/dev/null; then
  echo 'nas.home.arpa does not resolve on gateway2-vm; refusing to stop services for backup' >&2
  exit 1
fi

systemctl reset-failed mnt-backup.mount mnt-backup.automount 2>/dev/null || true
if ! findmnt -rn --mountpoint /mnt/backup >/dev/null; then
  systemctl start mnt-backup.mount
fi
if ! findmnt -rn --mountpoint /mnt/backup >/dev/null; then
  echo '/mnt/backup is not mounted; refusing to run backup' >&2
  exit 1
fi

export RESTIC_REPOSITORY="$repository"
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password
export RESTIC_CACHE_DIR=/var/cache/restic-gateway-appsdata

if [ ! -r "$RESTIC_PASSWORD_FILE" ]; then
  echo "$RESTIC_PASSWORD_FILE is not readable; refusing to run backup" >&2
  exit 1
fi

trap cleanup EXIT

printf 'Stopping gateway-state-backup.timer...\n'
systemctl stop gateway-state-backup.timer

printf 'Stopping stateful Gateway services for a consistent snapshot...\n'
for unit in traefik.service authentik-worker.service authentik-server.service redis-authentik.service postgresql.service podman-gluetun-webui.service podman-gluetun.service technitium-dns-server.service tailscaled.service netbird.service; do
  if ! unit_exists "$unit"; then
    printf '  %s not installed; skipping\n' "$unit"
    continue
  fi

  if systemctl is-active --quiet "$unit"; then
    stopped_services+=("$unit")
    printf '  %s will be restarted after validation\n' "$unit"
  else
    printf '  %s is not active; leaving it stopped\n' "$unit"
  fi
done

if [ "${#stopped_services[@]}" -gt 0 ]; then
  systemctl stop "${stopped_services[@]}"
fi

printf 'Running gateway-state-backup.service...\n'
systemctl start gateway-state-backup.service

printf 'Running gateway-state-restore-check.service...\n'
systemctl start gateway-state-restore-check.service

printf 'Latest Gateway appdata Restic snapshots:\n'
restic snapshots \
  --host gateway2-vm \
  --path "$source_path" \
  --tag "$tag" \
  --latest 5 \
  --retry-lock 30m
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

colmena exec --on "$HOST" -- "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"

"$ROOT/scripts/gateway2-vm/test-gateway2-services.sh"
