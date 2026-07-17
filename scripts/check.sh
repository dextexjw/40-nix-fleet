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
need python3
need rg

cd "$ROOT"

mapfile -t shell_files < <(rg --files -g '*.sh')
mapfile -t nix_files < <(rg --files -g '*.nix')

printf 'Checking shell syntax...\n'
for shell_file in "${shell_files[@]}"; do
  bash -n "$shell_file"
done

printf 'Checking repository-owned fleet agent skill...\n'
python3 tests/validate-fleet-agent-skill.py

printf 'Checking canonical fleet lifecycle command...\n'
python3 tests/test-fleet-lifecycle.py
python3 tests/test-fleet-upgrade-lifecycle.py
python3 tests/test-ci-lifecycle-policy.py

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
nixfmt --check "${nix_files[@]}"

printf 'Checking flake evaluation...\n'
nix flake check

printf 'Checking Colmena host evaluation...\n'
mapfile -t fleet_hosts < <(
  nix eval --json .#colmenaHive.nodes --apply builtins.attrNames \
    | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)))'
)
for host in "${fleet_hosts[@]}"; do
  nix eval ".#colmenaHive.nodes.${host}.config.system.build.toplevel.drvPath" >/dev/null
done

printf 'Checking evaluated deployment image pins...\n'
evaluated_containers="$(mktemp)"
trap 'rm -f "$evaluated_containers"' EXIT
nix eval --json .#colmenaHive.nodes \
  --apply 'nodes: builtins.mapAttrs (_: node: node.config.virtualisation.oci-containers.containers) nodes' \
  >"$evaluated_containers"
scripts/check-deployment-pins.py \
  --evaluated-containers "$evaluated_containers" \
  --exceptions policy/deployment-pin-exceptions.json

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
