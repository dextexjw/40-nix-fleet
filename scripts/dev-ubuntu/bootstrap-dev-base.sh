#!/usr/bin/env bash
# shellcheck disable=SC2029
set -euo pipefail

TARGET="${TARGET:-smoke@dev.ubuntu.home.arpa}"
MIN_ROOT_GB="${MIN_ROOT_GB:-80}"
SWAP_GB="${SWAP_GB:-16}"
EXPECTED_HOSTNAME="${EXPECTED_HOSTNAME:-dev-ubuntu}"
CODEX_INSTALL_URL="${CODEX_INSTALL_URL:-https://chatgpt.com/codex/install.sh}"
HERMES_INSTALLABLE="${HERMES_INSTALLABLE:-github:NousResearch/hermes-agent#messaging}"

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

printf 'Bootstrapping %s as the fleet Ubuntu development base...\n' "$TARGET"

ssh "${SSH_OPTS[@]}" "$TARGET" \
  "MIN_ROOT_GB='$MIN_ROOT_GB' SWAP_GB='$SWAP_GB' EXPECTED_HOSTNAME='$EXPECTED_HOSTNAME' CODEX_INSTALL_URL='$CODEX_INSTALL_URL' HERMES_INSTALLABLE='$HERMES_INSTALLABLE' bash -s" <<'REMOTE'
set -euo pipefail

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is missing"
}

as_smoke_systemctl() {
  XDG_RUNTIME_DIR="/run/user/$(id -u)" systemctl --user "$@"
}

