#!/usr/bin/env bash
# Client Mac mini deployment installer
# Companion to: bootstrap.sh / Brewfile / README.md
# Installs everything outside Brewfile: Homebrew + Xcode CLI + 3 npm globals
# Usage: bash ./install.sh

set -e

VERSION="v5.6.7"

# ─── Logging ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$SCRIPT_DIR"

# Clean up install logs older than 7 days so they don't pile up across runs
find "$SCRIPT_DIR" -maxdepth 1 -name "install-*.log" -type f -mtime +7 -delete 2>/dev/null || true

LOG_FILE="$SCRIPT_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1

log()  { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }
err()  { printf "\033[1;31m✗ %s\033[0m\n" "$1"; }

START_TIME=$(date +%s)

# ─── 1/6  Homebrew ───────────────────────────────────────────────────────────
log "1/6  Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew already installed"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH (Apple Silicon — Intel path already filtered in bootstrap.sh pre-flight)
  if [[ -d /opt/homebrew/bin ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  ok "Homebrew installed"
fi

# ─── 2/6  Xcode CLI Tools ────────────────────────────────────────────────────
log "2/6  Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode CLI already installed"
else
  xcode-select --install
  warn "Xcode CLI installer dialog opened — finish the GUI install, then press Enter."
  read -rp "Press Enter to continue..." _
fi

# ─── 3/6  Brewfile ───────────────────────────────────────────────────────────
log "3/6  Brewfile (git / node / uv / tailscale / ghostty / chrome / claude-code / beeper / obsidian)"
if [[ -f "$SCRIPT_DIR/Brewfile" ]]; then
  brew bundle install --file="$SCRIPT_DIR/Brewfile"
  ok "Brewfile done"
else
  warn "Brewfile not found in script dir — skipping"
fi

# Old GUI Tailscale.app (cask) leaves its sandboxed tailscaled running, which
# blocks the formula daemon from binding the socket and rejects `tailscale up
# --ssh` with HTTP 500. Detect + remove the cask cleanly before starting the
# formula daemon. On fresh installs (no cask), this whole block is a no-op.
if [[ -d /Applications/Tailscale.app ]]; then
  warn "Detected old Tailscale.app (cask GUI) — removing so formula daemon can take over"
  osascript -e 'quit app "Tailscale"' 2>/dev/null || true
  sleep 1
  brew uninstall --cask tailscale-app 2>/dev/null || true
  sudo pkill -f 'Tailscale.app/Contents' 2>/dev/null || true
  sleep 1
  ok "Old Tailscale GUI cleaned up"
fi

# tailscale formula installs a launchd plist; start (or restart) it as a
# background service. `restart` covers both 'not running yet' and 'replacing
# the GUI daemon we just killed' cases — idempotent either way.
echo "Restarting tailscale launchd service to ensure formula daemon is the one running..."
if sudo brew services restart tailscale 2>/dev/null; then
  ok "tailscale service running"
else
  warn "Failed to (re)start tailscale service. Try manually: sudo brew services restart tailscale"
fi
sleep 2  # give the daemon a moment to bind the socket before `tailscale up`

# ─── 4/6  npm globals ────────────────────────────────────────────────────────
log "4/6  npm globals: Slock daemon / OpenAI Codex / OpenCLI"
need_pkg=()
for pkg in @slock-ai/daemon @openai/codex @jackwener/opencli; do
  if npm ls -g "$pkg" --depth=0 >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    need_pkg+=("$pkg")
  fi
done
if [[ "${#need_pkg[@]}" -gt 0 ]]; then
  echo "Installing: ${need_pkg[*]}"
  npm install -g "${need_pkg[@]}"
  ok "npm globals installed"
else
  ok "All npm globals already present — nothing to install"
fi

# ─── 5/6  Post-install verification ──────────────────────────────────────────
log "5/6  Verify installation"

VERIFY_FAILED=0
verify_app() {
  if [[ -d "/Applications/$1" ]]; then
    ok "/Applications/$1"
  else
    err "/Applications/$1 MISSING"
    VERIFY_FAILED=1
  fi
}
verify_cli() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 ($(command -v "$1"))"
  else
    err "$1 MISSING"
    VERIFY_FAILED=1
  fi
}

# Apps that get installed by Brewfile casks
verify_app "Ghostty.app"
verify_app "Google Chrome.app"
verify_app "Beeper Desktop.app"
verify_app "Obsidian.app"
# Note: Tailscale is now the CLI/daemon formula, not the cask, so no Tailscale.app

# CLI tools (from Brewfile formulas, casks shipping a CLI, and npm globals)
verify_cli git
verify_cli node
verify_cli uv
verify_cli tailscale
verify_cli claude
verify_cli codex
verify_cli slock-daemon   # npm @slock-ai/daemon exposes binary as 'slock-daemon', not 'slock'
verify_cli opencli

if [[ "$VERIFY_FAILED" -eq 1 ]]; then
  err "One or more items missing. See log: $LOG_FILE"
fi

# ─── 6/6  Summary + auto-open apps that need manual sign-in ──────────────────
log "6/6  Summary"

ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

ver() {
  local label="$1" cmd="$2" v
  v="$(eval "$cmd" 2>/dev/null | head -1 || echo 'n/a')"
  printf "  %-14s %s\n" "$label" "$v"
}

echo
echo "═══════════════════════════════════════════════════"
echo "  ✅ Install complete · ${VERSION} · Elapsed ${MINS}m ${SECS}s"
echo "───────────────────────────────────────────────────"
ver "Homebrew"     "brew --version"
ver "git"          "git --version"
ver "node"         "node --version"
ver "uv"           "uv --version"
ver "Claude Code"  "claude --version"
ver "Codex"        "codex --version"
ver "Slock daemon" "slock-daemon --version"
ver "Tailscale"    "tailscale --version"
ver "OpenCLI"      "opencli --version"
echo "═══════════════════════════════════════════════════"

# ─── macOS always-on settings (headless 24/7 operation) ─────────────────────
log "macOS always-on settings"

if sudo pmset -a sleep 0 >/dev/null; then ok "Sleep disabled"; else warn "Failed to disable sleep"; fi
if sudo pmset -a disksleep 0 >/dev/null; then ok "Disk sleep disabled"; else warn "Failed to disable disk sleep"; fi
if sudo pmset -a womp 1 >/dev/null; then ok "Wake on network enabled"; else warn "Failed to enable wake on network"; fi
if sudo pmset -a autorestart 1 >/dev/null; then ok "Auto-restart on power failure enabled"; else warn "Failed to enable auto-restart"; fi

# FileVault check — when on, disk unlock is required on every boot, breaking
# unattended operation. Don't auto-disable (security trade-off is the user's
# call); just surface the status.
FV_STATUS="$(fdesetup status 2>/dev/null | head -1)"
case "$FV_STATUS" in
  "FileVault is Off."*)
    ok "FileVault: Off (headless boot OK)"
    ;;
  "FileVault is On."*)
    warn "FileVault is ON — disk unlock required on every boot, breaks unattended operation."
    warn "  Consider disabling: System Settings → Privacy & Security → FileVault → Turn Off"
    warn "  (Or accept that someone must enter the password after every reboot.)"
    ;;
  *)
    warn "FileVault status unknown: $FV_STATUS"
    ;;
