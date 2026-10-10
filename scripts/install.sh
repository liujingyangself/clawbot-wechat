#!/usr/bin/env bash
# 微信 AI 助手 一键安装（macOS）
# 面向完全不懂代码的使用者：每一步都有中文说明，需要人工配合时会弹窗。
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$HOME/Library/Logs/clawbot-wechat-install.log"
mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# ── 输出与日志 ───────────────────────────────────────────────────────────
B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
log()  { printf '%s\n' "$(date '+%F %T') $*" >> "$LOG"; }
say()  { printf '%s\n' "$*"; log "$*"; }
step() { printf '\n%s▶ %s%s\n' "$B" "$*" "$N"; log "STEP: $*"; }
ok()   { printf '%s  ✓ %s%s\n' "$G" "$*" "$N"; log "OK: $*"; }
warn() { printf '%s  ! %s%s\n' "$Y" "$*" "$N"; log "WARN: $*"; }
die()  { printf '%s  ✗ %s%s\n' "$R" "$*" "$N"; log "FAIL: $*"
         dialog "安装中断了：$*

详细日志在：$LOG
把这个文件发给帮你装的人就能看出问题。"; exit 1; }

# ── 提示（需要使用者配合时）──────────────────────────────────────────────
# 设计原则：**终端永远打印一份，弹窗只是加强提醒**。
# 弹窗可能被别的窗口挡住、可能在非交互环境下根本不显示，
# 如果它是唯一的渠道，使用者就会对着一个没反应的窗口发呆。
INTERACTIVE=1
REAL_CONSOLE=1
[[ -t 0 ]] || INTERACTIVE=0
# 输出被捕获时，二维码这类「画在屏幕上」的东西使用者根本看不到——
# 它们会进到调用方（比如 AI 代理）的缓冲区里。
[[ -t 1 && -t 0 ]] || REAL_CONSOLE=0

# 二维码、agy 的登录界面这些必须真人盯着屏幕看。
# 但这个安装器的设计目标是「丢给 AI 代理全自动装完，人只辅助扫码」，
# 所以输出被捕获时**不能停下来让人手动跑**——那等于把活又推回给人。
# 正确做法：自己弹一个使用者看得见的 Terminal 窗口来做这一步，跑完自动回到主流程。
run_visible() {  # run_visible <标题> <命令> <提示>
  if (( REAL_CONSOLE )); then
    printf '\n%s  %s%s\n\n' "$Y" "$3" "$N"
    eval "$2"
    return 0
  fi

  printf '\n%s%s%s\n' "$Y" "$(printf '─%.0s' $(seq 1 60))" "$N"
  printf '%s  正在弹出一个新窗口：%s%s\n' "$Y$B" "$1" "$N"
  printf '  %s\n' "$3"
  echo   "  请在那个新窗口里操作，完成后会自动回到这里继续。"
  printf '%s%s%s\n' "$Y" "$(printf '─%.0s' $(seq 1 60))" "$N"
  log "VISIBLE-STEP: $1"

  local tag done_f script
  tag="$$-$(date +%s)"
  done_f="/tmp/clawbot-step-$tag.done"
  script="/tmp/clawbot-step-$tag.sh"
  {
    echo '#!/bin/bash'
    echo 'export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"'
    printf 'printf "\\n  %%s\\n\\n" %s\n' "$(printf '%q' "$3")"
    printf '%s\n' "$2"
    echo 'printf "\n  这一步完成了。\n"'
    echo 'sleep 2'
    printf 'touch %q\n' "$done_f"
    echo 'exit 0'
  } > "$script"
  chmod +x "$script"

  osascript -e "tell application \"Terminal\" to do script \"bash '$script'; exit\"" \
            -e 'tell application "Terminal" to activate' >/dev/null 2>&1 || {
    warn "弹不出新窗口"; rm -f "$script"; return 1; }

  # 最多等 15 分钟（二维码本身约 8 分钟就过期）
  local waited=0
  while [[ ! -f "$done_f" ]] && (( waited < 900 )); do sleep 2; waited=$((waited + 2)); done
  rm -f "$script" "$done_f"
  if (( waited >= 900 )); then warn "$1 超时了"; return 1; fi
  return 0
}

banner() {
  clear
  cat <<'BANNER'
  ┌──────────────────────────────────────────────┐
  │                                              │
  │        微信 AI 助手  ·  一键安装              │
  │                                              │
  │   装完之后，你在微信里发消息它就会回你        │
  │                                              │
  └──────────────────────────────────────────────┘

  安装过程中需要你配合 3 次（扫码 / 登录 / 复制密钥），
  到时候会弹窗提醒你，现在可以先去忙别的。

BANNER
}

# ── 0. 环境检查 ──────────────────────────────────────────────────────────
preflight() {
  step "检查电脑环境"
  [[ "$(uname -s)" == "Darwin" ]] || die "这个脚本只能在 Mac 上跑。Windows 请用 安装-Windows.bat"
  ok "系统：macOS $(sw_vers -productVersion) ($(uname -m))"

  log "=== 安装开始 $(date) ==="
}


# ── 代理（中国大陆几乎必需）──────────────────────────────────────────────
# 这里要解决的是一个很坑的情况：使用者开着 Clash 的「系统代理」，浏览器能上
# Google，于是以为网络没问题；但 Node.js 不读系统代理，OpenClaw 的后台服务
# 照样连不上 Gemini，报的错还完全看不出是代理问题。
PROXY_URL=""

# 常见客户端的默认 HTTP 代理端口。只探测 http://，因为 OpenClaw 的
# proxy.proxyUrl 只接受 http(s)://，不支持 socks5。
proxy_candidates() {
  cat <<'PORTS'
http://127.0.0.1:7890
http://127.0.0.1:7897
http://127.0.0.1:1087
http://127.0.0.1:10809
http://127.0.0.1:8889
http://127.0.0.1:6152
http://127.0.0.1:8080
http://127.0.0.1:2080
PORTS
}

google_reachable() {  # google_reachable [代理地址]
  if [[ -n "${1:-}" ]]; then
    curl -fsS --max-time 8 -x "$1" -o /dev/null https://www.google.com 2>/dev/null
  else
    curl -fsS --max-time 8 -o /dev/null https://www.google.com 2>/dev/null
  fi
}

detect_proxy() {
  # 先看系统代理设置里写了什么（macOS）
  local sys_host sys_port
  sys_host="$(scutil --proxy 2>/dev/null | awk '/HTTPProxy/{print $3}' | head -1)"
  sys_port="$(scutil --proxy 2>/dev/null | awk '/HTTPPort/{print $3}'  | head -1)"
  if [[ -n "${sys_host:-}" && -n "${sys_port:-}" ]]; then
    local u="http://$sys_host:$sys_port"
    google_reachable "$u" && { echo "$u"; return 0; }
  fi
  # 再挨个试常见端口
  local u
  while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    google_reachable "$u" && { echo "$u"; return 0; }
  done < <(proxy_candidates)
  return 1
}

apply_proxy_env() {  # 让本脚本后续所有 curl / 安装器都走代理
  export http_proxy="$PROXY_URL"  https_proxy="$PROXY_URL"
  export HTTP_PROXY="$PROXY_URL"  HTTPS_PROXY="$PROXY_URL"
  export no_proxy="localhost,127.0.0.1,::1"
  export NO_PROXY="$no_proxy"
  log "proxy in use: $PROXY_URL"
}

setup_proxy() {
  step "检查能不能连上 Google"

  # get.sh 可能已经探到代理并通过环境变量传下来了。
  # 如果不先认领它，下面的 curl 会因为带着环境变量而成功，
  # 于是误判成「能直连」，代理就不会被写进 OpenClaw 的配置。
  local inherited="${https_proxy:-${HTTPS_PROXY:-}}"
  if [[ -n "$inherited" ]]; then
    PROXY_URL="$inherited"; apply_proxy_env
    ok "沿用上一步探到的代理：$PROXY_URL"
    return
  fi

  if google_reachable; then ok "能直连，不需要代理"; return; fi

  warn "连不上 Google"
  say "  正在自动寻找你电脑上的代理软件…"
  local found; found="$(detect_proxy || true)"

  if [[ -n "$found" ]]; then
    PROXY_URL="$found"; apply_proxy_env
    ok "找到可用代理：$PROXY_URL"
    dialog "检测到你在用代理软件，地址是：

    $PROXY_URL

我会让助手也走这个代理，这样它才能用上 Google 的 AI。

（微信的消息不会绕到国外——代理软件会自己按规则分流，
国内的网站和微信走直连。）"
    return
  fi

  # 没探到：要么没开代理，要么开的是 socks 或者非常见端口
  dialog "连不上 Google，而且没找到正在运行的代理软件。

请先打开你的代理软件（Clash、v2rayN 这类），
确认浏览器能打开 google.com，然后点「知道了」继续。

如果你的软件只开了 socks5 端口，需要在它的设置里
把「HTTP 代理」也打开——这个助手只能用 HTTP 代理。"

  found="$(detect_proxy || true)"
  if [[ -n "$found" ]]; then
    PROXY_URL="$found"; apply_proxy_env; ok "找到了：$PROXY_URL"; return
  fi

  local manual
  manual="$(ask_text "还是没找到。请手动填写代理端口号（只填数字，在你代理软件的设置里能看到，常见的是 7890）：")"
  manual="$(printf '%s' "${manual:-}" | tr -cd '0-9')"
  if [[ -n "$manual" ]]; then
    local u="http://127.0.0.1:$manual"
    if google_reachable "$u"; then
      PROXY_URL="$u"; apply_proxy_env; ok "代理可用：$PROXY_URL"; return
    fi
    warn "通过 127.0.0.1:$manual 还是连不上 Google"
  fi
  die "没有可用的网络。请先确保代理软件正常工作（浏览器能打开 google.com），再重新运行安装程序。"
}

# OpenClaw 装好之后，把代理写进它自己的配置。
# 必须写进 config——只设环境变量的话，后台服务重装时会丢。
configure_openclaw_proxy() {
  [[ -z "$PROXY_URL" ]] && return 0
  step "让助手也走代理"
  openclaw config set proxy.proxyUrl "$PROXY_URL" >>"$LOG" 2>&1     || { warn "写入代理配置失败"; return; }
  # agy 是 Go 程序，会读 HTTPS_PROXY；把它写进服务的持久环境，
  # 这样后台服务拉起 agy 的时候也能走代理。
  local envf="$HOME/.openclaw/.env"
  mkdir -p "$(dirname "$envf")"
  if [[ -f "$envf" ]]; then
    grep -v -E '^(HTTPS?_PROXY|NO_PROXY)=' "$envf" > "$envf.tmp" 2>/dev/null && mv "$envf.tmp" "$envf"
  fi
  {
    echo "HTTP_PROXY=$PROXY_URL"
    echo "HTTPS_PROXY=$PROXY_URL"
    echo "NO_PROXY=localhost,127.0.0.1,::1"
  } >> "$envf"
  ok "助手的网络已指向 $PROXY_URL"
}

# ── 1. OpenClaw（助手的运行底座，自带 Node）──────────────────────────────
install_openclaw() {
  step "安装运行底座 OpenClaw（这步最久，3-10 分钟）"
  if command -v openclaw >/dev/null 2>&1; then
    ok "已经装过了：$(openclaw --version 2>/dev/null | head -1)"
    return
  fi
  say "  正在下载安装，请不要关窗口…"
  if ! curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard >>"$LOG" 2>&1; then
    curl -fsSL https://openclaw.ai/install.sh -o /tmp/oc-install.sh \
      && bash /tmp/oc-install.sh --no-onboard >>"$LOG" 2>&1 \
      || die "OpenClaw 安装失败，日志：$LOG"
  fi
  hash -r
  command -v openclaw >/dev/null 2>&1 || die "装完了但找不到 openclaw 命令，日志：$LOG"
  ok "OpenClaw $(openclaw --version 2>/dev/null | head -1)"
}

# ── 2. 微信通道插件（腾讯官方）───────────────────────────────────────────
install_wechat_plugin() {
  step "安装微信插件（腾讯官方出品）"
  if openclaw plugins list 2>/dev/null | grep -q "openclaw-weixin"; then
    ok "已经装过了"
  else
    openclaw plugins install "@tencent-weixin/openclaw-weixin" >>"$LOG" 2>&1 \
      || die "微信插件安装失败，日志：$LOG"
    ok "微信插件装好了"
  fi
  openclaw config set plugins.entries.openclaw-weixin.enabled true >>"$LOG" 2>&1 || true
}

# ── 3. Gemini 密钥（免费，不用绑卡）──────────────────────────────────────
setup_gemini_key() {
  step "配置备用通道（Google Gemini）"

  local existing
  existing="$(openclaw config get models.providers.google.apiKey 2>/dev/null | grep -oE '(AIza|AQ\.)[A-Za-z0-9_.-]{20,}' | head -1)"
  if [[ -n "${existing:-}" ]]; then
    ok "已经配过密钥了"
    # 重跑时也要探一次。只认「配过」就跳过的话，等于在没验证的情况下配置模型——
    # 密钥可能早就没额度了，而使用者要到发消息时才发现。
    say "  正在确认这把钥匙现在还能用…"
    if probe_any_model "$existing" >/dev/null; then
      ok "可用模型：$PICKED_MODEL"
    else
      warn "这把钥匙目前没有可用额度（多半是今天的免费次数用完了）"
    fi
    return
  fi

  dialog "接下来拿一把「钥匙」，作为助手的备用通道。

免费、不用信用卡，但要先说清楚：
这个免费额度**每天只有二十来次**，所以它只是兜底，
日常干活靠的是上一步装的 Antigravity。

点「知道了」之后我会帮你打开网页，你照着做：

1. 用你的 Google 账号登录
2. 点蓝色按钮「Create API key」（创建密钥）
3. 复制出来的那一长串（以 AIza 开头）
4. 回到这里粘贴

如果网页是英文的，不用怕，按钮位置是固定的。"

  open "https://aistudio.google.com/apikey" >/dev/null 2>&1 || true

  local key tries=0
  while (( tries < 3 )); do
    key="$(ask_text "把复制到的密钥粘贴到下面（以 AIza 开头的那一长串）：")"
    key="$(printf '%s' "${key:-}" | tr -d '[:space:]')"
    if [[ "$key" =~ ^(AIza[A-Za-z0-9_-]{20,}|AQ\.[A-Za-z0-9_.-]{20,})$ ]]; then
      say "  正在验证这把钥匙能不能用…"
      # 必须真发一次生成请求。列模型那个接口在额度为 0 时照样返回 200，
      # 用它验证等于没验——装的时候显示「通过」，用的时候才发现一次都生成不了。
      if probe_any_model "$key" >/dev/null; then
        openclaw config set models.providers.google "{\"apiKey\":\"$key\"}" \
          --strict-json --merge >>"$LOG" 2>&1 || die "写入密钥失败"
        ok "密钥验证通过"
        GEMINI_KEY="$key"
        return
      fi
      warn "这把钥匙 Google 不认，可能是复制时少了几位"
    else
      warn "格式不像（应该以 AIza 开头、很长一串）"
    fi
    (( tries++ ))
  done
  die "密钥试了 3 次都不对。可以稍后重新双击安装程序再来一次。"
}

# ── 4. 选模型 + 装助手的行为规则 ─────────────────────────────────────────
# 挑模型：对候选逐个真发一次最小的生成请求，谁通用谁。
#
# 两条经验是实机踩出来的：
#  · flash 的免费档只有 20 次/天（Google 的原话：limit: 20），flash-lite 高得多，
#    所以**优先 lite**——之前把 lite 排除掉是错的。
#  · 不能只看模型列表。列表接口在额度为 0 时照样返回 200。
PICKED_MODEL=""
probe_any_model() {  # probe_any_model <key> → stdout = 可用的模型名
  local key="$1" json
  json="$(curl -fsS --max-time 25 \
    "https://generativelanguage.googleapis.com/v1beta/models?key=$key" 2>/dev/null)" || return 1

  local names
  names="$(printf '%s' "$json" | tr ',' '\n' | grep -o '"models/[a-z0-9.-]*"' \
           | tr -d '"' | sed 's#^models/##' \
           | grep flash | grep -v image | grep -v tts | sort -u)"
  [[ -z "$names" ]] && return 1

  # lite 在前：它的免费额度最大
  local ordered
  ordered="$(printf '%s\n' "$names" | grep lite; printf '%s\n' "$names" | grep -v lite)"

  local m code
  while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -H 'Content-Type: application/json' -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent?key=$key" \
      -d '{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}' 2>/dev/null)"
    log "probe $m -> HTTP $code"
    if [[ "$code" == "200" ]]; then PICKED_MODEL="$m"; printf '%s' "$m"; return 0; fi
  done <<< "$ordered"
  return 1
}

