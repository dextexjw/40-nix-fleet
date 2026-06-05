#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="monitoring-vm"
HOST_IP="10.2.20.115"
REMOTE_USER="smoke"
SECRETS="$ROOT/secrets/secrets.yaml"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

need colmena
need sops
need ssh
need ssh-to-age

cd "$ROOT"

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

[[ -f "$SECRETS" ]] || die "missing $SECRETS"
grep -q '^sops:' "$SECRETS" || die "$SECRETS does not look encrypted by sops"

if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
  die "unable to decrypt $SECRETS locally; rekey it for your local/admin key"
fi

check_required_secrets_for_host "$HOST" "$decrypted_secrets" "$SECRETS"

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

if ! target_recipient="$(
  ssh_monitoring_vm \
    'sudo -n ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' \
    2>/dev/null \
    | ssh-to-age
)"; then
  die "unable to read $HOST SOPS SSH host public key from $HOST_IP"
fi

[[ -n "$target_recipient" ]] || die "unable to read $HOST SOPS SSH host public key from $HOST_IP"

if ! grep -Fq "$target_recipient" "$SECRETS"; then
  die "$HOST cannot decrypt $SECRETS; run: scripts/monitoring-vm/update-monitoring-sops-recipient.sh"
fi

colmena apply --on "$HOST" switch