esac

# ─── Tailscale + macOS Screen Sharing (remote support backbone) ──────────────
log "Tailscale + Screen Sharing setup (for remote SSH/VNC from Jacky's MacBook)"

# Tailscale CLI formula (brew install tailscale, not the cask GUI).
# 'sudo' uses secure_path by default which doesn't include /opt/homebrew/bin,
# so 'sudo tailscale' would fail with 'command not found'. Use the absolute path.
TAILSCALE_BIN="/opt/homebrew/bin/tailscale"

if "$TAILSCALE_BIN" status 2>/dev/null | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s"; then
  ok "Tailscale already up: $("$TAILSCALE_BIN" ip -4 2>/dev/null | head -1)"
else
  # Auth key resolution order:
  #   1. $TAILSCALE_AUTH_KEY env var (highest priority)
  #   2. ~/.slock-mac-mini-setup.env file (source it if present)
  #   3. Interactive prompt (fallback)
  ENV_FILE="$HOME/.slock-mac-mini-setup.env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    ok "Loaded $ENV_FILE"
  fi

  TS_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

  if [[ -z "$TS_AUTH_KEY" ]]; then
    read -rp "Paste Tailscale auth key (tskey-auth-...) or Enter to skip: " TS_AUTH_KEY
  else
    ok "Using TAILSCALE_AUTH_KEY from environment"
  fi

  if [[ -n "$TS_AUTH_KEY" ]]; then
    DEFAULT_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || echo 'ecoya-client')"
    read -rp "Hostname on tailnet [$DEFAULT_HOSTNAME]: " TS_HOSTNAME
    TS_HOSTNAME="${TS_HOSTNAME:-$DEFAULT_HOSTNAME}"

    # Refresh sudo cache right before invoking — install may have taken many minutes
    # since pre-flight cached sudo, and the background keep-alive can fail silently
    # for various reasons (tty changes, signal handling, etc). Better to re-verify
    # than have sudo prompt mid-Tailscale-up.
    sudo -v

    if sudo "$TAILSCALE_BIN" up \
         --auth-key="$TS_AUTH_KEY" \
         --hostname="$TS_HOSTNAME" \
         --advertise-tags=tag:ecoya-client \
         --ssh; then
      TS_IP="$("$TAILSCALE_BIN" ip -4 2>/dev/null | head -1)"
      ok "Tailscale up as '$TS_HOSTNAME' (tailnet IP $TS_IP, Tailscale SSH enabled)"
    else
      warn "Tailscale up failed. Run manually:"
      warn "  sudo $TAILSCALE_BIN up --auth-key=<key> --hostname=<name> --advertise-tags=tag:ecoya-client --ssh"
    fi
  else
    warn "Tailscale not joined — remote SSH/VNC won't work until you run:"
    warn "  sudo $TAILSCALE_BIN up --hostname=<name> --advertise-tags=tag:ecoya-client --ssh"
  fi