configure_agent() {
  step "设置助手的大脑和脾气"
  local m="${PICKED_MODEL:-gemini-flash-lite-latest}"
  log "chosen model: $m"
  # OpenClaw 自己的模型目录常常只认一两个 google 模型，lite 往往不在里面，
  # 直接 set primary 会报 Unknown model。所以先把它显式声明进 provider。
  openclaw config set models.providers.google \
    "{\"models\":[{\"id\":\"$m\",\"input\":[\"text\"],\"contextWindow\":1000000,\"contextTokens\":200000,\"maxTokens\":8192,\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}}]}" \
    --strict-json --merge >>"$LOG" 2>&1 || true
  openclaw config set agents.defaults.model.primary "google/$m" >>"$LOG" 2>&1 || true
  openclaw config set memory.search.enabled false >>"$LOG" 2>&1 || true

  # 只有本人能用；群里不说话
  openclaw config set channels.openclaw-weixin \
    '{"dmPolicy":"pairing","groupPolicy":"allowlist"}' --strict-json --merge >>"$LOG" 2>&1 || true

  # 能跑命令，但限制在 allowlist 内
  openclaw config set tools.exec.mode auto >>"$LOG" 2>&1 || true

  ok "大脑：$m"
  ok "只有你能用它，群聊里它不说话"
}

