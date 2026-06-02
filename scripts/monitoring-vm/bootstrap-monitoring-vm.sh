#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="monitoring-vm"
HOST_IP="10.2.20.115"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh run [--snapshot-id <id>]
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh check-local-readiness
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh enable-vm-secret-access
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh dry-activate-monitoring-vm
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh deploy-monitoring-vm
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh restore-appdata [snapshot-id]
  scripts/monitoring-vm/bootstrap-monitoring-vm.sh verify-monitoring-vm

This orchestrates the post-install monitoring-vm bootstrap. Run the external
VM install first, then confirm SSH works for ${REMOTE_USER}@${HOST_IP}.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

validate_snapshot_id() {
  local snapshot_id="$1"

  if [[ -n "$snapshot_id" && ! "$snapshot_id" =~ ^[[:xdigit:]]{8,64}$ ]]; then
    die "snapshot id must be 8-64 hexadecimal characters"
  fi
}

ssh_monitoring_vm() {
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
  ssh_monitoring_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

ensure_vm_hostname() {
  command -v ssh >/dev/null 2>&1 || die "ssh is missing"

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_monitoring_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
}

phase_check_local_readiness() {
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

  for required_key in admin-password-hash beszel-agent-key beszel-agent-token checkmate-capture-environment checkmate-environment restic-password smb-credentials; do
    grep -q "^${required_key}:" <<<"$decrypted_secrets" || die "$SECRETS is missing $required_key"
  done

  if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
    die "$SECRETS still contains CHANGE_ME placeholders"
  fi

  nix flake check
  colmena build --on "$HOST"
}

phase_enable_vm_secret_access() {
  "$ROOT/scripts/monitoring-vm/update-monitoring-sops-recipient.sh"
}

phase_dry_activate_monitoring_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_monitoring_vm() {
  "$ROOT/scripts/monitoring-vm/deploy-monitoring.sh"
  ensure_vm_hostname
}

phase_restore_appdata() {
  local snapshot_id="${1:-}"

  validate_snapshot_id "$snapshot_id"

  if [[ -n "$snapshot_id" ]]; then
    "$ROOT/scripts/monitoring-vm/restore-monitoring-appdata.sh" "$snapshot_id"
  else
    "$ROOT/scripts/monitoring-vm/restore-monitoring-appdata.sh"
  fi
}

phase_verify_monitoring_vm() {
  local hostname_output static_hostname transient_hostname

  command -v ssh >/dev/null 2>&1 || die "ssh is missing"

  printf 'Checking %s hostname state...\n' "$HOST"
  if ! hostname_output="$(ssh_monitoring_vm 'hostnamectl --static; hostnamectl --transient')"; then
    die "unable to read hostname state from $HOST_IP"
  fi

  printf '%s\n' "$hostname_output"

  static_hostname="$(printf '%s\n' "$hostname_output" | sed -n '1p')"
  transient_hostname="$(printf '%s\n' "$hostname_output" | sed -n '2p')"

  [[ "$static_hostname" == "$HOST" ]] || die "static hostname is '$static_hostname', expected '$HOST'"
  [[ "$transient_hostname" == "$HOST" ]] || die "transient hostname is '$transient_hostname', expected '$HOST'"

  "$ROOT/scripts/monitoring-vm/test-monitoring-services.sh"
}

run_phase() {
  local name="$1"
  shift

  printf '\n==> %s\n' "$name"
  "$@"
}

run_all() {
  local snapshot_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --snapshot-id)
        [[ $# -ge 2 ]] || die "--snapshot-id requires a value"
        snapshot_id="$2"
        shift 2
        ;;
      --snapshot-id=*)
        snapshot_id="${1#*=}"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown run argument: $1"
        ;;
    esac
  done

  validate_snapshot_id "$snapshot_id"

  run_phase check-local-readiness phase_check_local_readiness
  run_phase confirm-ssh-access confirm_ssh_access
  run_phase enable-vm-secret-access phase_enable_vm_secret_access
  run_phase dry-activate-monitoring-vm phase_dry_activate_monitoring_vm
  run_phase deploy-monitoring-vm phase_deploy_monitoring_vm
  run_phase restore-appdata phase_restore_appdata "$snapshot_id"
  run_phase verify-monitoring-vm phase_verify_monitoring_vm

  printf '\nmonitoring-vm bootstrap completed.\n'
}

cd "$ROOT"

command="${1:-}"
case "$command" in
  run)
    shift
    run_all "$@"
    ;;
  check-local-readiness)
    shift
    [[ $# -eq 0 ]] || die "check-local-readiness does not accept arguments"
    phase_check_local_readiness
    ;;
  enable-vm-secret-access)
    shift
    [[ $# -eq 0 ]] || die "enable-vm-secret-access does not accept arguments"
    phase_enable_vm_secret_access
    ;;
  dry-activate-monitoring-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-monitoring-vm does not accept arguments"
    phase_dry_activate_monitoring_vm
    ;;
  deploy-monitoring-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-monitoring-vm does not accept arguments"
    phase_deploy_monitoring_vm
    ;;
  restore-appdata)
    shift
    [[ $# -le 1 ]] || die "restore-appdata accepts at most one snapshot id"
    phase_restore_appdata "${1:-}"
    ;;
  verify-monitoring-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-monitoring-vm does not accept arguments"
    phase_verify_monitoring_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
