#!/usr/bin/env bash
# Client Mac mini deployment installer
# Companion to: bootstrap.sh / Brewfile / README.md
# Installs everything outside Brewfile: Homebrew + Xcode CLI + 3 npm globals
# Usage: bash ./install.sh

set -e

VERSION="v5.6.2"

# ─── Logging ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$SCRIPT_DIR"

# Clean up install logs older than 7 days so they don't pile up across runs
find "$SCRIPT_DIR" -maxdepth 1 -name "install-*.log" -type f -mtime +7 -delete 2>/dev/null || true

LOG_FILE="$SCRIPT_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1
echo "Log: $LOG_FILE"

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
log "3/6  Brewfile (git / node / uv / ghostty / chrome / claude-code / beeper / obsidian / tailscale)"
if [[ -f "$SCRIPT_DIR/Brewfile" ]]; then
  brew bundle install --file="$SCRIPT_DIR/Brewfile"
  ok "Brewfile done"
else
  warn "Brewfile not found in script dir — skipping"
fi

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
verify_app "Tailscale.app"

# CLI tools (from Brewfile formulas, casks shipping a CLI, and npm globals)
verify_cli git
verify_cli node
verify_cli uv
verify_cli claude
verify_cli codex
verify_cli slock
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
ver "Slock"        "slock --version"
ver "OpenCLI"      "opencli --version"
echo "═══════════════════════════════════════════════════"

# ─── Tailscale + macOS Screen Sharing (remote support backbone) ──────────────
log "Tailscale + Screen Sharing setup (for remote SSH/VNC from Jacky's MacBook)"

if tailscale status 2>/dev/null | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s"; then
  ok "Tailscale already up: $(tailscale ip -4 2>/dev/null | head -1)"
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
    echo
    echo "Tailscale auth key needed. Three ways to provide it (in order of preference):"
    echo "  1. Pre-create file:  ~/.slock-mac-mini-setup.env  (one line: TAILSCALE_AUTH_KEY=tskey-auth-...)"
    echo "  2. Env var:          TAILSCALE_AUTH_KEY=tskey-... bash bootstrap.sh"
    echo "  3. Paste here interactively (this prompt)"
    echo
    echo "If you don't have a long-lived key yet, generate at:"
    echo "  https://login.tailscale.com/admin/settings/keys"
    echo "  Reusable: YES · Expires: 'No expiry' · Tags: tag:ecoya-client"
    echo "(Safe to be reusable — joined machines get tag:ecoya-client which has no inbound"
    echo " access per the ACL, so leak only lets others add unprivileged nodes that you see"
    echo " and can remove from the admin console.)"
    echo
    read -rp "Paste Tailscale auth key (tskey-auth-...) or Enter to skip: " TS_AUTH_KEY
  else
    ok "Using TAILSCALE_AUTH_KEY from environment (length ${#TS_AUTH_KEY})"
  fi

  if [[ -n "$TS_AUTH_KEY" ]]; then
    DEFAULT_HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || echo 'ecoya-client')"
    read -rp "Hostname on tailnet [$DEFAULT_HOSTNAME]: " TS_HOSTNAME
    TS_HOSTNAME="${TS_HOSTNAME:-$DEFAULT_HOSTNAME}"

    if sudo tailscale up \
         --auth-key="$TS_AUTH_KEY" \
         --hostname="$TS_HOSTNAME" \
         --advertise-tags=tag:ecoya-client \
         --ssh; then
      TS_IP="$(tailscale ip -4 2>/dev/null | head -1)"
      ok "Tailscale up as '$TS_HOSTNAME' (tailnet IP $TS_IP, Tailscale SSH enabled)"
    else
      warn "Tailscale up failed. Run manually:"
      warn "  sudo tailscale up --auth-key=<key> --hostname=<name> --advertise-tags=tag:ecoya-client --ssh"
    fi
  else
    warn "Tailscale not joined — remote SSH/VNC won't work until you run:"
    warn "  sudo tailscale up --hostname=<name> --advertise-tags=tag:ecoya-client --ssh"
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

# Sign in to AI tool CLIs (Claude Code + Codex use browser-based OAuth)
# Each is optional per client — most clients only use one. We check current
# status first and only prompt for the ones that aren't already authenticated.
log "AI tool sign-in (Claude Code + Codex, browser OAuth)"

claude_authed=0
codex_authed=0
claude auth status >/dev/null 2>&1 && claude_authed=1
codex login status  >/dev/null 2>&1 && codex_authed=1

if [[ "$claude_authed" -eq 1 ]]; then ok "Claude Code already authenticated"; fi
if [[ "$codex_authed"  -eq 1 ]]; then ok "Codex already authenticated"; fi

if [[ "$claude_authed" -eq 1 && "$codex_authed" -eq 1 ]]; then
  ok "Both AI tools authenticated — no sign-in needed"
else
  echo
  echo "Each AI tool sign-in is optional — most clients only use one."

  if [[ "$claude_authed" -eq 0 ]]; then
    read -rp "Sign in to Claude Code (Anthropic)? [y/N]: " ans
    case "$ans" in
      [Yy]*)
        if claude auth login; then
          ok "Claude Code signed in"
        else
          warn "Claude Code sign-in failed. Run later: claude auth login"
        fi
        ;;
      *)
        warn "Skipped Claude Code. Run later: claude auth login"
        ;;
    esac
  fi

  if [[ "$codex_authed" -eq 0 ]]; then
    read -rp "Sign in to Codex (OpenAI)? [y/N]: " ans
    case "$ans" in
      [Yy]*)
        if codex login; then
          ok "Codex signed in"
        else
          warn "Codex sign-in failed. Run later: codex login"
        fi
        ;;
      *)
        warn "Skipped Codex. Run later: codex login"
        ;;
    esac
  fi
fi

# Auto-open the GUI apps that still need manual sign-in
log "Opening GUI apps for manual sign-in..."
open -a "Beeper Desktop" 2>/dev/null || true
open -a "Obsidian" 2>/dev/null || true
open -a "Google Chrome" 2>/dev/null || true

cat <<'POST'

────────────────────────────────────────────────────
  Remaining manual steps (GUI)
────────────────────────────────────────────────────
  1. Chrome     → sign in to client accounts (XHS / IG / Gmail / WhatsApp Web / WeChat)
  2. Slock      → run `slock` and join the assigned workspace
  3. Obsidian   → open the client workspace folder as a vault
  4. Beeper     → sign in and attach client IM accounts

POST

# Remote-access cheatsheet for Jacky (printed at end so it's the last thing on screen)
if command -v tailscale >/dev/null 2>&1 && tailscale status 2>/dev/null | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s"; then
  TS_IP_FINAL="$(tailscale ip -4 2>/dev/null | head -1)"
  TS_NAME_FINAL="$(tailscale status --self --json 2>/dev/null | grep -m1 '"DNSName"' | sed 's/.*"DNSName":"//; s/\.",.*//; s/\..*//' || scutil --get LocalHostName 2>/dev/null)"
  cat <<REMOTE

────────────────────────────────────────────────────
  Remote access from Jacky's MacBook (save these)
────────────────────────────────────────────────────
  Hostname     : $TS_NAME_FINAL
  Tailnet IP   : $TS_IP_FINAL
  SSH          : tailscale ssh $USER@$TS_NAME_FINAL
  Screen (VNC) : open vnc://$TS_NAME_FINAL/   (or use IP $TS_IP_FINAL)
  Status check : tailscale status | grep $TS_NAME_FINAL

REMOTE
fi

echo "Install log: $LOG_FILE"
echo
