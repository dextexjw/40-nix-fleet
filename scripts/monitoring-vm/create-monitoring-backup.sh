#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="monitoring-vm"
HOST_IP="10.2.20.115"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/monitoring-vm"
SOURCE="/srv/appsdata"
SERVICES=(
  beszel-hub.service
  ntfy-sh.service
  podman-checkmate.service
  podman-checkmate-mongodb.service
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v ssh >/dev/null 2>&1 || die "ssh is missing"

ssh_monitoring_vm() {
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
ssh_monitoring_vm "sh -lc 'getent hosts nas.home.arpa >/dev/null && (findmnt -rn --target /mnt/backups >/dev/null || sudo mount /mnt/backups)'"

printf 'Stopping backup timer and stateful monitoring services...\n'
ssh_monitoring_vm "sudo systemctl stop monitoring-appdata-backup.timer"
for service in "${SERVICES[@]}"; do
  ssh_monitoring_vm "sudo systemctl stop '$service' || true"
done

restart_services() {
  printf 'Restarting monitoring services and backup timer...\n'
  for ((i=${#SERVICES[@]} - 1; i >= 0; i--)); do
    ssh_monitoring_vm "sudo systemctl start '${SERVICES[$i]}' || true"
  done
  ssh_monitoring_vm "sudo systemctl start monitoring-appdata-backup.timer"
}

trap restart_services EXIT

printf 'Running Restic backup and restore validation...\n'
ssh_monitoring_vm "sudo systemctl start monitoring-appdata-backup.service"
ssh_monitoring_vm "sudo systemctl start monitoring-appdata-restore-check.service"

printf 'Recent monitoring-vm appdata snapshots:\n'
ssh_monitoring_vm "sudo env RESTIC_REPOSITORY='$REPOSITORY' RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic snapshots --host '$HOST' --path '$SOURCE' --tag appsdata --latest 5"

trap - EXIT
restart_services

"$ROOT/scripts/monitoring-vm/test-monitoring-services.sh"
