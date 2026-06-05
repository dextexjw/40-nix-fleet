#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="gateway-vm"
HOST_IP="10.2.20.112"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"
REPOSITORY="/mnt/backup/restic/appdata/gateway-vm"
SOURCE="/srv/appsdata"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/gateway-vm/upgrade-gateway-vm.sh run
  scripts/gateway-vm/upgrade-gateway-vm.sh check-upgrade-readiness
  scripts/gateway-vm/upgrade-gateway-vm.sh create-pre-upgrade-backup
  scripts/gateway-vm/upgrade-gateway-vm.sh dry-activate-gateway-vm
  scripts/gateway-vm/upgrade-gateway-vm.sh deploy-gateway-vm
  scripts/gateway-vm/upgrade-gateway-vm.sh verify-gateway-vm

This orchestrates a safe gateway-vm upgrade for the current repo state. It does
not update flake.lock and never restores appdata automatically.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

ssh_gateway_vm() {
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

confirm_ssh_access() {
  need ssh

  printf 'Confirming non-interactive SSH access to %s@%s...\n' "$REMOTE_USER" "$HOST_IP"
  ssh_gateway_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

ensure_vm_hostname() {
  need ssh

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_gateway_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
}

phase_check_upgrade_readiness() {
  local decrypted_secrets

  need nix
  need sops
  need ssh
  need ssh-to-age
  need colmena

  [[ -f "$SECRETS" ]] || die "missing $SECRETS"
  grep -q '^sops:' "$SECRETS" || die "$SECRETS does not look encrypted by sops"

  if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
    die "unable to decrypt $SECRETS; rekey it for your local/admin key"
  fi

  check_required_secrets_for_host "$HOST" "$decrypted_secrets" "$SECRETS"

  if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
    die "$SECRETS still contains CHANGE_ME placeholders"
  fi

  confirm_ssh_access

  nix flake check
  colmena build --on "$HOST"

  printf 'Upgrade readiness checks passed for %s.\n' "$HOST"
}

phase_create_pre_upgrade_backup() {
  need colmena

  colmena exec --on "$HOST" -- "sh -lc 'findmnt -rn --target /mnt/backup >/dev/null || mount /mnt/backup'"
  colmena exec --on "$HOST" -- systemctl start gateway-state-backup.service
  colmena exec --on "$HOST" -- env \
    RESTIC_REPOSITORY="$REPOSITORY" \
    RESTIC_PASSWORD_FILE=/run/secrets/restic-password \
    restic snapshots --host "$HOST" --path "$SOURCE" --tag appsdata --latest 5
}

phase_dry_activate_gateway_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_gateway_vm() {
  "$ROOT/scripts/gateway-vm/deploy-gateway.sh"
  ensure_vm_hostname
}

phase_verify_gateway_vm() {
  "$ROOT/scripts/gateway-vm/test-gateway-services.sh"

  printf 'Checking systemd-tmpfiles declarations...\n'
  ssh_gateway_vm "sudo systemd-tmpfiles --create" || die "systemd-tmpfiles check failed on $HOST_IP"
}

run_phase() {
  local name="$1"
  shift

  printf '\n==> %s\n' "$name"
  "$@"
}

run_all() {
  run_phase check-upgrade-readiness phase_check_upgrade_readiness
  run_phase create-pre-upgrade-backup phase_create_pre_upgrade_backup
  run_phase dry-activate-gateway-vm phase_dry_activate_gateway_vm
  run_phase deploy-gateway-vm phase_deploy_gateway_vm
  run_phase verify-gateway-vm phase_verify_gateway_vm

  printf '\ngateway-vm upgrade completed.\n'
}

cd "$ROOT"

command="${1:-}"
case "$command" in
  run)
    shift
    [[ $# -eq 0 ]] || die "run does not accept arguments"
    run_all
    ;;
  check-upgrade-readiness)
    shift
    [[ $# -eq 0 ]] || die "check-upgrade-readiness does not accept arguments"
    phase_check_upgrade_readiness
    ;;
  create-pre-upgrade-backup)
    shift
    [[ $# -eq 0 ]] || die "create-pre-upgrade-backup does not accept arguments"
    phase_create_pre_upgrade_backup
    ;;
  dry-activate-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-gateway-vm does not accept arguments"
    phase_dry_activate_gateway_vm
    ;;
  deploy-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-gateway-vm does not accept arguments"
    phase_deploy_gateway_vm
    ;;
  verify-gateway-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-gateway-vm does not accept arguments"
    phase_verify_gateway_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
