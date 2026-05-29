#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
KEY_SERVICES=(
  postgresql
  gitea
  nginx
  paperless-scheduler
  paperless-task-queue
  paperless-consumer
  paperless-web
  freshrss-config
  phpfpm-freshrss
  searx
  vaultwarden
  phpfpm-privatebin
  syncthing
  stirling-pdf
  phpfpm-firefly-iii
  phpfpm-nextcloud
  garage
  ntfy-sh
)

HOST_ROUTES=(
  gitea.h
  docs.h
  paperless.h
  freshrss.h
  searxng.h
  privatebin.h
  vaultwarden.h
  syncthing.h
  stirling-pdf.h
  firefly.h
  nextcloud.h
  garage.h
  garage-web.h
  ntfy.h
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

printf 'Checking key productivity services...\n'
for service in "${KEY_SERVICES[@]}"; do
  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done

printf 'Checking backup and restore validation...\n'
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start productivity-appdata-backup.service
colmena exec --on "$HOST" -- systemctl start productivity-appdata-restore-check.service
colmena exec --on "$HOST" -- systemctl is-active --quiet productivity-appdata-backup.timer
colmena exec --on "$HOST" -- test -s /srv/appsdata/postgresql-dumps/latest.sql.gz
colmena exec --on "$HOST" -- env \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 3

printf 'Checking direct service listeners and nginx vhosts...\n'
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3000/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8087/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8222/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8384/ >/dev/null"
colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 http://127.0.0.1:8086/); case \"\$status\" in 2*|3*|401) exit 0 ;; *) echo \"unexpected Stirling PDF status: \$status\" >&2; exit 1 ;; esac'"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:2586/v1/health >/dev/null"

printf 'Checking Garage layout and endpoints...\n'
garage_status="$(colmena exec --on "$HOST" -- garage status 2>&1)"
printf '%s\n' "$garage_status"
if grep -q 'NO ROLE ASSIGNED' <<<"$garage_status"; then
  die "Garage node has no assigned layout role; run scripts/productivity-vm/initialize-garage.sh"
fi
colmena exec --on "$HOST" -- garage bucket list >/dev/null

for route in "${HOST_ROUTES[@]}"; do
  case "$route" in
    garage.h)
      colmena exec --on "$HOST" -- "sh -lc 'tmp=\$(mktemp); trap \"rm -f \\\"\$tmp\\\"\" EXIT; status=\$(curl -sS -o \"\$tmp\" -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:3900/); case \"\$status\" in 403) ;; *) echo \"unexpected Garage S3 anonymous status for $route: \$status\" >&2; cat \"\$tmp\" >&2; exit 1 ;; esac; grep -q AccessDenied \"\$tmp\" || { echo \"Garage S3 anonymous response did not contain AccessDenied\" >&2; cat \"\$tmp\" >&2; exit 1; }'"
      ;;
    garage-web.h)
      colmena exec --on "$HOST" -- "sh -lc 'tmp=\$(mktemp); trap \"rm -f \\\"\$tmp\\\"\" EXIT; if ! status=\$(curl -sS -o \"\$tmp\" -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:3902/); then echo \"Garage static web endpoint request failed for $route\" >&2; exit 1; fi; case \"\$status\" in 2*|3*|4*) exit 0 ;; *) echo \"unexpected Garage static web status for $route: \$status\" >&2; cat \"\$tmp\" >&2; exit 1 ;; esac'"
      ;;
    gitea.h)
      colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:3000/ >/dev/null"
      ;;
    ntfy.h)
      colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:2586/v1/health >/dev/null"
      ;;
    searxng.h)
      colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8087/ >/dev/null"
      ;;
    stirling-pdf.h)
      colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:8086/); case \"\$status\" in 2*|3*|401) exit 0 ;; *) echo \"unexpected Stirling PDF status for $route: \$status\" >&2; exit 1 ;; esac'"
      ;;
    syncthing.h)
      colmena exec --on "$HOST" -- "curl -fsSk --max-time 10 -H 'Host: $route' http://127.0.0.1:8384/ >/dev/null"
      ;;
    vaultwarden.h)
      colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8222/ >/dev/null"
      ;;
    *)
      colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1/ >/dev/null"
      ;;
  esac
done

printf 'productivity-vm validation completed.\n'