fi

# Enable macOS Screen Sharing (VNC on port 5900) for remote desktop control
log "Enable macOS Screen Sharing (VNC port 5900)"
if sudo launchctl list 2>/dev/null | grep -q com.apple.screensharing; then
  ok "Screen Sharing already enabled"
elif sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist 2>/dev/null; then
  ok "Screen Sharing enabled (port 5900)"
else
  warn "Screen Sharing enable failed. Enable manually:"
  warn "  System Settings → General → Sharing → Screen Sharing: ON"
fi

# AI tool CLIs (Claude Code + Codex) — each optional per client, skip if already authed
log "AI tool sign-in"

claude_authed=0
codex_authed=0
claude auth status >/dev/null 2>&1 && claude_authed=1
codex login status  >/dev/null 2>&1 && codex_authed=1

if [[ "$claude_authed" -eq 1 ]]; then ok "Claude Code already authenticated"; fi
if [[ "$codex_authed"  -eq 1 ]]; then ok "Codex already authenticated"; fi

if [[ "$claude_authed" -eq 0 ]]; then
  read -rp "Sign in to Claude Code (Anthropic)? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    if claude auth login; then ok "Claude Code signed in"; else warn "Claude Code sign-in failed. Run later: claude auth login"; fi
  else
    warn "Skipped Claude Code. Run later: claude auth login"
  fi
fi

if [[ "$codex_authed" -eq 0 ]]; then
  read -rp "Sign in to Codex (OpenAI)? [y/N]: " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    if codex login; then ok "Codex signed in"; else warn "Codex sign-in failed. Run later: codex login"; fi
  else
    warn "Skipped Codex. Run later: codex login"
  fi
fi

cat <<'AUTOLOGIN'

────────────────────────────────────────────────────
  ⚠ One-time manual step: enable Auto-login (GUI only)
────────────────────────────────────────────────────
  After a reboot, user-level apps (Slock daemon, Beeper, Obsidian, etc.)
  only start once a user is logged in. macOS does not allow setting auto-login
  safely from the command line, so configure it once via the GUI:

    System Settings → Users & Groups → Automatically log in as → <user>

  Without this, after a power outage the machine will boot but stay at the
  login screen and your background agents will be unreachable.

AUTOLOGIN

echo "Install log: $LOG_FILE"