# ── 5. Antigravity CLI（干重活用，免费）──────────────────────────────────
install_agy() {
  step "安装「干重活」的工具 Antigravity（免费）"
  if command -v agy >/dev/null 2>&1; then
    ok "已经装过了：$(agy --version 2>/dev/null | head -1)"
  else
    curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/agy-install.sh 2>>"$LOG" \
      || { warn "下载失败，跳过这一步（不影响聊天功能）"; return; }
    sh /tmp/agy-install.sh >>"$LOG" 2>&1 || { warn "安装失败，跳过（不影响聊天功能）"; return; }
    hash -r
  fi
  command -v agy >/dev/null 2>&1 || { warn "找不到 agy，跳过"; return; }

  if [[ -f "$HOME/.gemini/antigravity-cli/settings.json" ]] \
     && grep -q '"permissions"' "$HOME/.gemini/antigravity-cli/settings.json" 2>/dev/null; then
    ok "已经登录并配置过了"
  else
    dialog "现在装助手的主力大脑：Antigravity。

这一步是**整个安装里最重要的**——它用你的 Google 账号，
额度比后面那个备用通道大得多。跳过的话助手每天只能回二十来条消息。

点「知道了」之后，窗口里会出现一个设置界面，请这样操作：

1. 配色界面 → 直接按回车
2. 条款界面 → 建议按空格键取消勾选「分享数据」，再按回车
3. 登录界面 → 选「用浏览器登录」，在弹出的浏览器里登录 Google
4. 看到输入框（最下面有个 > ）就说明成功了
5. 这时候输入 /quit 再按回车，回到安装程序

整个过程大约 2 分钟。"
    run_visible "Antigravity 登录" "agy" \
      "回车选配色 → 空格取消勾选分享数据 → 回车 → 选浏览器登录 → 看到 > 输入框后敲 /quit" || true

    # 必须确认登录真的成功了。之前的版本跑完 agy 就往下走，
    # 结果使用者在被捕获的环境里根本没完成登录，却一路显示「装好了」。
    local tries=0
    while [[ ! -f "$HOME/.gemini/antigravity-cli/settings.json" ]] && (( tries < 2 )); do
      (( tries++ ))
      warn "没有检测到登录成功的痕迹"
      if ask_yes_no "看起来 Antigravity 还没登录成功。

没有它，助手每天只能回二十来条消息就会停。

要再试一次吗？

• 点「好」→ 再弹一次登录窗口
• 点「跳过」→ 先这样，以后重跑一次安装程序也能补上"; then
        run_visible "Antigravity 登录（重试）" "agy" \
          "回车选配色 → 空格取消分享数据 → 回车 → 浏览器登录 → 敲 /quit 退出" || true
      else
        break
      fi
    done
    if [[ -f "$HOME/.gemini/antigravity-cli/settings.json" ]]; then
      ok "Antigravity 登录成功"
    else
      warn "Antigravity 没登录成功 —— 助手会受每天二十来条的免费额度限制"
      warn "以后想补：打开终端敲 agy，照提示登录一次就行"
    fi
  fi
  "$REPO_DIR/scripts/agy-permissions.sh" >>"$LOG" 2>&1 \
    && ok "已限制它只能在「桌面」和「文稿」里干活" \
    || warn "权限收紧失败，日志：$LOG"

  openclaw approvals allowlist add --agent main "$HOME/.local/bin/agy" >>"$LOG" 2>&1 || true
  for b in /bin/ls /usr/bin/which /usr/bin/git; do
    openclaw approvals allowlist add --agent main "$b" >>"$LOG" 2>&1 || true
  done
  ok "Antigravity 装好了"
}

