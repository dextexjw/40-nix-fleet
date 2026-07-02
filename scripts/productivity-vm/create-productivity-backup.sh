#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
HOST_IP="10.2.20.114"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
SERVICES=(
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
  podman-netbootxyz.service
  iperf3.service
  podman-memos.service
  rustdesk-signal.service
  rustdesk-relay.service
  garage.service
  podman-shlink.service
  podman-shlink-web.service
  podman-rustfs.service
)
ON_DEMAND_STOP_UNITS=(
  podman-affine.service
  redis-affine.service
  gitea-oidc-config.service
  gitea.service
  firefly-iii-cron.timer
  firefly-iii-cron.service
  phpfpm-firefly-iii.service
  stirling-pdf.service
)
ON_DEMAND_APPS=(
  affine
  gitea
  firefly
  stirling-pdf
)
declare -A ON_DEMAND_STATUS_UNIT=(
  [affine]=podman-affine.service
  [firefly]=phpfpm-firefly-iii.service
  [gitea]=gitea.service
  [stirling-pdf]=stirling-pdf.service
)
declare -A ON_DEMAND_START_UNITS=(
  [affine]="redis-affine.service podman-affine.service"
  [firefly]="phpfpm-firefly-iii.service firefly-iii-cron.timer"
  [gitea]="gitea.service gitea-oidc-config.service"
  [stirling-pdf]="stirling-pdf.service"
)
ON_DEMAND_ACTIVE_APPS=()

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

for app in "${ON_DEMAND_APPS[@]}"; do
  if remote_unit_active "${ON_DEMAND_STATUS_UNIT[$app]}"; then
    ON_DEMAND_ACTIVE_APPS+=("$app")
  fi
done

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
  for service in "${SERVICES[@]}"; do
    ssh_productivity_vm "sudo systemctl start '$service' || true"
  done
  for app in "${ON_DEMAND_ACTIVE_APPS[@]}"; do
    for unit in ${ON_DEMAND_START_UNITS[$app]}; do
      if remote_unit_exists "$unit"; then
        ssh_productivity_vm "sudo systemctl start '$unit' || true"
      fi
    done
  done
  ssh_productivity_vm "sudo systemctl start productivity-appdata-backup.timer"
  clear_maintenance_lock
}

trap restart_services EXIT

printf 'Running PostgreSQL dump, Restic backup, and restore validation...\n'
ssh_productivity_vm "sudo systemctl start productivity-postgresql-dump.service"
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
