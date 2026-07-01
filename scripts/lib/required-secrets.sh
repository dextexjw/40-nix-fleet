#!/usr/bin/env bash

FLEET_REQUIRED_SECRET_HOSTS=(
  gateway-vm
  gateway2-vm
  media-vm
  monitoring-vm
  productivity-vm
  testbed-vm
)

FLEET_COMMON_REQUIRED_SECRET_KEYS=(
  admin-password-hash
  beszel-agent-key
  beszel-agent-token
  checkmate-capture-environment
)

GATEWAY_REQUIRED_SECRET_KEYS=(
  "${FLEET_COMMON_REQUIRED_SECRET_KEYS[@]}"
  authentik-bootstrap-email
  authentik-bootstrap-password
  authentik-bootstrap-token
  authentik-bootstrap-username
  authentik-postgresql-password
  authentik-secret-key
  affine-oidc-client-secret
  beszel-oidc-client-secret
  bookorbit-oidc-client-secret
  forgejo-oidc-client-secret
  gitea-oidc-client-secret
  gluetun-control-api-key
  gluetun-openvpn-password
  gluetun-openvpn-username
  kaneo-oidc-client-secret
  listmonk-oidc-client-secret
  homebox-oidc-client-secret
  memos-oidc-client-secret
  nextcloud-oidc-client-secret
  paperless-oidc-client-secret
  restic-password
  rustfs-oidc-client-secret
  smb-credentials
  sure-oidc-client-secret
  technitium-admin-password
  technitium-admin-username
  traefik-cloudflare-dns-api-token
)

MEDIA_REQUIRED_SECRET_KEYS=(
  "${FLEET_COMMON_REQUIRED_SECRET_KEYS[@]}"
  bookorbit-admin-username
  bookorbit-admin-password
  bookorbit-email-encryption-key
  bookorbit-jwt-secret
  bookorbit-migration-encryption-key
  bookorbit-oidc-client-secret
  bookorbit-postgres-password
  bookorbit-setup-bootstrap-token
  media-gluetun-control-api-key
  media-gluetun-openvpn-password
  media-gluetun-openvpn-username
  qbittorrent-webui-password
  qbittorrent-webui-username
  restic-password
  smb-credentials
)

MONITORING_REQUIRED_SECRET_KEYS=(
  "${FLEET_COMMON_REQUIRED_SECRET_KEYS[@]}"
  beszel-oidc-client-secret
  checkmate-environment
  checkmate-provisioning-credentials
  restic-password
  smb-credentials
)

PRODUCTIVITY_REQUIRED_SECRET_KEYS=(
  "${FLEET_COMMON_REQUIRED_SECRET_KEYS[@]}"
  affine-environment
  authentik-bootstrap-email
  firefly-admin-password
  firefly-admin-username
  firefly-app-key
  forgejo-oidc-client-secret
  freshrss-admin-password
  freshrss-admin-username
  garage-admin-token
  kaneo-garage-access-key-id
  kaneo-garage-secret-access-key
  garage-metrics-token
  garage-rpc-secret
  gitea-oidc-client-secret
  invoiceplane-db-password
  memos-admin-pat
  memos-oidc-client-secret
  nextcloud-admin-password
  nextcloud-admin-username
  nextcloud-oidc-client-secret
  paperless-admin-password
  paperless-admin-username
  paperless-oidc-client-secret
  plane-garage-access-key-id
  plane-garage-secret-access-key
  restic-password
  rustfs-environment
  rustfs-oidc-client-secret
  searxng-environment
  shlink-environment
  smb-credentials
  syncthing-gui-password
  syncthing-gui-username
  vaultwarden-environment
)

TESTBED_REQUIRED_SECRET_KEYS=(
  "${FLEET_COMMON_REQUIRED_SECRET_KEYS[@]}"
  fizzy-secret-key-base
  homebox-api-key-pepper
  homebox-oidc-client-secret
  kaneo-auth-secret
  kaneo-garage-access-key-id
  kaneo-garage-secret-access-key
  kaneo-oidc-client-secret
  kaneo-postgres-password
  keeper-better-auth-secret
  keeper-encryption-key
  keeper-google-client-id
  keeper-google-client-secret
  keeper-microsoft-client-id
  keeper-microsoft-client-secret
  keeper-postgres-password
  listmonk-admin-password
  listmonk-admin-username
  listmonk-oidc-client-secret
  plane-admin-email
  plane-admin-password
  plane-garage-access-key-id
  plane-garage-secret-access-key
  plane-live-server-secret-key
  plane-postgres-password
  plane-rabbitmq-password
  plane-secret-key
  sure-oidc-client-secret
  sure-postgres-password
  sure-secret-key-base
  restic-password
  smb-credentials
)

