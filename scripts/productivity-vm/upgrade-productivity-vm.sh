#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
HOST_IP="10.2.20.114"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/productivity-vm/upgrade-productivity-vm.sh run
  scripts/productivity-vm/upgrade-productivity-vm.sh check-upgrade-readiness
  scripts/productivity-vm/upgrade-productivity-vm.sh create-pre-upgrade-backup
  scripts/productivity-vm/upgrade-productivity-vm.sh dry-activate-productivity-vm
  scripts/productivity-vm/upgrade-productivity-vm.sh deploy-productivity-vm
  scripts/productivity-vm/upgrade-productivity-vm.sh initialize-garage
  scripts/productivity-vm/upgrade-productivity-vm.sh verify-productivity-vm

This orchestrates a safe productivity-vm upgrade for the current repo state. It
does not update flake.lock and never restores appdata automatically.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

ssh_productivity_vm() {
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
  ssh_productivity_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

ensure_vm_hostname() {
  command -v ssh >/dev/null 2>&1 || die "ssh is missing"

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_productivity_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
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

  for required_key in admin-password-hash beszel-agent-key beszel-agent-token checkmate-capture-environment freshrss-admin-password memos-admin-pat memos-oidc-client-secret nextcloud-admin-password paperless-admin-password restic-password rustfs-environment rustfs-oidc-client-secret smb-credentials; do
    grep -q "^${required_key}:" <<<"$decrypted_secrets" || die "$SECRETS is missing $required_key"
  done

  if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
    die "$SECRETS still contains CHANGE_ME placeholders"
  fi

  confirm_ssh_access

  nix flake check
  colmena build --on "$HOST"

  printf 'Upgrade readiness checks passed for %s.\n' "$HOST"
}

phase_create_pre_upgrade_backup() {
  "$ROOT/scripts/productivity-vm/create-productivity-backup.sh"
}

phase_dry_activate_productivity_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_productivity_vm() {
  "$ROOT/scripts/productivity-vm/deploy-productivity.sh"
  ensure_vm_hostname
}

phase_initialize_garage() {
  "$ROOT/scripts/productivity-vm/initialize-garage.sh"
}

phase_verify_productivity_vm() {
  "$ROOT/scripts/productivity-vm/test-productivity-services.sh"
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
  run_phase dry-activate-productivity-vm phase_dry_activate_productivity_vm
  run_phase deploy-productivity-vm phase_deploy_productivity_vm
  run_phase initialize-garage phase_initialize_garage
  run_phase verify-productivity-vm phase_verify_productivity_vm

  printf '\nproductivity-vm upgrade completed.\n'
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
  dry-activate-productivity-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-productivity-vm does not accept arguments"
    phase_dry_activate_productivity_vm
    ;;
  deploy-productivity-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-productivity-vm does not accept arguments"
    phase_deploy_productivity_vm
    ;;
  initialize-garage)
    shift
    [[ $# -eq 0 ]] || die "initialize-garage does not accept arguments"
    phase_initialize_garage
    ;;
  verify-productivity-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-productivity-vm does not accept arguments"
    phase_verify_productivity_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
