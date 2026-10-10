#!/usr/bin/env bash
# 双击我就开始安装。
cd "$(dirname "$0")" || exit 1
# 去掉下载后被 macOS 打上的隔离标记，避免「无法验证开发者」反复弹窗
xattr -dr com.apple.quarantine . 2>/dev/null || true
chmod +x scripts/*.sh scripts/*.command 2>/dev/null || true
exec bash scripts/install.sh
