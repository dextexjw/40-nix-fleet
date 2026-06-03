#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="media-vm"
HOST_ADDR="10.2.20.113"
HOST_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/media-stack-vm"
SOURCE="/srv/appsdata"
LATEST="${1:-}"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v base64 >/dev/null 2>&1 || die "base64 is missing"
command -v ssh >/dev/null 2>&1 || die "ssh is missing"

if [ -n "$LATEST" ] && [[ ! "$LATEST" =~ ^[0-9]+$ ]]; then
  die "optional latest count must be a positive integer"
fi

cd "$ROOT"

latest_arg=""
if [ -n "$LATEST" ]; then
  latest_arg="--latest $LATEST"
fi

remote_script="$(
  cat <<SCRIPT
set -euo pipefail

findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups

export RESTIC_REPOSITORY='${REPOSITORY}'
export RESTIC_PASSWORD_FILE=/run/secrets/restic-password

restic snapshots --host '${HOST}' --path '${SOURCE}' --tag appsdata ${latest_arg}
SCRIPT
)"

remote_script_b64="$(printf '%s' "$remote_script" | base64 --wrap=0)"

ssh "${HOST_USER}@${HOST_ADDR}" "printf '%s' '$remote_script_b64' | base64 -d | sudo bash"
