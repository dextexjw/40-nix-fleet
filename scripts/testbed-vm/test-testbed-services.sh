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
for service in postgresql listmonk mailpit-testbed podman-fizzy; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result listmonk-oidc-config.service)\" = success"

printf 'Checking testbed appdata and local listeners...\n'
colmena exec --on "$HOST" -- test -d /srv/appsdata/fizzy/storage
colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%g' /srv/appsdata/fizzy/storage)\" = 1000:1000"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9010/up >/dev/null"
colmena exec --on "$HOST" -- test -d /srv/appsdata/listmonk/uploads
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9000/admin/login | grep -Fq 'Authentik'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:8025/api/v1/messages >/dev/null"
colmena exec --on "$HOST" -- "podman exec fizzy env | grep -Fxq 'SMTP_USERNAME=fizzy'"
colmena exec --on "$HOST" -- "python3 -c 'import email.message, smtplib; msg = email.message.EmailMessage(); msg[\"Subject\"] = \"testbed SMTP AUTH smoke\"; msg[\"From\"] = \"fizzy@testbed.home.arpa\"; msg[\"To\"] = \"test@example.com\"; msg.set_content(\"testbed SMTP AUTH smoke\"); smtp = smtplib.SMTP(\"127.0.0.1\", 1025, timeout=5); smtp.login(\"fizzy\", \"mailpit\"); smtp.send_message(msg); smtp.quit()'"
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
colmena exec --on gateway-vm -- "status=\$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --resolve fizzy.jax22.com:443:127.0.0.1 https://fizzy.jax22.com/up); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Fizzy auth status \$status\" >&2; exit 1 ;; esac"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: fizzy.h' http://127.0.0.1/up >/dev/null"
colmena exec --on gateway-vm -- "grep -Fq 'https://fizzy.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9010/up' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve listmonk.jax22.com:443:127.0.0.1 https://listmonk.jax22.com/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: listmonk.h' http://127.0.0.1/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/listmonk/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "status=\$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --resolve mailpit.jax22.com:443:127.0.0.1 https://mailpit.jax22.com/api/v1/messages); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Mailpit auth status \$status\" >&2; exit 1 ;; esac"
colmena exec --on gateway-vm -- "grep -Fq 'https://mailpit.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:8025/api/v1/messages' /etc/homepage-dashboard/services.yaml"

printf 'testbed-vm validation completed.\n'
