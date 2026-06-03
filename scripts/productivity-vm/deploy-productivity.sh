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

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

need colmena
need sops
need ssh
need ssh-to-age

cd "$ROOT"

[[ -f "$SECRETS" ]] || die "missing $SECRETS"

if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
  die "unable to decrypt $SECRETS locally; rekey it for your local/admin key"
fi

for required_key in admin-password-hash beszel-agent-key beszel-agent-token checkmate-capture-environment memos-admin-pat memos-oidc-client-secret restic-password smb-credentials; do
  grep -q "^${required_key}:" <<<"$decrypted_secrets" || die "$SECRETS is missing $required_key"
done

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

if ! target_recipient="$(
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$REMOTE_USER@$HOST_IP" \
    'sudo -n ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' \
    2>/dev/null \
    | ssh-to-age
)"; then
  die "unable to read $HOST SOPS SSH host public key from $HOST_IP"
fi

target_recipient="${target_recipient//$'\r'/}"
target_recipient="${target_recipient//$'\n'/}"

[[ -n "$target_recipient" ]] || die "unable to read $HOST SOPS SSH host public key from $HOST_IP"

if ! grep -Fq "$target_recipient" "$SECRETS"; then
  die "$HOST cannot decrypt $SECRETS; add '$target_recipient' to .sops.yaml, then run: sops updatekeys secrets/secrets.yaml"
fi

colmena apply --on "$HOST" switch