# ── 6. 启动服务 ──────────────────────────────────────────────────────────
start_gateway() {
  step "让助手开机自动运行"
  openclaw config set gateway.mode local >>"$LOG" 2>&1 || true
  if [[ -n "$PROXY_URL" ]]; then
    openclaw gateway install --force >>"$LOG" 2>&1 || true
  else
    openclaw gateway install >>"$LOG" 2>&1 || true
  fi
  openclaw gateway restart >>"$LOG" 2>&1 || true
  sleep 8
  openclaw gateway status 2>/dev/null | grep -q "running" \
    && ok "服务已启动，以后开机自动运行" \
    || warn "服务可能没起来，装完后可以运行 openclaw gateway status 看看"
}


install_agent_rules() {
  step "写入助手的行为规则"
  local ws="$HOME/.openclaw/workspace" src="$REPO_DIR/assets/AGENTS-friend.md"
  [[ -f "$src" ]] || { warn "找不到规则文件，跳过"; return; }
  mkdir -p "$ws"
  local marker="## 微信助手的行为规则"
  if [[ -f "$ws/AGENTS.md" ]] && grep -qF "$marker" "$ws/AGENTS.md" 2>/dev/null; then
    ok "规则已经写过了（重跑不会重复追加）"
    return
  fi
  cat "$src" >> "$ws/AGENTS.md"
  ok "规则写好了（说人话、不群发、防止被别人指使）"
}

