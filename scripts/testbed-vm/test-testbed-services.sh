#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
REPOSITORY="/mnt/backups/restic/appdata/testbed-vm"
SOURCE="/srv/appsdata"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

printf 'Checking key testbed services...\n'
for service in postgresql listmonk mailhog; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result listmonk-oidc-config.service)\" = success"

printf 'Checking Listmonk appdata and local listeners...\n'
colmena exec --on "$HOST" -- test -d /srv/appsdata/listmonk/uploads
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9000/admin/login | grep -Fq 'Authentik'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8025/api/v2/messages >/dev/null"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d listmonk -tAc \"select (value->>'enabled') from settings where key = 'security.oidc'\" | tr -d '[:space:]' | grep -Fxq true"

printf 'Checking backup and restore validation...\n'
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start testbed-appdata-backup.service
colmena exec --on "$HOST" -- systemctl start testbed-appdata-restore-check.service
colmena exec --on "$HOST" -- systemctl is-active --quiet testbed-appdata-backup.timer
colmena exec --on "$HOST" -- test -s /srv/appsdata/postgresql-dumps/latest.sql.gz
colmena exec --on "$HOST" -- env \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 3

printf 'Checking Gateway-routed Listmonk URLs when reachable from this environment...\n'
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve listmonk.jax22.com:443:127.0.0.1 https://listmonk.jax22.com/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: listmonk.h' http://127.0.0.1/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/listmonk/.well-known/openid-configuration | grep -Fq '\"issuer\"'"

printf 'testbed-vm validation completed.\n'
