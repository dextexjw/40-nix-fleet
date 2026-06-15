#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
HOST_IP="10.2.20.114"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
SERVICES=(
  redis-affine.service
  podman-affine.service
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
  phpfpm-nextcloud.service
  podman-openspeedtest.service
  phpfpm-invoiceplane.service
  mysql.service
  podman-netbootxyz.service
  iperf3.service
  podman-memos.service
  rustdesk-signal.service
  rustdesk-relay.service
  garage.service
  podman-shlink.service
  podman-shlink-web.service
  podman-rustfs.service
  ntfy-sh.service
)
ON_DEMAND_STOP_UNITS=(
  gitea-oidc-config.service
  gitea.service
  firefly-iii-cron.timer
  firefly-iii-cron.service
  phpfpm-firefly-iii.service
  stirling-pdf.service
)
GITEA_WAS_ACTIVE=0
FIREFLY_WAS_ACTIVE=0
STIRLING_WAS_ACTIVE=0

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

remote_unit_exists() {
  local unit="$1"

  ssh_productivity_vm "systemctl cat '$unit' >/dev/null 2>&1"
}

remote_unit_active() {
  local unit="$1"

  ssh_productivity_vm "systemctl is-active --quiet '$unit'"
}

set_maintenance_lock() {
  ssh_productivity_vm "sudo install -d -m 0755 -o root -g root /run/on-demand-apps-dashboard && printf '%s\n' 'consistency-first backup is running' | sudo tee /run/on-demand-apps-dashboard/maintenance.lock >/dev/null" || true
}

clear_maintenance_lock() {
  ssh_productivity_vm "sudo rm -f /run/on-demand-apps-dashboard/maintenance.lock" || true
}

cd "$ROOT"

printf 'Checking backup mount prerequisites on %s...\n' "$HOST"
ssh_productivity_vm "sh -lc 'getent hosts nas.home.arpa >/dev/null && (findmnt -rn --target /mnt/backups >/dev/null || sudo mount /mnt/backups)'"

if remote_unit_active gitea.service; then
  GITEA_WAS_ACTIVE=1
fi
if remote_unit_active phpfpm-firefly-iii.service; then
  FIREFLY_WAS_ACTIVE=1
fi
if remote_unit_active stirling-pdf.service; then
  STIRLING_WAS_ACTIVE=1
fi

printf 'Stopping backup timer and stateful productivity services...\n'
set_maintenance_lock
ssh_productivity_vm "sudo systemctl stop productivity-appdata-backup.timer"
for service in "${ON_DEMAND_STOP_UNITS[@]}"; do
  ssh_productivity_vm "sudo systemctl stop '$service' || true"
done
for service in "${SERVICES[@]}"; do
  ssh_productivity_vm "sudo systemctl stop '$service' || true"
done

restart_services() {
  printf 'Restarting productivity services and backup timer...\n'
  ssh_productivity_vm "sudo systemctl start postgresql.service"
  if remote_unit_exists mysql.service; then
    ssh_productivity_vm "sudo systemctl start mysql.service"
  fi
  for service in "${SERVICES[@]}"; do
    ssh_productivity_vm "sudo systemctl start '$service' || true"
  done
  if (( GITEA_WAS_ACTIVE )); then
    ssh_productivity_vm "sudo systemctl start gitea.service" || true
    if remote_unit_exists gitea-oidc-config.service; then
      ssh_productivity_vm "sudo systemctl start gitea-oidc-config.service" || true
    fi
  fi
  if (( FIREFLY_WAS_ACTIVE )); then
    ssh_productivity_vm "sudo systemctl start phpfpm-firefly-iii.service" || true
    ssh_productivity_vm "sudo systemctl start firefly-iii-cron.timer" || true
  fi
  if (( STIRLING_WAS_ACTIVE )); then
    ssh_productivity_vm "sudo systemctl start stirling-pdf.service" || true
  fi
  ssh_productivity_vm "sudo systemctl start productivity-appdata-backup.timer"
  clear_maintenance_lock
}

trap restart_services EXIT

printf 'Running PostgreSQL dump, Restic backup, and restore validation...\n'
ssh_productivity_vm "sudo systemctl start productivity-postgresql-dump.service"
if remote_unit_exists productivity-mariadb-dump.service; then
  ssh_productivity_vm "sudo systemctl start productivity-mariadb-dump.service"
else
  printf 'Skipping productivity-mariadb-dump.service because it is not deployed yet.\n'
fi
if remote_unit_exists productivity-memos-sqlite-backup.service; then
  ssh_productivity_vm "sudo systemctl start productivity-memos-sqlite-backup.service"
else
  printf 'Skipping productivity-memos-sqlite-backup.service because it is not deployed yet.\n'
fi
ssh_productivity_vm "sudo systemctl start productivity-appdata-backup.service"
ssh_productivity_vm "sudo systemctl start productivity-appdata-restore-check.service"

printf 'Recent productivity-vm appdata snapshots:\n'
ssh_productivity_vm "sudo env RESTIC_REPOSITORY='$REPOSITORY' RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic snapshots --host '$HOST' --path '$SOURCE' --tag appsdata --latest 5"

trap - EXIT
restart_services

"$ROOT/scripts/productivity-vm/test-productivity-services.sh" --allow-missing-new-services
