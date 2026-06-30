#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="testbed-vm"
HOST_IP="10.2.20.129"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/testbed-vm/upgrade-testbed-vm.sh run
  scripts/testbed-vm/upgrade-testbed-vm.sh check-upgrade-readiness
  scripts/testbed-vm/upgrade-testbed-vm.sh create-pre-upgrade-backup
  scripts/testbed-vm/upgrade-testbed-vm.sh dry-activate-testbed-vm
  scripts/testbed-vm/upgrade-testbed-vm.sh deploy-testbed-vm
  scripts/testbed-vm/upgrade-testbed-vm.sh verify-testbed-vm

This orchestrates a safe testbed-vm upgrade for the current repo state. It
does not update flake.lock and never restores appdata automatically.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

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

confirm_ssh_access() {
  command -v ssh >/dev/null 2>&1 || die "ssh is missing"

  printf 'Confirming non-interactive SSH access to %s@%s...\n' "$REMOTE_USER" "$HOST_IP"
  ssh_testbed_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

ensure_vm_hostname() {
  command -v ssh >/dev/null 2>&1 || die "ssh is missing"

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_testbed_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
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
  "$ROOT/scripts/testbed-vm/create-testbed-backup.sh"
}

phase_dry_activate_testbed_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_testbed_vm() {
  "$ROOT/scripts/testbed-vm/deploy-testbed.sh"
  ensure_vm_hostname
}

phase_verify_testbed_vm() {
  "$ROOT/scripts/testbed-vm/test-testbed-services.sh"
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
  run_phase dry-activate-testbed-vm phase_dry_activate_testbed_vm
  run_phase deploy-testbed-vm phase_deploy_testbed_vm
  run_phase verify-testbed-vm phase_verify_testbed_vm

  printf '\ntestbed-vm upgrade completed.\n'
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
  dry-activate-testbed-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-testbed-vm does not accept arguments"
    phase_dry_activate_testbed_vm
    ;;
  deploy-testbed-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-testbed-vm does not accept arguments"
    phase_deploy_testbed_vm
    ;;
  verify-testbed-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-testbed-vm does not accept arguments"
    phase_verify_testbed_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
