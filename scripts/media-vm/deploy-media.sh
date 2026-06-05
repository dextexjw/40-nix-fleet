#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="media-vm"
HOST_IP="10.2.20.113"
SECRETS="$ROOT/secrets/secrets.yaml"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"
command -v sops >/dev/null 2>&1 || die "sops is missing; run nix develop first"
command -v ssh >/dev/null 2>&1 || die "ssh is missing"
command -v ssh-to-age >/dev/null 2>&1 || die "ssh-to-age is missing; run nix develop first"

cd "$ROOT"

if [[ ! -f "$SECRETS" ]]; then
  die "missing $SECRETS"
fi

if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
  die "unable to decrypt $SECRETS locally; rekey it for your local/admin key"
fi

check_required_secrets_for_host "$HOST" "$decrypted_secrets" "$SECRETS"

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

if ! target_recipient="$(
  ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "smoke@$HOST_IP" \
    'sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key' \
    2>/dev/null \
    | ssh-to-age
)"; then
  die "unable to read $HOST SOPS SSH host public key from $HOST_IP"
fi

if [[ -z "$target_recipient" ]]; then
  die "unable to read $HOST SOPS SSH host public key from $HOST_IP"
fi

if ! grep -Fq "$target_recipient" "$SECRETS"; then
  die "$HOST cannot decrypt $SECRETS; run: scripts/media-vm/update-media-sops-recipient.sh"
fi

colmena apply --on "$HOST" switch
