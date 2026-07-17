#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
REMOTE_USER="smoke"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v ssh >/dev/null 2>&1 || die "ssh is missing"
SKIP_OUTLINE_SMOKE=0
SKIP_SURE_SMOKE=0

ssh_testbed_vm() {
  ssh \
    -o BatchMode=yes \
    -o CheckHostIP=no \
    -o ConnectTimeout=5 \
    -o GlobalKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UpdateHostKeys=no \
    -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$HOST_IP" \
    "$@"
}

cd "$ROOT"

printf 'Checking backup mount prerequisites on %s...\n' "$HOST"
ssh_testbed_vm "sh -lc 'getent hosts nas.home.arpa >/dev/null && (findmnt -rn --target /mnt/backups >/dev/null || sudo mount /mnt/backups)'"
if ! ssh_testbed_vm "systemctl show -P LoadState podman-sure-web.service 2>/dev/null | grep -Fxq loaded"; then
  SKIP_SURE_SMOKE=1
fi
if ! ssh_testbed_vm "systemctl show -P LoadState podman-outline.service 2>/dev/null | grep -Fxq loaded"; then
  SKIP_OUTLINE_SMOKE=1
fi

printf 'Running the declaration-driven backup and restore validation...\n'
ssh_testbed_vm "sudo systemctl start testbed-appdata-backup.service"
ssh_testbed_vm "sudo systemctl start testbed-appdata-restore-check.service"

printf 'Verifying recent testbed-vm appdata snapshots and lifecycle health:\n'
ssh_testbed_vm "sudo /etc/fleet/testbed-recovery-verify"

SKIP_OUTLINE_SMOKE="$SKIP_OUTLINE_SMOKE" SKIP_SURE_SMOKE="$SKIP_SURE_SMOKE" "$ROOT/scripts/testbed-vm/test-testbed-services.sh"
