#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2029
set -euo pipefail

OLD_DEV="${OLD_DEV:-smoke@dev.nix.home.arpa}"
NEW_DEV="${NEW_DEV:-smoke@dev.ubuntu.home.arpa}"
MIN_ROOT_GB="${MIN_ROOT_GB:-80}"
RSYNC_DELETE="${RSYNC_DELETE:-0}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

remote() {
  local target="$1"
  shift
  ssh "${SSH_OPTS[@]}" "$target" "$@"
}

rsync_from_old_to_new() {
  local source="$1"
  local dest="$2"
  shift 2

  ssh "${SSH_OPTS[@]}" "$NEW_DEV" bash -s -- "$OLD_DEV" "$source" "$dest" "$@" <<'REMOTE_RSYNC'
set -euo pipefail
old_dev="$1"
source="$2"
dest="$3"
shift 3

rsync -aH --info=progress2 \
  -e "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
  "$@" \
  "$old_dev:$source" \
  "$dest"
REMOTE_RSYNC
}

printf 'Checking old and new development hosts...\n'
remote "$OLD_DEV" 'test "$(hostname)" = dev && command -v rsync >/dev/null && command -v systemctl >/dev/null'
remote "$NEW_DEV" 'set -eu
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
[ "$(hostname)" = dev-ubuntu ] || {
  printf "expected dev-ubuntu, got %s\n" "$(hostname)" >&2
  exit 1
}
missing=0
for cmd in rsync nix codex hermes; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "missing required command on dev-ubuntu: %s\n" "$cmd" >&2
    missing=1
  fi
done
exit "$missing"
'

remote "$NEW_DEV" "disk_bytes=\$(lsblk -bnro SIZE /dev/sda | head -n 1); min_bytes=\$(( $MIN_ROOT_GB * 1024 * 1024 * 1024 )); [ \"\$disk_bytes\" -ge \"\$min_bytes\" ]" \
  || die "$NEW_DEV has not been resized to at least ${MIN_ROOT_GB} GiB"

printf 'Copying SSH client identity and known-host state from old dev...\n'
remote "$NEW_DEV" 'install -d -m 0700 "$HOME/.ssh"'
remote "$OLD_DEV" 'cd "$HOME/.ssh" && find . -maxdepth 1 -type f \( -name "config" -o -name "id_*" -o -name "known_hosts*" \) -print0 | tar --null -T - -cf -' \
  | remote "$NEW_DEV" 'tar -xf - -C "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 0644 {} +; find "$HOME/.ssh" -type f ! -name "*.pub" -exec chmod 0600 {} +'

printf 'Copying code-cave worktrees from old dev to dev-ubuntu...\n'
delete_args=()
if [ "$RSYNC_DELETE" = "1" ]; then
  delete_args+=(--delete)
fi
remote "$NEW_DEV" 'install -d -m 0755 "$HOME/code-cave"'
rsync_from_old_to_new "/home/smoke/code-cave/" "/home/smoke/code-cave/" "${delete_args[@]}"

printf 'Copying Codex runtime state without package/cache/control directories...\n'
remote "$NEW_DEV" 'install -d -m 0700 "$HOME/.codex"'
rsync_from_old_to_new \
  "/home/smoke/.codex/" \
  "/home/smoke/.codex/" \
  --exclude '/packages/' \
  --exclude '/.tmp/' \
  --exclude '/app-server-control/' \
  --exclude '/shell_snapshots/'
remote "$NEW_DEV" 'install -d -m 0700 "$HOME/.local/state/codex-auto-update"'
rsync_from_old_to_new \
  "/home/smoke/.local/state/codex-auto-update/" \
  "/home/smoke/.local/state/codex-auto-update/" \
  || true

printf 'Taking an initial Hermes state copy while the old gateway is still running...\n'
remote "$NEW_DEV" 'install -d -m 0700 "$HOME/.hermes"'
rsync_from_old_to_new \
  "/home/smoke/.hermes/" \
  "/home/smoke/.hermes/" \
  --exclude '/logs/' \
  --exclude '*.lock' \
  --exclude '*.pid'

printf 'Stopping old Hermes gateway for final state sync...\n'
remote "$OLD_DEV" 'systemctl --user stop hermes-gateway.service || true'

printf 'Taking final Hermes state copy...\n'
rsync_from_old_to_new \
  "/home/smoke/.hermes/" \
  "/home/smoke/.hermes/" \
  --exclude '/logs/' \
  --exclude '*.lock' \
  --exclude '*.pid'

printf 'Regenerating and starting Hermes gateway on dev-ubuntu...\n'
remote "$NEW_DEV" 'set -euo pipefail
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HERMES_HOME="$HOME/.hermes"
printf "y\ny\n" | hermes gateway install --force
systemctl --user daemon-reload
systemctl --user enable --now hermes-gateway.service
sleep 8
systemctl --user is-active --quiet hermes-gateway.service
'

printf 'Disabling old Hermes gateway and updater timer after successful Ubuntu start...\n'
remote "$OLD_DEV" 'systemctl --user disable --now hermes-gateway.service || true; systemctl --user disable --now hermes-nix-update.timer || true'

printf 'Final verification on dev-ubuntu...\n'
remote "$NEW_DEV" 'set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
df -h /
nix --version
codex --version
hermes --version | head -n 1
systemctl --user is-active hermes-gateway.service
systemctl --user list-timers codex-auto-update.timer hermes-nix-update.timer --no-pager
git -C "$HOME/code-cave/40-nix-fleet" status --short --branch
'

printf 'Migration complete. %s is now the primary development base.\n' "$NEW_DEV"