path_with_nix() {
  export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

ensure_swap() {
  [ "$SWAP_GB" -gt 0 ] || return 0

  current_swap_kb="$(awk '/SwapTotal:/ { print $2 }' /proc/meminfo)"
  desired_swap_kb=$((SWAP_GB * 1024 * 1024))
  if [ "$current_swap_kb" -ge "$desired_swap_kb" ]; then
    printf 'Swap is already at least %s GiB.\n' "$SWAP_GB"
    return 0
  fi

  [ ! -e /swapfile ] || [ -f /swapfile ] || die "/swapfile exists but is not a regular file"

  printf 'Creating %s GiB swapfile for large Nix builds...\n' "$SWAP_GB"
  sudo swapoff /swapfile 2>/dev/null || true
  sudo rm -f /swapfile
  if ! sudo fallocate -l "${SWAP_GB}G" /swapfile; then
    sudo dd if=/dev/zero of=/swapfile bs=1M count="$((SWAP_GB * 1024))" status=progress
  fi
  sudo chmod 0600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile

  if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap[[:space:]]+' /etc/fstab; then
    printf '%s\n' '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
}

path_with_nix

printf 'Checking target identity and OS...\n'
[ "$(id -un)" = "smoke" ] || die "run this as smoke"
[ "$(hostname)" = "$EXPECTED_HOSTNAME" ] || die "expected hostname $EXPECTED_HOSTNAME, got $(hostname)"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || die "expected Ubuntu, got ${ID:-unknown}"
[ "${VERSION_ID:-}" = "26.04" ] || die "expected Ubuntu 26.04, got ${VERSION_ID:-unknown}"
sudo -n true >/dev/null 2>&1 || die "passwordless sudo is required for bootstrap"

printf 'Checking CPU, memory, and disk...\n'
[ "$(nproc)" -ge 2 ] || die "expected at least 2 CPU cores"
awk '/MemTotal:/ { if ($2 < 3900000) exit 1 }' /proc/meminfo || die "expected at least 4 GiB RAM"

disk_bytes="$(lsblk -bnro SIZE /dev/sda | head -n 1)"
min_bytes=$((MIN_ROOT_GB * 1024 * 1024 * 1024))
if [ "$disk_bytes" -lt "$min_bytes" ]; then
  disk_gb=$((disk_bytes / 1024 / 1024 / 1024))
  die "/dev/sda is ${disk_gb} GiB; resize the VM disk to at least ${MIN_ROOT_GB} GiB before running this script"
fi

need growpart
need resize2fs
printf 'Growing root partition and filesystem if needed...\n'
sudo growpart /dev/sda 1 || true
sudo resize2fs /dev/sda1

root_free_kb="$(df -Pk / | awk 'NR == 2 { print $4 }')"
if [ "$root_free_kb" -lt $((20 * 1024 * 1024)) ]; then
  die "expected at least 20 GiB free on / after resize"
fi

printf 'Installing Ubuntu base packages...\n'
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  cloud-guest-utils \
  curl \
  direnv \
  git \
  jq \
  openssh-client \
  ripgrep \
  rsync \
  util-linux

ensure_swap

printf 'Enabling linger for smoke...\n'
sudo loginctl enable-linger smoke

if ! command -v nix >/dev/null 2>&1; then
  printf 'Installing Nix multi-user daemon...\n'
  tmp_install="$(mktemp)"
  curl --fail --location --silent --show-error \
    --retry 5 --retry-delay 5 --retry-max-time 300 \
    --output "$tmp_install" \
    https://nixos.org/nix/install
  sh "$tmp_install" --daemon --yes
  rm -f "$tmp_install"
fi

path_with_nix
if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

need nix

printf 'Configuring Nix daemon features and trusted user...\n'
sudo mkdir -p /etc/nix
sudo touch /etc/nix/nix.conf
sudo sed -i \
  -e '/^experimental-features[[:space:]]*=/d' \
  -e '/^max-jobs[[:space:]]*=/d' \
  -e '/^cores[[:space:]]*=/d' \
  -e '/^trusted-users[[:space:]]*=/d' \
  /etc/nix/nix.conf
{
  printf '%s\n' 'experimental-features = nix-command flakes'
  printf '%s\n' 'max-jobs = 2'
  printf '%s\n' 'cores = 2'
  printf '%s\n' 'trusted-users = root smoke'
} | sudo tee -a /etc/nix/nix.conf >/dev/null
sudo systemctl restart nix-daemon.service

printf 'Installing or updating Codex CLI...\n'
mkdir -p "$HOME/.local/bin" "$HOME/.local/state/codex-auto-update"
codex_installer="$HOME/.local/state/codex-auto-update/install.sh"
curl --fail --location --silent --show-error \
  --retry 5 --retry-delay 10 --retry-max-time 300 --retry-connrefused \
  --connect-timeout 20 --max-time 300 \
  --output "$codex_installer" \
  "$CODEX_INSTALL_URL"
sh -n "$codex_installer"
CODEX_NON_INTERACTIVE=1 sh "$codex_installer"
hash -r

cat >"$HOME/.local/bin/codex-auto-update" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/codex-auto-update"
log_file="$state_dir/update.log"
lock_file="$state_dir/update.lock"
installer="$state_dir/install.sh"
install_url="${CODEX_INSTALL_URL:-https://chatgpt.com/codex/install.sh}"

mkdir -p "$state_dir"

if [ -f "$log_file" ] && [ "$(wc -c <"$log_file")" -gt 1048576 ]; then
  mv -f "$log_file" "$log_file.1"
fi

exec >>"$log_file" 2>&1

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

exec 9>"$lock_file"
if ! flock -n 9; then
  log "another Codex update is already running; exiting"
  exit 0
fi

cleanup() {
  rm -f "$installer"
}
trap cleanup EXIT
trap 'status=$?; log "Codex update failed with exit status $status at line $LINENO"; exit "$status"' ERR

log "starting Codex update"
before="$(codex --version 2>/dev/null || codex --version 2>&1 || true)"
before_path="$(command -v codex || true)"
before_realpath="$([ -n "$before_path" ] && readlink -f "$before_path" || true)"
log "before version: $before"
log "before path: ${before_realpath:-unknown}"
log "installer URL: $install_url"

curl --fail --location --silent --show-error \
  --retry 5 --retry-delay 10 --retry-max-time 300 --retry-connrefused \
  --connect-timeout 20 --max-time 300 \
  --output "$installer" \
  "$install_url"

sh -n "$installer"
CODEX_NON_INTERACTIVE=1 sh "$installer"
hash -r

after="$(codex --version 2>/dev/null || codex --version 2>&1)"
after_path="$(command -v codex)"
after_realpath="$(readlink -f "$after_path")"
log "after version: $after"
log "after path: $after_realpath"

if [ "$before" = "$after" ]; then
  log "Codex is already current"
else
  log "Codex changed from '$before' to '$after'"
fi

log "finished Codex update"
SCRIPT
chmod 0755 "$HOME/.local/bin/codex-auto-update"

mkdir -p "$HOME/.config/systemd/user"
cat >"$HOME/.config/systemd/user/codex-auto-update.service" <<'UNIT'
[Unit]
Description=Update Codex CLI
Documentation=https://developers.openai.com/codex/cli
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/smoke/.local/bin/codex-auto-update
Environment=HOME=/home/smoke
Environment=XDG_STATE_HOME=/home/smoke/.local/state
Environment=PATH=/home/smoke/.local/bin:/home/smoke/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WorkingDirectory=/home/smoke
TimeoutStartSec=15min
UNIT

cat >"$HOME/.config/systemd/user/codex-auto-update.timer" <<'UNIT'
[Unit]
Description=Update Codex CLI daily

[Timer]
OnCalendar=*-*-* 04:15:00
RandomizedDelaySec=2h
Persistent=true
Unit=codex-auto-update.service

[Install]
WantedBy=timers.target
UNIT

printf 'Installing Hermes through the user Nix profile...\n'
if ! nix profile list --json 2>/dev/null | grep -q '"messaging"[[:space:]]*:'; then
  nix profile install --accept-flake-config "$HERMES_INSTALLABLE"
else
  nix build --no-link --accept-flake-config "$HERMES_INSTALLABLE"
fi

cat >"$HOME/.local/bin/hermes-nix-update" <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

export HOME="${HOME:-/home/smoke}"
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

if [[ -f "$HERMES_HOME/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . "$HERMES_HOME/.env"
  set +a
fi

log_dir="$HERMES_HOME/logs"
mkdir -p "$log_dir" "$HOME/.cache"
log_file="$log_dir/hermes-nix-update.log"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" | tee -a "$log_file"
}

notify_gateway_back() {
  local chat_id="${TELEGRAM_HOME_CHANNEL:-8385770769}"
  local token="${TELEGRAM_BOT_TOKEN:-}"
  local version="${after_version:-unknown}"

  if [[ -z "$token" || -z "$chat_id" ]]; then
    log "Gateway-back Telegram notification skipped: TELEGRAM_BOT_TOKEN or TELEGRAM_HOME_CHANNEL is not configured."
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log "Gateway-back Telegram notification skipped: curl not found."
    return 0
  fi

  local text="Hermes gateway is back online after the nightly Nix update. Version: $version"
  if curl --fail --silent --show-error --max-time 15 \
    -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${text}" \
    >/dev/null; then
    log "Sent gateway-back notification to Telegram chat ${chat_id}."
  else
    log "WARNING: failed to send gateway-back Telegram notification."
  fi
}

exec 9>"$HOME/.cache/hermes-nix-update.lock"
if ! flock -n 9; then
  log "Another Hermes Nix update is already running; exiting."
  exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
  log "ERROR: nix command not found in PATH=$PATH"
  exit 127
fi

if ! nix profile list --json 2>/dev/null | grep -q '"messaging"[[:space:]]*:'; then
  log "ERROR: Nix profile item 'messaging' was not found; refusing to guess what to upgrade."
  exit 1
fi

hermes_bin="$HOME/.nix-profile/bin/hermes"
before_store="$(readlink -f "$hermes_bin" 2>/dev/null || true)"
before_version="$($hermes_bin --version 2>/dev/null | head -n 1 || true)"
log "Starting Hermes Nix profile upgrade. before_store=${before_store:-unknown} before_version=${before_version:-unknown}"

upstream_flake="github:NousResearch/hermes-agent"
upstream_installable="$upstream_flake#messaging"
patched_checkout="$HOME/code-cave/hermes-agent-upstream-fix"
selected_installable="$upstream_installable"

log "Pre-building $upstream_installable to verify it is installable."
if nix build "$upstream_installable" --no-link --accept-flake-config 2>&1 | tee -a "$log_file"; then
  log "Upstream pre-build succeeded."
elif [[ -d "$patched_checkout" ]]; then
  selected_installable="path:$patched_checkout#messaging"
  log "Upstream pre-build failed; trying patched checkout at $selected_installable."
  nix build "$selected_installable" --no-link --accept-flake-config 2>&1 | tee -a "$log_file"
  log "Patched checkout pre-build succeeded; replacing profile item through the temporary local installable."
else
  log "ERROR: Upstream pre-build failed and patched checkout is missing at $patched_checkout."
  exit 1
fi

log "Replacing Nix profile item 'messaging' with $selected_installable."
nix profile remove messaging 2>&1 | tee -a "$log_file"
if ! nix profile add --accept-flake-config "$selected_installable" 2>&1 | tee -a "$log_file"; then
  log "ERROR: profile add failed after removing messaging; rolling back to the previous profile generation."
  nix profile rollback 2>&1 | tee -a "$log_file" || true
  exit 1
fi

after_store="$(readlink -f "$hermes_bin" 2>/dev/null || true)"
after_version="$($hermes_bin --version 2>/dev/null | head -n 1 || true)"
log "Finished Nix profile upgrade. after_store=${after_store:-unknown} after_version=${after_version:-unknown}"

if [[ "$before_store" == "$after_store" ]]; then
  log "Hermes profile path unchanged; no gateway reinstall/restart needed."
  exit 0
fi

log "Hermes changed; reinstalling gateway unit so ExecStart points at the new Nix store path."
printf 'y\ny\n' | "$hermes_bin" gateway install --force 2>&1 | tee -a "$log_file"

systemctl --user daemon-reload 2>&1 | tee -a "$log_file" || true

if systemctl --user is-enabled --quiet hermes-gateway.service || systemctl --user is-active --quiet hermes-gateway.service; then
  log "Restarting hermes-gateway.service to run the upgraded Hermes."
  systemctl --user restart hermes-gateway.service 2>&1 | tee -a "$log_file"

  if systemctl --user is-active --quiet hermes-gateway.service; then
    sleep 8
    if systemctl --user is-active --quiet hermes-gateway.service; then
      notify_gateway_back
    else
      log "WARNING: hermes-gateway.service was not active after restart; not sending gateway-back notification."
    fi
  else
    log "WARNING: hermes-gateway.service restart did not leave the service active; not sending gateway-back notification."
  fi
else
  log "hermes-gateway.service is not enabled or active; leaving it stopped."
fi

log "Hermes Nix update complete."
SCRIPT
chmod 0755 "$HOME/.local/bin/hermes-nix-update"

cat >"$HOME/.config/systemd/user/hermes-nix-update.service" <<'UNIT'
[Unit]
Description=Update Hermes Agent from Nix profile
Documentation=https://hermes-agent.nousresearch.com/docs
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/smoke/.local/bin/hermes-nix-update
WorkingDirectory=/home/smoke
Environment=HOME=/home/smoke
Environment=HERMES_HOME=/home/smoke/.hermes
Environment=PATH=/home/smoke/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/home/smoke/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
TimeoutStartSec=2h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT

cat >"$HOME/.config/systemd/user/hermes-nix-update.timer" <<'UNIT'
[Unit]
Description=Nightly Hermes Agent Nix profile update
Documentation=https://hermes-agent.nousresearch.com/docs

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=30m
Persistent=false
Unit=hermes-nix-update.service

[Install]
WantedBy=timers.target
UNIT

as_smoke_systemctl daemon-reload
as_smoke_systemctl enable --now codex-auto-update.timer
as_smoke_systemctl enable --now hermes-nix-update.timer

printf 'Bootstrap verification...\n'
df -h /
nix --version
codex --version
hermes --version | head -n 1
as_smoke_systemctl list-timers codex-auto-update.timer hermes-nix-update.timer --no-pager

printf 'dev-ubuntu base bootstrap completed. Run migrate-from-dev-nix.sh to copy repos and agent state.\n'
REMOTE
