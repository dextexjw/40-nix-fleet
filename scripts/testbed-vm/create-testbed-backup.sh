#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
REMOTE_USER="smoke"
REPOSITORY="/mnt/backups/restic/appdata/testbed-vm"
SOURCE="/srv/appsdata"
SERVICES=(
  podman-fizzy.service
  phpfpm-invoiceplane.service
  mysql.service
  homebox.service
  podman-kaneo.service
  podman-keeper.service
  podman-outline.service
  podman-plane-space.service
  podman-plane-admin.service
  podman-plane-web.service
  podman-plane-live.service
  podman-plane-beat-worker.service
  podman-plane-worker.service
  podman-plane-api.service
  podman-plane-rabbitmq.service
  podman-postiz.service
  podman-postiz-postgres.service
  podman-postiz-redis.service
  podman-postiz-temporal.service
  podman-postiz-temporal-elasticsearch.service
  podman-postiz-temporal-postgres.service
  podman-sure-web.service
  podman-sure-worker.service
  redis-plane.service
  redis-sure.service
  listmonk.service
  mailpit-testbed.service
  redis-outline.service
  redis-keeper.service
  postgresql.service
)

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

printf 'Stopping backup timer and stateful testbed services...\n'
ssh_testbed_vm "sudo systemctl stop testbed-appdata-backup.timer"
for service in "${SERVICES[@]}"; do
  ssh_testbed_vm "sudo systemctl stop '$service' || true"
done

restart_services() {
  printf 'Restarting testbed services and backup timer...\n'
  for ((i=${#SERVICES[@]} - 1; i >= 0; i--)); do
    ssh_testbed_vm "sudo systemctl start --no-block '${SERVICES[$i]}' || true"
  done
  ssh_testbed_vm "sudo systemctl start kaneo-postgresql-password.service || true"
  ssh_testbed_vm "sudo systemctl start keeper-postgresql-password.service || true"
  ssh_testbed_vm "sudo systemctl start listmonk-oidc-config.service || true"
  ssh_testbed_vm "sudo systemctl start outline-postgresql-password.service || true"
  ssh_testbed_vm "sudo systemctl start plane-postgresql-password.service || true"
  ssh_testbed_vm "sudo systemctl start plane-rabbitmq-config.service || true"
  ssh_testbed_vm "sudo systemctl start postiz-podman-network.service || true"
  ssh_testbed_vm "sudo systemctl start postiz-environment.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz-temporal-elasticsearch.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz-temporal-postgres.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz-temporal.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz-postgres.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz-redis.service || true"
  ssh_testbed_vm "sudo systemctl start podman-postiz.service || true"
  ssh_testbed_vm "sudo systemctl start sure-postgresql-password.service || true"
  ssh_testbed_vm "sudo systemctl start plane-migrate.service || true"
  ssh_testbed_vm "sudo systemctl start invoiceplane-mysql-password.service || true"
  ssh_testbed_vm "sudo systemctl start invoiceplane-prepare.service || true"
  ssh_testbed_vm "sudo systemctl start phpfpm-invoiceplane.service || true"
  ssh_testbed_vm "sudo systemctl start invoiceplane-bootstrap.service || true"
  ssh_testbed_vm "sudo systemctl start podman-plane-api.service || true"
  ssh_testbed_vm "sudo systemctl start podman-plane-worker.service || true"
  ssh_testbed_vm "sudo systemctl start podman-plane-beat-worker.service || true"
  ssh_testbed_vm "sudo systemctl start podman-plane-live.service || true"
  ssh_testbed_vm "sudo systemctl start plane-admin-bootstrap.service || true"
  ssh_testbed_vm "sudo systemctl start podman-sure-web.service || true"
  ssh_testbed_vm "sudo systemctl start podman-sure-worker.service || true"
  ssh_testbed_vm "sudo systemctl start testbed-appdata-backup.timer"
}

trap restart_services EXIT

printf 'Running PostgreSQL dump, Restic backup, and restore validation...\n'
ssh_testbed_vm "sudo systemctl start testbed-mariadb-dump.service"
ssh_testbed_vm "sudo systemctl start testbed-postgresql-dump.service"
ssh_testbed_vm "sudo systemctl start testbed-appdata-backup.service"
ssh_testbed_vm "sudo systemctl start testbed-appdata-restore-check.service"

printf 'Recent testbed-vm appdata snapshots:\n'
ssh_testbed_vm "sudo env RESTIC_REPOSITORY='$REPOSITORY' RESTIC_PASSWORD_FILE=/run/secrets/restic-password restic snapshots --host '$HOST' --path '$SOURCE' --tag appsdata --latest 5"

trap - EXIT
restart_services

SKIP_OUTLINE_SMOKE="$SKIP_OUTLINE_SMOKE" SKIP_SURE_SMOKE="$SKIP_SURE_SMOKE" "$ROOT/scripts/testbed-vm/test-testbed-services.sh"
