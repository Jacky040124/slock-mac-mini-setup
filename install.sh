#!/usr/bin/env bash
# 客户端 Mac mini 部署 install 脚本
# 配套：客户端_Mac_mini_部署清单.md
# 装 Brewfile 之外那 5 项：Homebrew / Xcode CLI / 3 个 npm 全局工具
# 用法：bash ./install.sh

set -e

log() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }
warn(){ printf "\033[1;33m⚠ %s\033[0m\n" "$1"; }

# ─── 1. Homebrew ─────────────────────────────────────────────────────────────
log "1/5  Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew 已经在了，跳过"
else
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # 把 brew 加进 PATH（Apple Silicon）
  if [[ -d /opt/homebrew/bin ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  ok "Homebrew 装好"
fi

# ─── 2. Xcode CLI Tools ──────────────────────────────────────────────────────
log "2/5  Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode CLI 已经在了，跳过"
else
  xcode-select --install
  warn "Xcode CLI 安装弹窗已弹出，等装完再继续"
  read -rp "装完按回车继续..." _
fi

# ─── 3. Brewfile ─────────────────────────────────────────────────────────────
log "3/5  Brewfile（git / node / uv / ghostty / chrome / claude-code / beeper / obsidian / tailscale）"
if [[ -f "$(dirname "$0")/Brewfile" ]]; then
  brew bundle install --file="$(dirname "$0")/Brewfile"
  ok "Brewfile 装完"
else
  warn "Brewfile 不在同目录，跳过"
fi

# ─── 4. npm 全局工具 ─────────────────────────────────────────────────────────
log "4/5  npm 全局：Slock daemon / OpenAI Codex / OpenCLI"
npm install -g \
  @slock-ai/daemon \
  @openai/codex \
  @jackwener/opencli
ok "npm 全局工具装完"

# ─── 5. 完工提示 ─────────────────────────────────────────────────────────────
log "5/5  完工"
cat <<'POST'

✓ 14 项部署清单全部装完。剩下需要人工的：

  1. 打开 Chrome → 登录客户的 XHS / IG / Gmail / WhatsApp Web / WeChat
  2. 打开 Tailscale → 客户家 Mac mini 接入 Jacky 的 tailnet
  3. 跑 `slock` → 加入对应 Slock server / workspace
  4. 打开 Obsidian → 关联 agent_shared_memories vault
  5. 打开 Beeper → 客户的 IM 账号挂上

POST
