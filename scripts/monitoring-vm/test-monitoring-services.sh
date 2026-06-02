#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="monitoring-vm"
REPOSITORY="/mnt/backups/restic/appdata/monitoring-vm"
SOURCE="/srv/appsdata"
SERVICE_DOMAINS=(
  jax22.com
  h
)
KEY_UNITS=(
  beszel-agent.service
  beszel-hub.service
  checkmate-capture.service
  podman-checkmate.service
  podman-checkmate-mongodb.service
  monitoring-appdata-backup.timer
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

printf 'Checking key monitoring units...\n'
for unit in "${KEY_UNITS[@]}"; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$unit"
done

printf 'Checking monitoring listeners...\n'
colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :52345 )' | grep -Eq '([[:space:]]|^)(10[.]2[.]20[.]115|0[.]0[.]0[.]0|\\*|\\[::\\]):52345'"
colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :8090 )' | grep -Eq '([[:space:]]|^)(10[.]2[.]20[.]115|0[.]0[.]0[.]0|\\*|\\[::\\]):8090'"
colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :59232 )' | grep -Eq '([[:space:]]|^)(10[.]2[.]20[.]115|0[.]0[.]0[.]0|\\*|\\[::\\]):59232'"
colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :45876 )' | grep -q ':45876'"
colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :27017 )' | grep -Eq '([[:space:]]|^)(127[.]0[.]0[.]1|\\[::1\\]):27017'"

printf 'Checking direct HTTP endpoints...\n'
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:52345/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8090/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:59232/health >/dev/null"

printf 'Checking routed host-header behavior on monitoring-vm backends...\n'
for domain in "${SERVICE_DOMAINS[@]}"; do
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: checkmate.${domain}' http://127.0.0.1:52345/ >/dev/null"
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: beszel.${domain}' http://127.0.0.1:8090/ >/dev/null"
done

printf 'Checking declarative Checkmate provisioning state...\n'
colmena exec --on "$HOST" -- "getent hosts homepage.jax22.com | grep -q '10[.]2[.]20[.]112'"
colmena exec --on "$HOST" -- "jq -e '.expectedServiceMonitors == 38 and .expectedHardwareMonitors == 4 and .expectedManagedMonitors == 42 and (.serviceMonitors | length == 38) and (.hardwareMonitors | length == 4)' /etc/fleet/checkmate-targets.json >/dev/null"
colmena exec --on "$HOST" -- "jq -e 'any(.serviceMonitors[]; .id == \"openspeedtest\") and all(.serviceMonitors[]; (.id | test(\"^libr(e)?speed$\") | not))' /etc/fleet/checkmate-targets.json >/dev/null"
colmena exec --on "$HOST" -- "jq -e 'all(.hardwareMonitors[]; .url | endswith(\"/api/v1/metrics\"))' /etc/fleet/checkmate-targets.json >/dev/null"
colmena exec --on "$HOST" -- "systemctl show checkmate-provisioning.service -p Result -p ExecMainStatus | grep -Fxq Result=success && systemctl show checkmate-provisioning.service -p Result -p ExecMainStatus | grep -Fxq ExecMainStatus=0"
colmena exec --on "$HOST" -- "sudo jq -e '.expectedServiceMonitors == 38 and .expectedHardwareMonitors == 4 and .expectedManagedMonitors == 42' /var/lib/checkmate-provisioning/last-summary.json >/dev/null"

printf 'Checking backup and restore validation...\n'
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start monitoring-appdata-backup.service
colmena exec --on "$HOST" -- systemctl start monitoring-appdata-restore-check.service
colmena exec --on "$HOST" -- systemctl is-active --quiet monitoring-appdata-backup.timer
colmena exec --on "$HOST" -- env \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 3

printf 'monitoring-vm validation completed.\n'