TESTBED_KEEPER_OAUTH_SECRET_KEYS=(
  keeper-google-client-id
  keeper-google-client-secret
  keeper-microsoft-client-id
  keeper-microsoft-client-secret
)

required_secret_keys_for_host() {
  local host="$1"

  case "$host" in
    gateway-vm)
      printf '%s\n' "${GATEWAY_REQUIRED_SECRET_KEYS[@]}"
      ;;
    gateway2-vm)
      printf '%s\n' "${GATEWAY_REQUIRED_SECRET_KEYS[@]}"
      ;;
    media-vm)
      printf '%s\n' "${MEDIA_REQUIRED_SECRET_KEYS[@]}"
      ;;
    monitoring-vm)
      printf '%s\n' "${MONITORING_REQUIRED_SECRET_KEYS[@]}"
      ;;
    productivity-vm)
      printf '%s\n' "${PRODUCTIVITY_REQUIRED_SECRET_KEYS[@]}"
      ;;
    testbed-vm)
      printf '%s\n' "${TESTBED_REQUIRED_SECRET_KEYS[@]}"
      ;;
    *)
      printf 'error: unknown host for required secrets: %s\n' "$host" >&2
      return 1
      ;;
  esac
}

all_required_secret_keys() {
  local host key
  declare -A seen=()

  for host in "${FLEET_REQUIRED_SECRET_HOSTS[@]}"; do
    while IFS= read -r key; do
      if [[ -z "${seen[$key]:-}" ]]; then
        seen[$key]=1
        printf '%s\n' "$key"
      fi
    done < <(required_secret_keys_for_host "$host")
  done
}

check_required_secrets_for_host() {
  local host="$1"
  local decrypted_secrets="$2"
  local secrets_file="${3:-secrets/secrets.yaml}"
  local key missing=0

  while IFS= read -r key; do
    if ! grep -q "^${key}:" <<<"$decrypted_secrets"; then
      printf 'error: %s is missing %s\n' "$secrets_file" "$key" >&2
      missing=1
    fi
  done < <(required_secret_keys_for_host "$host")

  return "$missing"
}

check_nonempty_secret_keys() {
  local decrypted_secrets="$1"
  local secrets_file="${2:-secrets/secrets.yaml}"
  shift 2

  local key line value missing=0

  for key in "$@"; do
    line="$(grep -E "^${key}:" <<<"$decrypted_secrets" | head -n 1 || true)"
    value="${line#*:}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ -z "$line" || -z "$value" || "$value" == '""' || "$value" == "''" ]]; then
      printf 'error: %s has empty required secret %s\n' "$secrets_file" "$key" >&2
      missing=1
    fi
  done

  return "$missing"
}

check_testbed_keeper_oauth_secrets() {
  local decrypted_secrets="$1"
  local secrets_file="${2:-secrets/secrets.yaml}"

  check_nonempty_secret_keys "$decrypted_secrets" "$secrets_file" "${TESTBED_KEEPER_OAUTH_SECRET_KEYS[@]}"
}

validate_secret_manifest_files() {
  local root="${1:-$(pwd)}"
  local example="$root/secrets/example-secrets.yaml"
  local sops_config="$root/.sops.yaml"
  local key missing=0

  [[ -f "$example" ]] || {
    printf 'error: missing %s\n' "$example" >&2
    return 1
  }
  [[ -f "$sops_config" ]] || {
    printf 'error: missing %s\n' "$sops_config" >&2
    return 1
  }

  while IFS= read -r key; do
    if ! grep -q "^${key}:" "$example"; then
      printf 'error: %s is missing example key %s\n' "$example" "$key" >&2
      missing=1
    fi
    if ! grep -q "$key" "$sops_config"; then
      printf 'error: %s encrypted_regex is missing %s\n' "$sops_config" "$key" >&2
      missing=1
    fi
  done < <(all_required_secret_keys)

  return "$missing"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail

  command="${1:-}"
  case "$command" in
    list)
      required_secret_keys_for_host "${2:?host is required}"
      ;;
    validate-manifest)
      validate_secret_manifest_files "${2:-$(pwd)}"
      ;;
    *)
      printf 'Usage:\n' >&2
      printf '  %s list <host>\n' "$0" >&2
      printf '  %s validate-manifest [repo-root]\n' "$0" >&2
      exit 2
      ;;
  esac
fi
