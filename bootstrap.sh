#!/usr/bin/env bash
# slock-mac-mini-setup · bootstrap
# Ecoya Consulting · standard Slock client Mac mini deployment
#
# Recommended usage (so sudo can grab tty):
#   curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh -o ~/bootstrap.sh && bash ~/bootstrap.sh

set -e

VERSION="v5.5"
REPO_URL="https://github.com/Jacky040124/slock-mac-mini-setup.git"
TARGET_DIR="$HOME/slock-mac-mini-setup"

log() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
err() { printf "\033[1;31m✗ %s\033[0m\n" "$1"; }

# ─── Banner ──────────────────────────────────────────────────────────────────
cat <<BANNER

═══════════════════════════════════════════════════
  slock-mac-mini-setup · Ecoya Consulting
  ${VERSION}
═══════════════════════════════════════════════════

BANNER

# ─── 0/4  Pre-flight ─────────────────────────────────────────────────────────
log "0/4  Pre-flight checks"

# CPU architecture — Apple Silicon only
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  err "This setup only supports Apple Silicon Mac (M1/M2/M3/M4)."
  err "Detected architecture: $ARCH (Intel). Use an Apple Silicon Mac mini."
  err "Apple discontinued Intel Mac mini in late 2022; all current models are M-series."
  exit 1
fi
ok "Apple Silicon ($ARCH)"

# admin user
if ! dseditgroup -o checkmember -m "$USER" admin >/dev/null 2>&1; then
  err "Current user '$USER' is not an admin."
  err "Homebrew and casks need admin. Switch to an admin account, or grant admin to '$USER'."
  exit 1
fi
ok "User '$USER' is admin"

# disk space — need >= 5 GB free on /
DISK_AVAIL_GB="$(df -k / | awk 'NR==2 {print int($4/1048576)}')"
if [[ "$DISK_AVAIL_GB" -lt 5 ]]; then
  err "Only ${DISK_AVAIL_GB} GB available on /. Need at least 5 GB"
  err "(Brewfile ~1.5 GB + Xcode CLI ~1 GB + buffer)."
  err "Free up space: empty Trash, clean ~/Downloads, remove large files."
  exit 1
fi
ok "Disk space: ${DISK_AVAIL_GB} GB available (>= 5 GB required)"

# network
if ! curl -fsS --max-time 5 https://github.com >/dev/null; then
  err "Cannot reach github.com. Check WiFi."
  exit 1
fi
ok "Network OK"

# sudo cache + background keep-alive (silent for ~15 min)
echo
echo "Admin password required (once, then cached for ~15 min):"
if ! sudo -v; then
  err "sudo authentication failed."
  err "Common causes:"
  err "  1) Wrong password — re-run bootstrap.sh"
  err "  2) 'curl | bash' mode can't grab tty for sudo. Use download-then-bash:"
  err "     curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh -o ~/bootstrap.sh && bash ~/bootstrap.sh"
  exit 1
fi
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
ok "sudo cached (background keep-alive PID $SUDO_KEEPALIVE_PID)"

# ─── 1/4  git + Xcode CLI ────────────────────────────────────────────────────
# Note: 'command -v git' alone is unreliable on fresh macOS — there's a stub
# binary at /usr/bin/git that returns true but triggers the Xcode CLI installer
# dialog (and exits non-zero) when actually invoked. Use xcode-select -p instead,
# which checks whether the developer tools are really installed.
log "1/4  Ensure Xcode Command Line Tools are installed"
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode CLI already installed ($(xcode-select -p))"
else
  echo "Xcode CLI not installed — triggering installer dialog now."
  echo "Click 'Install' in the macOS dialog when it appears, accept the license,"
  echo "and wait for the download (~1 GB, 3-5 min on a normal connection)."
  xcode-select --install 2>/dev/null || true
  echo
  echo "Polling for installation to complete..."
  WAITED=0
  until xcode-select -p >/dev/null 2>&1; do
    printf "."
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ "$WAITED" -ge 1800 ]]; then
      echo
      err "Xcode CLI install did not complete within 30 minutes."
      err "Finish the GUI install manually, then re-run bootstrap.sh."
      exit 1
    fi
  done
  echo
  ok "Xcode CLI installed ($(xcode-select -p))"
fi

# Sanity-check git too (Xcode CLI ships git, so this should pass now)
if ! git --version >/dev/null 2>&1; then
  err "git still not working after Xcode CLI install. Check 'xcode-select -p' and 'which git'."
  exit 1
fi
ok "git available ($(git --version | head -1))"

# ─── 2/4  Clone / pull repo ──────────────────────────────────────────────────
log "2/4  Fetch setup repo into $TARGET_DIR"
if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "Repo already present — pulling latest..."
  git -C "$TARGET_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$TARGET_DIR"
fi
ok "Repo ready"

# ─── 3/4  Run install.sh ─────────────────────────────────────────────────────
log "3/4  Run install.sh (pre-flight passed, sudo cached)"
cd "$TARGET_DIR"
export BOOTSTRAP_PREFLIGHT_DONE=1
bash install.sh

# ─── 4/4  Done ───────────────────────────────────────────────────────────────
log "4/4  bootstrap complete"
