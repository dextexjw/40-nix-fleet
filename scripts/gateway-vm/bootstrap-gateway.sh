#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="gateway-vm"
SECRETS="$ROOT/secrets/secrets.yaml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need nix
need sops
need ssh
need ssh-to-age
need colmena

cd "$ROOT"

if [[ ! -f "$SECRETS" ]]; then
  die "missing $SECRETS; copy secrets/example-secrets.yaml, fill it, then encrypt it with sops"
fi

if ! grep -q '^sops:' "$SECRETS"; then
  die "$SECRETS does not look encrypted by sops"
fi

if ! decrypted_secrets="$(sops --decrypt "$SECRETS")"; then
  die "unable to decrypt $SECRETS; rekey it for your local key before bootstrap checks"
fi

for required_key in admin-password-hash gluetun-control-api-key gluetun-openvpn-password gluetun-openvpn-username restic-password smb-credentials technitium-admin-username technitium-admin-password traefik-cloudflare-dns-api-token; do
  grep -q "^${required_key}:" <<<"$decrypted_secrets" || die "$SECRETS is missing $required_key"
done

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

nix flake check
colmena build --on "$HOST"

cat <<MSG
Local readiness checks passed for $HOST.

Next steps:
  1. Confirm non-interactive SSH for smoke works at 10.2.20.112.
  2. Continue with: scripts/gateway-vm/bootstrap-gateway-vm.sh run
MSG
