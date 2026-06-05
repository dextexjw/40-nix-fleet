#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/required-secrets.sh
source "$ROOT/scripts/lib/required-secrets.sh"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

run_advisory() {
  local label="$1"
  shift

  printf 'Running advisory %s...\n' "$label"
  if "$@"; then
    printf '  %s clean\n' "$label"
  else
    printf '  warning: %s reported issues; not failing yet\n' "$label" >&2
  fi
}

need bash
need nix
need rg

cd "$ROOT"

mapfile -t shell_files < <(rg --files -g '*.sh')
mapfile -t nix_files < <(rg --files -g '*.nix')

printf 'Checking shell syntax...\n'
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

printf 'Checking required secret manifests...\n'
scripts/lib/required-secrets.sh validate-manifest "$ROOT"

printf 'Checking required secrets against host declarations...\n'
for host in "${FLEET_REQUIRED_SECRET_HOSTS[@]}"; do
  diff -u \
    <(required_secret_keys_for_host "$host" | sort) \
    <(
      nix eval --raw ".#colmenaHive.nodes.${host}.config.sops.secrets" \
        --apply 'secrets: builtins.concatStringsSep "\n" (builtins.attrNames secrets)' \
        | sort
    )
done

printf 'Checking Nix formatting...\n'
nix develop --command nixfmt --check "${nix_files[@]}"

printf 'Checking flake evaluation...\n'
nix flake check

printf 'Checking Colmena host evaluation...\n'
for host in "${FLEET_REQUIRED_SECRET_HOSTS[@]}"; do
  nix eval ".#colmenaHive.nodes.${host}.config.system.build.toplevel.drvPath" >/dev/null
done

if command -v shellcheck >/dev/null 2>&1; then
  run_advisory shellcheck shellcheck "${shell_files[@]}"
else
  run_advisory shellcheck nix develop --command shellcheck "${shell_files[@]}"
fi

if command -v statix >/dev/null 2>&1; then
  run_advisory statix statix check .
else
  run_advisory statix nix develop --command statix check .
fi

if command -v deadnix >/dev/null 2>&1; then
  run_advisory deadnix deadnix .
else
  run_advisory deadnix nix develop --command deadnix .
fi

printf 'Repository checks completed.\n'
