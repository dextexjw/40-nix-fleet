#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="media-vm"
HOST_IP="10.2.20.113"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"
KEY_SERVICES=(
  jellyfin
  audiobookshelf
  kavita
  radarr
  sonarr
  prowlarr
  bazarr
  podman-media-gluetun
  podman-media-qbittorrent
  podman-media-sabnzbd
  podman-media-gluetun-webui
  seerr
  flaresolverr
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  scripts/upgrade-media-vm.sh run
  scripts/upgrade-media-vm.sh check-upgrade-readiness
  scripts/upgrade-media-vm.sh create-pre-upgrade-backup
  scripts/upgrade-media-vm.sh dry-activate-media-vm
  scripts/upgrade-media-vm.sh deploy-media-vm
  scripts/upgrade-media-vm.sh verify-media-vm

This orchestrates a safe media-vm upgrade for the current repo state. It does
not update flake.lock and never restores appdata automatically.
EOF
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
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

ensure_vm_hostname() {
  need ssh

  printf 'Ensuring %s transient hostname matches deployed hostname...\n' "$HOST"
  ssh_media_vm "sudo hostnamectl --transient set-hostname '$HOST'" || die "unable to set transient hostname on $HOST_IP"
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

  if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
    die "$SECRETS still contains CHANGE_ME placeholders"
  fi

  for required_key in admin-password-hash media-gluetun-control-api-key media-gluetun-openvpn-password media-gluetun-openvpn-username qbittorrent-webui-password qbittorrent-webui-username restic-password smb-credentials; do
    grep -q "^$required_key:" <<<"$decrypted_secrets" || die "$SECRETS is missing required key: $required_key"
  done

  confirm_ssh_access

  nix flake check
  colmena build --on "$HOST"

  printf 'Upgrade readiness checks passed for %s.\n' "$HOST"
}

phase_create_pre_upgrade_backup() {
  "$ROOT/scripts/create-media-backup.sh"
}

phase_dry_activate_media_vm() {
  need colmena

  colmena apply --on "$HOST" dry-activate
}

phase_deploy_media_vm() {
  "$ROOT/scripts/deploy-media.sh"
  ensure_vm_hostname
}

phase_verify_media_vm() {
  local hostname_output static_hostname transient_hostname service

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

  "$ROOT/scripts/test-media-backup.sh"

  printf 'Checking systemd-tmpfiles declarations...\n'
  ssh_media_vm "sudo systemd-tmpfiles --create" || die "systemd-tmpfiles check failed on $HOST_IP"

  printf 'Checking key media services...\n'
  for service in "${KEY_SERVICES[@]}"; do
    ssh_media_vm "systemctl is-active --quiet '$service.service'" || die "$service.service is not active"
  done
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
  run_phase dry-activate-media-vm phase_dry_activate_media_vm
  run_phase deploy-media-vm phase_deploy_media_vm
  run_phase verify-media-vm phase_verify_media_vm

  printf '\nmedia-vm upgrade completed.\n'
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
  dry-activate-media-vm)
    shift
    [[ $# -eq 0 ]] || die "dry-activate-media-vm does not accept arguments"
    phase_dry_activate_media_vm
    ;;
  deploy-media-vm)
    shift
    [[ $# -eq 0 ]] || die "deploy-media-vm does not accept arguments"
    phase_deploy_media_vm
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
