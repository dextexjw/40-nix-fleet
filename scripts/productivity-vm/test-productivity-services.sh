#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
REPOSITORY="/mnt/backups/restic/appdata/productivity-vm"
SOURCE="/srv/appsdata"
ALLOW_MISSING_NEW_SERVICES=0
SERVICE_DOMAINS=(
  jax22.com
  h
)
KEY_SERVICES=(
  postgresql
  gitea
  forgejo
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
  podman-openspeedtest
  phpfpm-invoiceplane
  mysql
  iperf3
  podman-memos
  rustdesk-signal
  rustdesk-relay
  garage
  podman-shlink
  podman-shlink-web
  podman-rustfs
  ntfy-sh
)

HOST_ROUTES=(
  gitea
  forgejo
  docs
  paperless
  freshrss
  searxng
  privatebin
  vaultwarden
  syncthing
  stirling-pdf
  firefly
  nextcloud
  openspeedtest
  invoiceplane
  memos
  garage
  garage-web
  rustfs
  rustfs-console
  s
  shlink
  ntfy
)

declare -A OPTIONAL_FIRST_DEPLOY_SERVICE=(
  [forgejo]=1
  [iperf3]=1
  [podman-openspeedtest]=1
  [mysql]=1
  [phpfpm-invoiceplane]=1
  [podman-memos]=1
  [podman-shlink]=1
  [podman-shlink-web]=1
  [podman-rustfs]=1
  [rustdesk-relay]=1
  [rustdesk-signal]=1
)
declare -A SKIPPED_SERVICE=()

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/productivity-vm/test-productivity-services.sh [--allow-missing-new-services]
EOF
}

case "${1:-}" in
  --allow-missing-new-services)
    ALLOW_MISSING_NEW_SERVICES=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
esac
[[ $# -eq 0 ]] || die "unknown argument: $1"

service_unit_exists() {
  local service="$1"

  colmena exec --on "$HOST" -- "systemctl cat '$service.service' >/dev/null 2>&1" >/dev/null 2>&1
}

service_is_skipped() {
  local service="$1"

  [[ "${SKIPPED_SERVICE[$service]:-0}" == 1 ]]
}

route_is_skipped() {
  local route="$1"

  case "$route" in
    forgejo.*)
      service_is_skipped forgejo
      ;;
    invoiceplane.*)
      service_is_skipped phpfpm-invoiceplane
      ;;
    openspeedtest.*)
      service_is_skipped podman-openspeedtest
      ;;
    memos.*)
      service_is_skipped podman-memos
      ;;
    rustfs.* | rustfs-console.*)
      service_is_skipped podman-rustfs
      ;;
    s.*)
      service_is_skipped podman-shlink
      ;;
    shlink.*)
      service_is_skipped podman-shlink-web
      ;;
    *)
      return 1
      ;;
  esac
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

printf 'Checking key productivity services...\n'
for service in "${KEY_SERVICES[@]}"; do
  if (( ALLOW_MISSING_NEW_SERVICES )) \
    && [[ "${OPTIONAL_FIRST_DEPLOY_SERVICE[$service]:-0}" == 1 ]] \
    && ! service_unit_exists "$service"; then
    printf 'Skipping %s.service because it is not deployed yet.\n' "$service"
    SKIPPED_SERVICE[$service]=1
    continue
  fi

  colmena exec --on "$HOST" -- systemctl is-active --quiet "$service.service"
done

printf 'Checking backup and restore validation...\n'
colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backups >/dev/null || mount /mnt/backups'"
colmena exec --on "$HOST" -- systemctl start productivity-appdata-backup.service
colmena exec --on "$HOST" -- systemctl start productivity-appdata-restore-check.service
colmena exec --on "$HOST" -- systemctl is-active --quiet productivity-appdata-backup.timer
colmena exec --on "$HOST" -- test -s /srv/appsdata/postgresql-dumps/latest.sql.gz
if ! service_is_skipped mysql; then
  colmena exec --on "$HOST" -- test -s /srv/appsdata/mariadb-dumps/latest.sql.gz
fi
colmena exec --on "$HOST" -- env \
  RESTIC_REPOSITORY="$REPOSITORY" \
  RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
  restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 3

printf 'Checking direct service listeners and nginx vhosts...\n'
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3000/ >/dev/null"
if ! service_is_skipped forgejo; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:3002/ >/dev/null"
fi
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8087/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8222/ >/dev/null"
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8384/ >/dev/null"
colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 http://127.0.0.1:8086/); case \"\$status\" in 2*|3*|401) exit 0 ;; *) echo \"unexpected Stirling PDF status: \$status\" >&2; exit 1 ;; esac'"
if ! service_is_skipped podman-openspeedtest; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8989/ >/dev/null"
fi
if ! service_is_skipped phpfpm-invoiceplane; then
  colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 -H \"Host: invoiceplane.jax22.com\" http://127.0.0.1/); case \"\$status\" in 2*|3*) exit 0 ;; *) echo \"unexpected InvoicePlane status: \$status\" >&2; exit 1 ;; esac'"
fi
if ! service_is_skipped iperf3; then
  colmena exec --on "$HOST" -- "iperf3 -c 127.0.0.1 -p 5201 -t 1 >/dev/null"
