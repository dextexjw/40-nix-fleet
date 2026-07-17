#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="operate-40-nix-fleet"
REPO_SKILL="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="check"

while (( $# > 0 )); do
  case "$1" in
    --check | --install)
      MODE="${1#--}"
      shift
      ;;
    --repo-skill)
      [[ $# -ge 2 ]] || {
        printf 'error: --repo-skill requires a path\n' >&2
        exit 2
      }
      REPO_SKILL="$(cd -- "$2" && pwd)"
      shift 2
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
USER_SKILL="$CODEX_HOME/skills/$SKILL_NAME"

if [[ -L "$USER_SKILL" ]] && [[ "$(readlink -f -- "$USER_SKILL")" == "$REPO_SKILL" ]]; then
  printf 'User skill path links to the repository package.\n'
  exit 0
fi

if [[ "$MODE" == "check" ]]; then
  if [[ -e "$USER_SKILL" || -L "$USER_SKILL" ]]; then
    printf 'error: ambiguous user-scoped skill exists at %s\n' "$USER_SKILL" >&2
    printf 'Run this command with --install to preserve it outside discovery and create one canonical link.\n' >&2
    exit 1
  fi
  printf 'No duplicate user-scoped skill found.\n'
  exit 0
fi

mkdir -p -- "$CODEX_HOME/skills" "$CODEX_HOME/skill-backups"
if [[ -e "$USER_SKILL" || -L "$USER_SKILL" ]]; then
  BACKUP="$CODEX_HOME/skill-backups/$SKILL_NAME-$(date -u +%Y%m%dT%H%M%SZ)"
  mv -- "$USER_SKILL" "$BACKUP"
  printf 'Preserved previous user-scoped copy at %s\n' "$BACKUP"
fi
ln -s -- "$REPO_SKILL" "$USER_SKILL"
printf 'Linked %s to %s\n' "$USER_SKILL" "$REPO_SKILL"
