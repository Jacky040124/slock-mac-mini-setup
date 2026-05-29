#!/usr/bin/env bash
# Client Mac mini deployment installer
# Companion to: bootstrap.sh / Brewfile / README.md
# Installs everything outside Brewfile: Homebrew + Xcode CLI + 3 npm globals
# Usage: bash ./install.sh

set -e

VERSION="v5.5"

# ─── Logging ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$SCRIPT_DIR"
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
npm install -g \
  @slock-ai/daemon \
  @openai/codex \
  @jackwener/opencli
ok "npm globals installed"

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

# Sign in to AI tool CLIs (Claude Code + Codex use browser-based OAuth)
log "AI tool sign-in (Claude Code + Codex use browser OAuth)"
echo "Press Enter to start CLI sign-ins, or Ctrl+C to skip and do it manually later."
read -r _

# Claude Code (Anthropic)
log "Sign in to Claude Code"
if claude auth status >/dev/null 2>&1; then
  ok "Claude Code already authenticated"
else
  if claude auth login; then
    ok "Claude Code signed in"
  else
    warn "Claude Code sign-in skipped or failed. Run later: claude auth login"
  fi
fi

# Codex (OpenAI)
log "Sign in to Codex"
if codex login status >/dev/null 2>&1; then
  ok "Codex already authenticated"
else
  if codex login; then
    ok "Codex signed in"
  else
    warn "Codex sign-in skipped or failed. Run later: codex login"
  fi
fi

# Auto-open the GUI apps that still need manual sign-in
log "Opening GUI apps for manual sign-in..."
open -a "Tailscale" 2>/dev/null || true
open -a "Beeper Desktop" 2>/dev/null || true
open -a "Obsidian" 2>/dev/null || true
open -a "Google Chrome" 2>/dev/null || true

cat <<'POST'

────────────────────────────────────────────────────
  Remaining manual steps (GUI)
────────────────────────────────────────────────────
  1. Chrome     → sign in to client accounts (XHS / IG / Gmail / WhatsApp Web / WeChat)
  2. Tailscale  → join the Ecoya tailnet
  3. Slock      → run `slock` and join the assigned workspace
  4. Obsidian   → open the client workspace folder as a vault
  5. Beeper     → sign in and attach client IM accounts

POST

echo "Install log: $LOG_FILE"
echo