# ── 7. 微信扫码 ──────────────────────────────────────────────────────────
login_wechat() {
  step "连接你的微信"
  if openclaw channels status 2>/dev/null | grep -q "openclaw-weixin.*running"; then
    ok "微信已经连上了"; return
  fi
  dialog "最后一步：连接微信。

点「知道了」之后，这个窗口里会出现一个二维码。

请用手机微信「扫一扫」，然后在手机上点确认。

如果手机要你输入一串数字配对码，就把它敲进这个窗口再回车。

二维码有效期约 8 分钟，扫不上可以重新运行安装程序。"
  run_visible "微信扫码登录" "openclaw channels login --channel openclaw-weixin" \
    "请用手机微信「扫一扫」扫下面的二维码，然后在手机上确认" || warn "扫码流程没有正常完成"
  sleep 3
  openclaw channels status 2>/dev/null | grep -q "openclaw-weixin" \
    && ok "微信连上了" || warn "没检测到微信连接，可以稍后重新运行安装程序"
}

# ── 8. 绘画（可选，要钱）─────────────────────────────────────────────────
setup_drawing() {
  step "绘画功能（可选）"
  if ask_yes_no "要开通「画图」功能吗？

⚠️ 画图是要花钱的：Google 对图像生成没有免费额度，
一张图大约 1 块钱人民币，从你的 Google 账号扣。

需要你去 Google Cloud 开通计费（绑一张信用卡）。

• 点「好」→ 我带你去开通
• 点「跳过」→ 其他功能照常用，以后想加随时可以

（建议先跳过，等用熟了再决定）"; then
    "$REPO_DIR/scripts/add-drawing.sh" || warn "绘画配置没完成，以后可以单独再跑"
  else
    ok "跳过了（以后双击 scripts/添加绘画-Mac.command 可以加上）"
  fi
}

