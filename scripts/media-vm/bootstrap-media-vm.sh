#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="media-vm"
HOST_IP="10.2.20.113"
REMOTE_USER="smoke"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/media-vm/bootstrap-media-vm.sh run [--snapshot-id <id>]
  scripts/media-vm/bootstrap-media-vm.sh check-local-readiness
  scripts/media-vm/bootstrap-media-vm.sh enable-vm-secret-access
  scripts/media-vm/bootstrap-media-vm.sh deploy-media-vm
  scripts/media-vm/bootstrap-media-vm.sh restore-appdata [snapshot-id]
  scripts/media-vm/bootstrap-media-vm.sh verify-media-vm

This orchestrates the post-install media-vm bootstrap. Run the external
nixos-anywhere install first, then confirm SSH works for ${REMOTE_USER}@${HOST_IP}.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

validate_snapshot_id() {
  local snapshot_id="$1"

  if [[ -n "$snapshot_id" && ! "$snapshot_id" =~ ^[[:xdigit:]]{8,64}$ ]]; then
    die "snapshot id must be 8-64 hexadecimal characters"
  fi
}

ssh_media_vm() {
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
  ssh_media_vm true || die "unable to reach $REMOTE_USER@$HOST_IP with non-interactive SSH"
}

phase_check_local_readiness() {
  "$ROOT/scripts/media-vm/bootstrap-media.sh"
}

phase_enable_vm_secret_access() {
  "$ROOT/scripts/media-vm/update-media-sops-recipient.sh"
}

phase_deploy_media_vm() {
  "$ROOT/scripts/media-vm/deploy-media.sh"
  ensure_vm_hostname
}

phase_restore_appdata() {
  local snapshot_id="${1:-}"

  validate_snapshot_id "$snapshot_id"

  if [[ -n "$snapshot_id" ]]; then
    "$ROOT/scripts/media-vm/restore-media-appdata.sh" "$snapshot_id"
  else
    "$ROOT/scripts/media-vm/restore-media-appdata.sh"
  fi
}

ensure_vm_hostname() {
  need ssh

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_media_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
}

phase_verify_media_vm() {
  local hostname_output static_hostname transient_hostname

  need ssh

  printf 'Checking %s hostname state...\n' "$HOST"
  if ! hostname_output="$(ssh_media_vm 'hostnamectl --static; hostnamectl --transient')"; then
    die "unable to read hostname state from $HOST_IP"
  fi

  printf '%s\n' "$hostname_output"

  static_hostname="$(printf '%s\n' "$hostname_output" | sed -n '1p')"
  transient_hostname="$(printf '%s\n' "$hostname_output" | sed -n '2p')"

  [[ "$static_hostname" == "$HOST" ]] || die "static hostname is '$static_hostname', expected '$HOST'"
  [[ "$transient_hostname" == "$HOST" ]] || die "transient hostname is '$transient_hostname', expected '$HOST'"

  "$ROOT/scripts/media-vm/test-media-backup.sh"
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
  run_phase deploy-media-vm phase_deploy_media_vm
  run_phase restore-appdata phase_restore_appdata "$snapshot_id"
  run_phase verify-media-vm phase_verify_media_vm

  printf '\nmedia-vm bootstrap completed.\n'
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
  deploy-media-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-media-vm does not accept arguments"
    phase_deploy_media_vm
    ;;
  restore-appdata)
    shift
    [[ $# -le 1 ]] || die "restore-appdata accepts at most one snapshot id"
    phase_restore_appdata "${1:-}"
    ;;
  verify-media-vm)
    shift
    [[ $# -eq 0 ]] || die "verify-media-vm does not accept arguments"
    phase_verify_media_vm
    ;;
  -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    die "unknown command: $command"
    ;;
esac
