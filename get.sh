#!/usr/bin/env bash
# 一行安装的引导脚本（macOS / Linux）
#
#   curl -fsSL https://raw.githubusercontent.com/liujingyangself/clawbot-wechat/main/get.sh | bash
#
# 它只做三件事：把仓库下载下来、放到一个固定位置、然后把安装交给 scripts/install.sh。
set -euo pipefail

REPO="liujingyangself/clawbot-wechat"
BRANCH="${CLAWBOT_BRANCH:-main}"
DEST="${CLAWBOT_DIR:-$HOME/clawbot-wechat}"

R=$'\033[31m'; G=$'\033[32m'; B=$'\033[1m'; N=$'\033[0m'
die() { printf '%s✗ %s%s\n' "$R" "$1" "$N" >&2; exit 1; }

printf '\n%s微信 AI 助手 · 正在准备安装%s\n\n' "$B" "$N"

# ── 1. 必须有终端 ────────────────────────────────────────────────────────
# curl | bash 时 stdin 是那根管道，不是键盘。但安装过程要扫二维码、要在
# Antigravity 的登录界面按键，没有真终端会直接卡死。所以这里强制接回 /dev/tty。
if [[ ! -e /dev/tty ]] || ! (exec </dev/tty) 2>/dev/null; then
  die "需要在终端里运行。请打开「终端」App，把那条安装命令粘进去再回车。"
fi

# ── 2. 基本依赖 ──────────────────────────────────────────────────────────
command -v curl >/dev/null 2>&1 || die "没有 curl，无法下载。"
command -v tar  >/dev/null 2>&1 || die "没有 tar，无法解压。"

# ── 3. 下载 ──────────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "  正在下载安装包…"
curl -fsSL --retry 3 --retry-delay 2 --max-time 120 \
  "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" -o "$TMP/src.tgz" \
  || die "下载失败。检查网络（在中国大陆可能需要先开代理），然后重新运行。"

[[ -s "$TMP/src.tgz" ]] || die "下载下来是空的，请重试。"

# 重装时先清掉旧的，避免新旧文件混在一起
if [[ -d "$DEST" ]]; then
  echo "  发现已有副本，正在更新…"
  rm -rf "$DEST"
fi
mkdir -p "$DEST"
tar -xzf "$TMP/src.tgz" --strip-components=1 -C "$DEST" \
  || die "解压失败，请重试。"

[[ -f "$DEST/scripts/install.sh" ]] || die "安装包不完整（缺 scripts/install.sh），请重试。"

chmod +x "$DEST"/scripts/*.sh "$DEST"/scripts/*.command "$DEST"/*.command 2>/dev/null || true
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

printf '%s  ✓ 准备好了：%s%s\n\n' "$G" "$DEST" "$N"

# ── 4. 交给真正的安装脚本，并把键盘接回去 ────────────────────────────────
exec bash "$DEST/scripts/install.sh" </dev/tty
