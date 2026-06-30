#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/testbed-vm"
SOURCE="/srv/appsdata"
SERVICES=(
  listmonk.service
  mailhog.service
  postgresql.service
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v ssh >/dev/null 2>&1 || die "ssh is missing"

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

printf 'Stopping backup timer and stateful testbed services...\n'
ssh_testbed_vm "sudo systemctl stop testbed-appdata-backup.timer"
for service in "${SERVICES[@]}"; do
  ssh_testbed_vm "sudo systemctl stop '$service' || true"
done

restart_services() {
  printf 'Restarting testbed services and backup timer...\n'
  for ((i=${#SERVICES[@]} - 1; i >= 0; i--)); do
    ssh_testbed_vm "sudo systemctl start '${SERVICES[$i]}' || true"
  done
  ssh_testbed_vm "sudo systemctl start listmonk-oidc-config.service || true"
  ssh_testbed_vm "sudo systemctl start testbed-appdata-backup.timer"
}

trap restart_services EXIT

printf 'Running PostgreSQL dump, Restic backup, and restore validation...\n'
ssh_testbed_vm "sudo systemctl start testbed-postgresql-dump.service"
ssh_testbed_vm "sudo systemctl start testbed-appdata-backup.service"
ssh_testbed_vm "sudo systemctl start testbed-appdata-restore-check.service"

printf 'Recent testbed-vm appdata snapshots:\n'
ssh_testbed_vm "sudo env RESTIC_REPOSITORY='$REPOSITORY' RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic snapshots --host '$HOST' --path '$SOURCE' --tag appsdata --latest 5"

trap - EXIT
restart_services

"$ROOT/scripts/testbed-vm/test-testbed-services.sh"
