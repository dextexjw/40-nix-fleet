#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

command -v nix >/dev/null 2>&1 || die "nix is missing"
command -v colmena >/dev/null 2>&1 || die "colmena is missing; run nix develop first"

cd "$ROOT"

nix flake check
colmena build --on media-vm
