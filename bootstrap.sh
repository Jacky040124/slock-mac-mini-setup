#!/usr/bin/env bash
# slock-mac-mini-setup · bootstrap
# 一行远程拉起整套部署：
#   curl -fsSL https://raw.githubusercontent.com/Jacky040124/slock-mac-mini-setup/main/bootstrap.sh | bash

set -e

REPO_URL="https://github.com/Jacky040124/slock-mac-mini-setup.git"
TARGET_DIR="$HOME/slock-mac-mini-setup"

log() { printf "\n\033[1;36m▶ %s\033[0m\n" "$1"; }
ok()  { printf "\033[1;32m✓ %s\033[0m\n" "$1"; }

log "1/3  确保 git 在 PATH 里"
if ! command -v git >/dev/null 2>&1; then
  echo "git 未安装，先触发 Xcode CLI 安装弹窗..."
  xcode-select --install || true
  echo "请装完 Xcode CLI 之后重新跑 bootstrap.sh"
  exit 1
fi
ok "git OK"

log "2/3  拉 setup repo 到 $TARGET_DIR"
if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "已存在，拉最新..."
  git -C "$TARGET_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$TARGET_DIR"
fi
ok "Repo 就位"

log "3/3  跑 install.sh"
cd "$TARGET_DIR"
bash install.sh
