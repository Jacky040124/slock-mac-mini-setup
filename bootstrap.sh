#!/usr/bin/env bash
# slock-mac-mini-setup · bootstrap
# 一行远程拉起整套部署。推荐用法（保证 sudo 能拿到 tty）：
#   curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh -o ~/bootstrap.sh && bash ~/bootstrap.sh

set -e

REPO_URL="https://github.com/Jacky040124/slock-mac-mini-setup.git"
TARGET_DIR="$HOME/slock-mac-mini-setup"

log() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
err() { printf "\033[1;31m✗ %s\033[0m\n" "$1"; }

# ─── 0/4  Pre-flight ─────────────────────────────────────────────────────────
log "0/4  Pre-flight checks"

# CPU architecture — Apple Silicon only
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  err "本脚本只支持 Apple Silicon Mac (M1/M2/M3/M4)"
  err "检测到架构 $ARCH（Intel），请换 Apple Silicon 机型"
  err "Apple 2022 年底已停产 Intel Mac mini，目前所有在售 Mac mini 都是 Apple Silicon"
  exit 1
fi
ok "Apple Silicon 架构（$ARCH）"

# admin user
if ! dseditgroup -o checkmember -m "$USER" admin >/dev/null 2>&1; then
  err "当前用户 $USER 不是 admin。装 Homebrew / cask 需要 admin。"
  err "解决：换到 admin 账号登录，或让客户给当前账号加 admin 权限。"
  exit 1
fi
ok "用户 $USER 是 admin"

# disk space — need >= 5 GB free on /
DISK_AVAIL_GB="$(df -k / | awk 'NR==2 {print int($4/1048576)}')"
if [[ "$DISK_AVAIL_GB" -lt 5 ]]; then
  err "可用磁盘空间只有 ${DISK_AVAIL_GB} GB，至少需要 5 GB（Brewfile + npm globals ≈ 1.5 GB，外加 Xcode CLI ≈ 1 GB 和缓冲）"
  err "清理磁盘后再跑：'open ~/.Trash' 清空回收站、删除大文件、清理 ~/Downloads"
  exit 1
fi
ok "可用磁盘 ${DISK_AVAIL_GB} GB（≥ 5 GB 需求）"

# network
if ! curl -fsS --max-time 5 https://github.com >/dev/null; then
  err "无法访问 github.com，先检查 WiFi"
  exit 1
fi
ok "网络通"

# sudo cache + background keep-alive（约 15 分钟内静默通过）
echo
echo "需要 admin 密码授权一次，之后约 15 分钟内不会再问。"
if ! sudo -v; then
  err "sudo 授权失败。常见原因："
  err "  1) 密码输错 — 重新跑 bootstrap.sh"
  err "  2) 'curl | bash' 模式下 sudo 拿不到 tty — 改成下载再跑："
  err "     curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh -o ~/bootstrap.sh && bash ~/bootstrap.sh"
  exit 1
fi
( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
ok "sudo 已 cache，后台续活中（PID $SUDO_KEEPALIVE_PID）"

# ─── 1/4  git ────────────────────────────────────────────────────────────────
log "1/4  确保 git 在 PATH 里"
if ! command -v git >/dev/null 2>&1; then
  echo "git 未安装，先触发 Xcode CLI 安装弹窗..."
  xcode-select --install || true
  err "请在 GUI 弹窗里装完 Xcode CLI 之后，重新跑 bootstrap.sh"
  exit 1
fi
ok "git OK"

# ─── 2/4  Clone / pull repo ──────────────────────────────────────────────────
log "2/4  拉 setup repo 到 $TARGET_DIR"
if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "已存在，拉最新..."
  git -C "$TARGET_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$TARGET_DIR"
fi
ok "Repo 就位"

# ─── 3/4  Run install.sh ─────────────────────────────────────────────────────
log "3/4  跑 install.sh（pre-flight 已通过，sudo 已 cache）"
cd "$TARGET_DIR"
export BOOTSTRAP_PREFLIGHT_DONE=1
bash install.sh

# ─── 4/4  Done ───────────────────────────────────────────────────────────────
log "4/4  bootstrap 完工 ✓"
