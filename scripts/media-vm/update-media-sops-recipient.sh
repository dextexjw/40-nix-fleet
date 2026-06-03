#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="media-vm"
HOST_IP="10.2.20.113"
REMOTE_USER="smoke"
SOPS_CONFIG="$ROOT/.sops.yaml"
SECRETS="$ROOT/secrets/secrets.yaml"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_dev_shell() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

need_dev_shell sops
need_dev_shell ssh-to-age
command -v ssh >/dev/null 2>&1 || die "ssh is missing"
command -v awk >/dev/null 2>&1 || die "awk is missing"
command -v mktemp >/dev/null 2>&1 || die "mktemp is missing"

cd "$ROOT"

[[ -f "$SOPS_CONFIG" ]] || die "missing $SOPS_CONFIG"
[[ -f "$SECRETS" ]] || die "missing $SECRETS"

printf 'Fetching %s SSH host recipient from %s...\n' "$HOST" "$HOST_IP"

if ! recipient="$(
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
  die "unable to read $HOST SSH host key from $HOST_IP; confirm SSH and passwordless sudo work"
fi

recipient="${recipient//$'\r'/}"
recipient="${recipient//$'\n'/}"

[[ -n "$recipient" ]] || die "empty age recipient returned for $HOST"
[[ "$recipient" == age1* ]] || die "unexpected age recipient: $recipient"

printf 'Recipient: %s\n' "$recipient"

if grep -Fq "$recipient" "$SOPS_CONFIG"; then
  printf '%s already contains the recipient.\n' "$SOPS_CONFIG"
else
  tmp="$(mktemp "$ROOT/.sops.yaml.XXXXXX")"

  if ! awk -v recipient="$recipient" '
    function flush_pending_with_recipient() {
      if (pending != "") {
        sub(/[[:space:]]*$/, ",", pending)
        print pending
      }
      print "      " recipient
      inserted = 1
      pending = ""
    }

    /^[[:space:]]*age:[[:space:]]*>[[:space:]]*$/ {
      print
      in_age = 1
      age_found = 1
      next
    }

    in_age && /^      [^#[:space:]].*$/ {
      if (pending != "") {
        print pending
      }
      pending = $0
      next
    }

    in_age {
      flush_pending_with_recipient()
      in_age = 0
      print
      next
    }

    {
      print
    }

    END {
      if (in_age && !inserted) {
        flush_pending_with_recipient()
      }
      if (!age_found) {
        exit 2
      }
    }
  ' "$SOPS_CONFIG" >"$tmp"; then
    rm -f "$tmp"
    die "unable to update $SOPS_CONFIG"
  fi

  mv "$tmp" "$SOPS_CONFIG"
  printf 'Added recipient to %s.\n' "$SOPS_CONFIG"
fi

printf 'Updating SOPS keys for %s...\n' "$SECRETS"
sops updatekeys --yes "$SECRETS"

printf 'Verifying local SOPS decryption...\n'
sops --decrypt "$SECRETS" >/dev/null

printf 'media-vm SOPS recipient is ready.\n'
