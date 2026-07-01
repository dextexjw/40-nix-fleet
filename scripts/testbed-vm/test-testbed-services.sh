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
for service in postgresql redis-keeper listmonk homebox mailpit-testbed podman-fizzy podman-kaneo podman-keeper; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result kaneo-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result keeper-postgresql-password.service)\" = success"
colmena exec --on "$HOST" -- "test \"\$(systemctl show -P Result listmonk-oidc-config.service)\" = success"

printf 'Checking testbed appdata and local listeners...\n'
colmena exec --on "$HOST" -- test -d /srv/appsdata/fizzy/storage
colmena exec --on "$HOST" -- "test \"\$(stat -c '%u:%g' /srv/appsdata/fizzy/storage)\" = 1000:1000"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:9010/up >/dev/null"
colmena exec --on "$HOST" -- test -d /srv/appsdata/keeper/redis
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:3000/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3001/api/health >/dev/null"
colmena exec --on "$HOST" -- sudo test -d /srv/appsdata/homebox/data
colmena exec --on "$HOST" -- "test \"\$(sudo stat -c '%U:%G' /srv/appsdata/homebox/data)\" = homebox:homebox"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:7745/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on "$HOST" -- test -d /srv/appsdata/kaneo/tmp
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://${HOST_IP}:5173/api/health >/dev/null"
colmena exec --on "$HOST" -- "podman exec kaneo env | grep -Fxq 'CUSTOM_OAUTH_CLIENT_ID=kaneo'"
colmena exec --on "$HOST" -- "podman exec kaneo env | grep -Fxq 'S3_BUCKET=kaneo-uploads'"
colmena exec --on "$HOST" -- "sudo -u postgres psql -d kaneo -tAc 'select 1' | tr -d '[:space:]' | grep -Fxq 1"
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
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve fizzy.jax22.com:443:127.0.0.1 https://fizzy.jax22.com/up); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Fizzy auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: fizzy.h' http://127.0.0.1/up >/dev/null"
colmena exec --on gateway-vm -- "grep -Fq 'https://fizzy.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:9010/up' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve keeper.jax22.com:443:127.0.0.1 https://keeper.jax22.com/); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Keeper auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://keeper.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:3000/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve homebox.jax22.com:443:127.0.0.1 https://homebox.jax22.com/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: homebox.h' http://127.0.0.1/api/v1/status | grep -Fq '\"health\":true'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/homebox/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'headers=\$(mktemp); body=\$(mktemp); trap \"rm -f \\\"\$headers\\\" \\\"\$body\\\"\" EXIT; status=\$(curl -sS -D \"\$headers\" -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve homebox.jax22.com:443:127.0.0.1 https://homebox.jax22.com/api/v1/users/login/oidc); test \"\$status\" = 302; tr -d \"\\r\" < \"\$headers\" | grep -Fqi \"location: https://auth.jax22.com/application/o/authorize/\"; tr -d \"\\r\" < \"\$headers\" | grep -Fq \"redirect_uri=https%3A%2F%2Fhomebox.jax22.com%2Fapi%2Fv1%2Fusers%2Flogin%2Foidc%2Fcallback\"; ! tr -d \"\\r\" < \"\$headers\" | grep -Fq \"redirect_uri=https%3A%2F%2Fhttps\"; tr -d \"\\r\" < \"\$headers\" | grep -Fq \"Domain=homebox.jax22.com\"; ! tr -d \"\\r\" < \"\$headers\" | grep -Fq \"Domain=https\"'"
colmena exec --on gateway-vm -- "grep -Fq 'https://homebox.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:7745/api/v1/status' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve kaneo.jax22.com:443:127.0.0.1 https://kaneo.jax22.com/api/health >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: kaneo.h' http://127.0.0.1/api/health >/dev/null"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/kaneo/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'body=\$(mktemp); trap \"rm -f \\\"\$body\\\"\" EXIT; status=\$(curl -sS -o \"\$body\" -w \"%{http_code}\" --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 \"https://auth.jax22.com/application/o/authorize/?client_id=kaneo&redirect_uri=https%3A%2F%2Fkaneo.jax22.com%2Fapi%2Fauth%2Foauth2%2Fcallback%2Fcustom&response_type=code&scope=openid%20profile%20email&state=test&nonce=test\"); case \"\$status\" in 2*|3*) ;; *) echo \"unexpected Kaneo authorize status \$status\" >&2; cat \"\$body\" >&2; exit 1 ;; esac; ! grep -Eiq \"invalid[ _-]*(client|redirect)\" \"\$body\"'"
colmena exec --on gateway-vm -- "grep -Fq 'https://kaneo.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:5173/api/health' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve listmonk.jax22.com:443:127.0.0.1 https://listmonk.jax22.com/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 -H 'Host: listmonk.h' http://127.0.0.1/admin/login | grep -Fq 'Authentik'"
colmena exec --on gateway-vm -- "curl -fsS --max-time 10 --resolve auth.jax22.com:443:127.0.0.1 https://auth.jax22.com/application/o/listmonk/.well-known/openid-configuration | grep -Fq '\"issuer\"'"
colmena exec --on gateway-vm -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 --resolve mailpit.jax22.com:443:127.0.0.1 https://mailpit.jax22.com/api/v1/messages); case \"\$status\" in 30[1278]|401|403) exit 0 ;; *) echo \"unexpected Mailpit auth status \$status\" >&2; exit 1 ;; esac'"
colmena exec --on gateway-vm -- "grep -Fq 'https://mailpit.jax22.com/' /etc/homepage-dashboard/services.yaml"
colmena exec --on gateway-vm -- "grep -Fq 'http://${HOST_IP}:8025/api/v1/messages' /etc/homepage-dashboard/services.yaml"

printf 'testbed-vm validation completed.\n'
