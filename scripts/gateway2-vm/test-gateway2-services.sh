#!/usr/bin/env bash
set -euo pipefail

HOST="gateway2-vm"
HOST_IP="10.2.20.122"
VIP_IP="10.2.20.102"
REMOTE_USER="smoke"
EXPOSURE_SMOKE_FILE="/etc/fleet/gateway-exposure-smoke.tsv"
EXTERNAL_TCP_PORTS=(22 25 53 80 443 853 5201 5380 8080 8082 8888 21115 21116 21117 21118 21119 53443)
LOCAL_TCP_PORTS=(3000 5432 6379 9000 9300)
UDP_PORTS=(53 5201 21116 41641)
KEY_UNITS=(
  traefik.service
  authentik-server.service
  authentik-worker.service
  homepage-dashboard.service
  postgresql.service
  redis-authentik.service
  technitium-dns-server.service
  podman-gluetun.service
  podman-gluetun-webui.service
  tailscaled.service
  keepalived.service
  gateway-state-backup.timer
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

wait_for_remote() {
  local description="$1"
  local command="$2"

  for attempt in {1..60}; do
    if ssh_gateway_vm "$command"; then
      return 0
    fi

    if [[ "$attempt" == 60 ]]; then
      die "$description"
    fi

    sleep 1
  done
}

ssh_gateway_vm() {
  ssh \
    -n \
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

unit_file_exists() {
  local unit="$1"

  ssh_gateway_vm "systemctl list-unit-files '$unit' --no-legend 2>/dev/null | awk '{ print \$1 }' | grep -Fxq '$unit'"
}

skip_for_missing_unit() {
  local required_unit="$1"
  local label="$2"

  if [[ -n "$required_unit" ]] && ! unit_file_exists "$required_unit"; then
    printf '  skipping %s; %s is not installed\n' "$label" "$required_unit"
    return 0
  fi

  return 1
}

need ssh
need dig

printf 'Checking %s hostname state...\n' "$HOST"
hostname_output="$(ssh_gateway_vm 'hostnamectl --static; hostnamectl --transient')" || die "unable to read hostname state"
printf '%s\n' "$hostname_output"

static_hostname="$(printf '%s\n' "$hostname_output" | sed -n '1p')"
transient_hostname="$(printf '%s\n' "$hostname_output" | sed -n '2p')"

[[ "$static_hostname" == "$HOST" ]] || die "static hostname is '$static_hostname', expected '$HOST'"
[[ "$transient_hostname" == "$HOST" ]] || die "transient hostname is '$transient_hostname', expected '$HOST'"

CHECK_NETBIRD=0
if ssh_gateway_vm "systemctl list-unit-files 'netbird.service' --no-legend 2>/dev/null | grep -q '^netbird[.]service'"; then
  CHECK_NETBIRD=1
  KEY_UNITS+=(netbird.service)
fi

printf 'Checking gateway units...\n'
for unit in "${KEY_UNITS[@]}"; do
  wait_for_remote "$unit is not active" "systemctl is-active --quiet '$unit'"
  printf '  %s active\n' "$unit"
done

printf 'Checking externally exposed TCP listeners...\n'
for port in "${EXTERNAL_TCP_PORTS[@]}"; do
  wait_for_remote "TCP $port is not externally listening" "sudo ss -ltn '( sport = :$port )' | grep -Eq '([[:space:]]|^)(${HOST_IP}|0[.]0[.]0[.]0|\\*|\\[::\\]):$port'"
  printf '  tcp/%s listening\n' "$port"
done

printf 'Checking local-only TCP listeners...\n'
for port in "${LOCAL_TCP_PORTS[@]}"; do
  wait_for_remote "TCP $port is not listening on localhost" "sudo ss -ltn '( sport = :$port )' | grep -Eq '([[:space:]]|^)(127[.]0[.]0[.]1|\\[::1\\]):$port'"
  wait_for_remote "TCP $port is exposed on the LAN address" "! sudo ss -ltn '( sport = :$port )' | grep -Eq '([[:space:]]|^)(${HOST_IP}|0[.]0[.]0[.]0|\\*|\\[::\\]):$port'"
  printf '  localhost tcp/%s listening\n' "$port"
done

printf 'Checking listening UDP ports...\n'
for port in "${UDP_PORTS[@]}"; do
  wait_for_remote "UDP $port is not listening" "sudo ss -lun '( sport = :$port )' | grep -q ':$port'"
  printf '  udp/%s listening\n' "$port"
done

if [[ "$CHECK_NETBIRD" == 1 ]]; then
  printf 'Checking NetBird WireGuard configuration...\n'
  wait_for_remote "NetBird WireGuard port is not configured" \
    "sudo grep -Eq '\"WgPort\"[[:space:]]*:[[:space:]]*51820' /var/lib/netbird/config.json"
  printf '  netbird WgPort configured for udp/51820\n'
else
  printf 'Skipping NetBird checks; netbird.service is not installed on %s\n' "$HOST"
fi

check_dns_record() {
  local name="$1"
  local expected_ip="$2"

  for attempt in {1..60}; do
    if dig @"$HOST_IP" "$name" +short | grep -Fxq "$expected_ip"; then
      printf '  %s resolves to %s\n' "$name" "$expected_ip"
      return 0
    fi

    if [[ "$attempt" == 60 ]]; then
      die "$name does not resolve to $expected_ip through gateway DNS"
    fi

    sleep 1
  done
}

run_exposure_smoke_checks() {
  wait_for_remote "Gateway exposure smoke catalog is missing" "test -s '$EXPOSURE_SMOKE_FILE'"

  while IFS=$'\t' read -r kind label arg1 arg2 arg3 _rest; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue

    case "$kind" in
      dns)
        if skip_for_missing_unit "$arg2" "$label"; then
          continue
        fi
        check_dns_record "$label" "$arg1"
        ;;
      http)
        if skip_for_missing_unit "$arg2" "$label"; then
          continue
        fi
        wait_for_remote "$label failed" "$arg1"
        printf '  %s ok\n' "$label"
        ;;
      homepage)
        if skip_for_missing_unit "$arg3" "$label"; then
          continue
        fi
        wait_for_remote "$label missing from Homepage generated config" "grep -Fq '$arg2' '$arg1'"
        printf '  %s found\n' "$label"
        ;;
      tcp)
        if skip_for_missing_unit "$arg2" "$label"; then
          continue
        fi
        wait_for_remote "$label TCP port $arg1 is not listening" "sudo ss -ltn '( sport = :$arg1 )' | grep -q ':$arg1'"
        printf '  %s tcp/%s listening\n' "$label" "$arg1"
        ;;
      udp)
        if skip_for_missing_unit "$arg2" "$label"; then
          continue
        fi
        wait_for_remote "$label UDP port $arg1 is not listening" "sudo ss -lun '( sport = :$arg1 )' | grep -q ':$arg1'"
        printf '  %s udp/%s listening\n' "$label" "$arg1"
        ;;
      *)
        die "unknown exposure smoke row kind '$kind' for '$label'"
        ;;
    esac
  done < <(ssh_gateway_vm "cat '$EXPOSURE_SMOKE_FILE'")
}