# ── 9. 自检 ──────────────────────────────────────────────────────────────
verify() {
  step "自检"
  local bad=0
  openclaw gateway status 2>/dev/null | grep -q running && ok "服务在跑" || { warn "服务没在跑"; bad=1; }
  openclaw channels status 2>/dev/null | grep -q weixin  && ok "微信已连"  || { warn "微信没连上"; bad=1; }
  command -v agy >/dev/null && ok "Antigravity 可用" || warn "Antigravity 没装上（不影响聊天）"
  # 先单独验证到 Gemini 的通路。不这么做的话，代理没配通会表现成
  # 「助手不回话」，使用者完全猜不到是网络问题。
  local gkey
  gkey="$(openclaw config get models.providers.google.apiKey 2>/dev/null \
          | grep -oE '(AIza|AQ\.)[A-Za-z0-9_.-]{20,}' | head -1)"
  if [[ -n "${gkey:-}" ]]; then
    if curl -fsS --max-time 25 \
        "https://generativelanguage.googleapis.com/v1beta/models?key=$gkey" \
        >/dev/null 2>&1; then
      ok "能连上 Google 的 AI 服务"
    else
      warn "连不上 Google 的 AI 服务"
      bad=1
      if [[ -n "$PROXY_URL" ]]; then
        dialog "助手装好了，但连不上 Google 的 AI 服务。

这是**网络问题，不是助手坏了**。

你的代理是：$PROXY_URL

请检查：
1. 代理软件还开着吗？
2. 浏览器能打开 google.com 吗？

代理软件重启后端口可能会变。端口变了的话，
重新运行一次安装程序就会自动重新探测。"
      else
        dialog "助手装好了，但连不上 Google 的 AI 服务。

这是**网络问题，不是助手坏了**。

如果你在中国大陆，需要先打开代理软件（Clash、v2rayN 这类），
然后重新运行一次安装程序，它会自动探测并配置好。"
      fi
    fi
  fi
  say ""
  say "  正在让助手回一句话试试（可能要等十几秒）…"
  local reply
  reply="$(openclaw agent --message "用一句话介绍你自己，不超过20个字" 2>&1 | tail -3)"
  if [[ -n "$reply" ]]; then ok "助手回话了：$reply"; else warn "助手没回话"; bad=1; fi
  return $bad
}

# ── main ─────────────────────────────────────────────────────────────────
banner
preflight
setup_proxy
pick_jsonrt
install_openclaw
configure_openclaw_proxy
pick_jsonrt
install_wechat_plugin
install_agy
setup_gemini_key
configure_agent
start_gateway
install_agent_rules
login_wechat
setup_drawing

if verify; then
  dialog "装好了！🎉

现在打开微信，给那个助手发条消息试试，比如：

    你好

或者：

    今天天气怎么样

它应该几秒钟内就会回你。

有问题看 docs/常见问题.md"
  say ""
  say "${G}${B}  装好了！打开微信发条消息试试。${N}"
else
  dialog "基本装完了，但有几项没通过自检。

请打开 docs/常见问题.md 对照排查，
或者把这个日志发给帮你装的人：
$LOG"
fi
say ""
say "  日志：$LOG"
say "  按回车键关闭窗口"
read -r _
