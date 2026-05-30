#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
HOST_IP="10.2.20.114"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
SERVICES=(
  gitea.service
  forgejo.service
  nginx.service
  paperless-scheduler.service
  paperless-task-queue.service
  paperless-consumer.service
  paperless-web.service
  freshrss-updater.service
  phpfpm-freshrss.service
  searx.service
  vaultwarden.service
  phpfpm-privatebin.service
  syncthing.service
  stirling-pdf.service
  phpfpm-firefly-iii.service
  phpfpm-nextcloud.service
  garage.service
  podman-rustfs.service
  ntfy-sh.service
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

need ssh

ssh_productivity_vm() {
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
ssh_productivity_vm "sh -lc 'getent hosts nas.home.arpa >/dev/null && (findmnt -rn --target /mnt/backups >/dev/null || sudo mount /mnt/backups)'"

printf 'Stopping backup timer and stateful productivity services...\n'
ssh_productivity_vm "sudo systemctl stop productivity-appdata-backup.timer"
for service in "${SERVICES[@]}"; do
  ssh_productivity_vm "sudo systemctl stop '$service' || true"
done

restart_services() {
  printf 'Restarting productivity services and backup timer...\n'
  ssh_productivity_vm "sudo systemctl start postgresql.service"
  for service in "${SERVICES[@]}"; do
    ssh_productivity_vm "sudo systemctl start '$service' || true"
  done
  ssh_productivity_vm "sudo systemctl start productivity-appdata-backup.timer"
}

trap restart_services EXIT

printf 'Running PostgreSQL dump, Restic backup, and restore validation...\n'
ssh_productivity_vm "sudo systemctl start productivity-postgresql-dump.service"
ssh_productivity_vm "sudo systemctl start productivity-appdata-backup.service"
ssh_productivity_vm "sudo systemctl start productivity-appdata-restore-check.service"

printf 'Recent productivity-vm appdata snapshots:\n'
ssh_productivity_vm "sudo env RESTIC_REPOSITORY='$REPOSITORY' RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic snapshots --host '$HOST' --path '$SOURCE' --tag appsdata --latest 5"

trap - EXIT
restart_services

"$ROOT/scripts/productivity-vm/test-productivity-services.sh" --allow-missing-new-services