printf 'Checking generated Gateway exposure DNS, routes, and Homepage cards...\n'
run_exposure_smoke_checks

printf 'Checking Gateway HA declaration...\n'
wait_for_remote "Gateway HA declaration missing VIP" "grep -Fq '\"vip\":\"${VIP_IP}\"' /etc/fleet/gateway-ha.json"
printf '  keepalived VIP declaration points to %s\n' "$VIP_IP"

printf 'Checking Gateway-local direct HTTP endpoints...\n'
wait_for_remote "Traefik dashboard route failed" "curl -fsS http://127.0.0.1:8080/dashboard/ >/dev/null"
wait_for_remote "Traefik metrics endpoint failed" "tmp=\$(mktemp); trap 'rm -f \"\$tmp\"' EXIT; curl -fsS -o \"\$tmp\" http://127.0.0.1:8080/metrics && grep -q '^traefik_' \"\$tmp\""
wait_for_remote "Authentik readiness endpoint failed" "curl -fsS http://127.0.0.1:9000/-/health/ready/ >/dev/null"
wait_for_remote "Authentik provisioning did not complete successfully" "systemctl show authentik-provision.service -p Result -p ExecMainStatus | grep -Fxq Result=success && systemctl show authentik-provision.service -p Result -p ExecMainStatus | grep -Fxq ExecMainStatus=0"
wait_for_remote "Homepage direct endpoint failed" "curl -fsS http://${HOST_IP}:8082/ >/dev/null"

printf 'Checking Traefik ACME storage...\n'
wait_for_remote "Traefik ACME storage is missing or empty" "sudo test -s /var/lib/traefik/acme.json"
wait_for_remote "Traefik ACME storage ownership or permissions are incorrect" "sudo stat -c '%U:%G %a' /var/lib/traefik/acme.json | grep -Fxq 'traefik:traefik 600'"

printf 'Checking static Homepage bookmark config...\n'
homepage_checks="grep -Fq 'Links:' /etc/homepage-dashboard/settings.yaml"
homepage_checks="$homepage_checks && grep -Fq 'columns: 3' /etc/homepage-dashboard/settings.yaml"
homepage_checks="$homepage_checks && ! grep -Fq 'iconsOnly: true' /etc/homepage-dashboard/settings.yaml"
homepage_checks="$homepage_checks && grep -Fq 'TorrentPeek' /etc/homepage-dashboard/bookmarks.yaml"
homepage_checks="$homepage_checks && grep -Fq 'https://github.com/' /etc/homepage-dashboard/bookmarks.yaml"
wait_for_remote "Homepage generated bookmark config is missing expected links" "$homepage_checks"

printf 'Checking Gluetun LAN HTTP proxy...\n'
wait_for_remote "Gluetun HTTP proxy failed" "curl -fsS --proxy http://${HOST_IP}:8888 https://ipinfo.io/ip >/dev/null"

printf 'Checking Gluetun WebUI direct backend health...\n'
wait_for_remote "Gluetun WebUI direct backend health failed" "curl -fsS http://127.0.0.1:3000/api/health >/dev/null"

printf 'Running gateway state backup and restore validation...\n'
ssh_gateway_vm "sudo systemctl start gateway-state-backup.service" || die "gateway-state-backup.service failed"
ssh_gateway_vm "sudo systemctl start gateway-state-restore-check.service" || die "gateway-state-restore-check.service failed"

printf 'gateway2-vm validation completed.\n'
