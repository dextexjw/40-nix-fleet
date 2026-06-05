#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="media-vm"
SECRETS="$ROOT/secrets/secrets.yaml"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

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

if grep -q 'CHANGE_ME' <<<"$decrypted_secrets"; then
  die "$SECRETS still contains CHANGE_ME placeholders"
fi

check_required_secrets_for_host "$HOST" "$decrypted_secrets" "$SECRETS"

nix flake check
colmena build --on "$HOST"

cat <<MSG
Local readiness checks passed for $HOST.

Next steps:
  1. Run the external nixos-anywhere install flow for the VM.
  2. Ensure non-interactive SSH for smoke works at 10.2.20.113.
  3. Continue with: scripts/media-vm/bootstrap-media-vm.sh run
MSG