fi
if ! service_is_skipped podman-memos; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:5230/ >/dev/null"
  colmena exec --on "$HOST" -- "sh -lc 'if [ -s /srv/appsdata/memos/memos_prod.db ]; then test -s /srv/appsdata/memos-backups/latest.db; fi'"
fi
if ! service_is_skipped rustdesk-signal && ! service_is_skipped rustdesk-relay; then
  colmena exec --on "$HOST" -- "test -s /srv/appsdata/rustdesk/id_ed25519.pub"
  for port in 21115 21116 21117 21118 21119; do
    colmena exec --on "$HOST" -- "sudo ss -ltn '( sport = :$port )' | grep -q ':$port'"
  done
  colmena exec --on "$HOST" -- "sudo ss -lun '( sport = :21116 )' | grep -q ':21116'"
fi
if ! service_is_skipped podman-rustfs; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:9000/health >/dev/null"
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:9001/rustfs/console/health >/dev/null"
fi
if ! service_is_skipped podman-shlink; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8088/rest/health >/dev/null"
fi
if ! service_is_skipped podman-shlink-web; then
  colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:8089/ >/dev/null"
fi
colmena exec --on "$HOST" -- "curl -fsS --max-time 10 http://127.0.0.1:2586/v1/health >/dev/null"

printf 'Checking Garage layout and endpoints...\n'
garage_status="$(colmena exec --on "$HOST" -- garage status 2>&1)"
printf '%s\n' "$garage_status"
if grep -q 'NO ROLE ASSIGNED' <<<"$garage_status"; then
  die "Garage node has no assigned layout role; run scripts/productivity-vm/initialize-garage.sh"
fi
colmena exec --on "$HOST" -- garage bucket list >/dev/null

for route_prefix in "${HOST_ROUTES[@]}"; do
  for domain in "${SERVICE_DOMAINS[@]}"; do
    route="${route_prefix}.${domain}"

    if route_is_skipped "$route"; then
      printf 'Skipping %s route because its service is not deployed yet.\n' "$route"
      continue
    fi

    case "$route" in
      garage.*)
        colmena exec --on "$HOST" -- "sh -lc 'tmp=\$(mktemp); trap \"rm -f \\\"\$tmp\\\"\" EXIT; status=\$(curl -sS -o \"\$tmp\" -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:3900/); case \"\$status\" in 403) ;; *) echo \"unexpected Garage S3 anonymous status for $route: \$status\" >&2; cat \"\$tmp\" >&2; exit 1 ;; esac; grep -q AccessDenied \"\$tmp\" || { echo \"Garage S3 anonymous response did not contain AccessDenied\" >&2; cat \"\$tmp\" >&2; exit 1; }'"
        ;;
      garage-web.*)
        colmena exec --on "$HOST" -- "sh -lc 'tmp=\$(mktemp); trap \"rm -f \\\"\$tmp\\\"\" EXIT; if ! status=\$(curl -sS -o \"\$tmp\" -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:3902/); then echo \"Garage static web endpoint request failed for $route\" >&2; exit 1; fi; case \"\$status\" in 2*|3*|4*) exit 0 ;; *) echo \"unexpected Garage static web status for $route: \$status\" >&2; cat \"\$tmp\" >&2; exit 1 ;; esac'"
        ;;
      gitea.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:3000/ >/dev/null"
        ;;
      forgejo.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:3002/ >/dev/null"
        ;;
      ntfy.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:2586/v1/health >/dev/null"
        ;;
      openspeedtest.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8989/ >/dev/null"
        ;;
      invoiceplane.*)
        colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1/); case \"\$status\" in 2*|3*) exit 0 ;; *) echo \"unexpected InvoicePlane status for $route: \$status\" >&2; exit 1 ;; esac'"
        ;;
      memos.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:5230/ >/dev/null"
        ;;
      rustfs.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:9000/health >/dev/null"
        ;;
      rustfs-console.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:9001/rustfs/console/health >/dev/null"
        ;;
      s.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8088/rest/health >/dev/null"
        ;;
      searxng.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8087/ >/dev/null"
        ;;
      shlink.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8089/ >/dev/null"
        ;;
      stirling-pdf.*)
        colmena exec --on "$HOST" -- "sh -lc 'status=\$(curl -sS -o /dev/null -w \"%{http_code}\" --max-time 10 -H \"Host: $route\" http://127.0.0.1:8086/); case \"\$status\" in 2*|3*|401) exit 0 ;; *) echo \"unexpected Stirling PDF status for $route: \$status\" >&2; exit 1 ;; esac'"
        ;;
      syncthing.*)
        colmena exec --on "$HOST" -- "curl -fsSk --max-time 10 -H 'Host: $route' http://127.0.0.1:8384/ >/dev/null"
        ;;
      vaultwarden.*)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1:8222/ >/dev/null"
        ;;
      *)
        colmena exec --on "$HOST" -- "curl -fsS --max-time 10 -H 'Host: $route' http://127.0.0.1/ >/dev/null"
        ;;
    esac
  done
done

printf 'productivity-vm validation completed.\n'
