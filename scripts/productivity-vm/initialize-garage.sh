#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="productivity-vm"
GARAGE_CAPACITY="20G"
GARAGE_ZONE="productivity"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing; run nix develop first"
}

run_colmena() {
  colmena exec --on "$HOST" -- "$@"
}

extract_node_id() {
  sed -n 's/^.*| //; s/^\([[:xdigit:]]\{16,\}\)@.*$/\1/p' | head -n 1
}

extract_layout_version() {
  sed -n 's/^.*Current cluster layout version: \([0-9][0-9]*\).*$/\1/p' | tail -n 1
}

need colmena

cd "$ROOT"

printf 'Checking Garage cluster layout on %s...\n' "$HOST"
status_output="$(run_colmena garage status 2>&1)"
printf '%s\n' "$status_output"

if ! grep -q 'NO ROLE ASSIGNED' <<<"$status_output"; then
  printf 'Garage already has an assigned layout role on %s.\n' "$HOST"
  exit 0
fi

node_id_output="$(run_colmena garage node id 2>&1)"
node_id="$(extract_node_id <<<"$node_id_output")"
[[ -n "$node_id" ]] || die "unable to discover Garage node ID"

layout_output="$(run_colmena garage layout show 2>&1)"
current_version="$(extract_layout_version <<<"$layout_output")"
[[ -n "$current_version" ]] || die "unable to discover current Garage layout version"
next_version="$((current_version + 1))"

printf 'Assigning Garage node role: zone=%s capacity=%s layout_version=%s\n' "$GARAGE_ZONE" "$GARAGE_CAPACITY" "$next_version"
run_colmena garage layout assign --zone "$GARAGE_ZONE" --capacity "$GARAGE_CAPACITY" "$node_id"
run_colmena garage layout apply --version "$next_version"

printf 'Garage layout after initialization:\n'
run_colmena garage status
