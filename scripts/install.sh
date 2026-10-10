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

# ── 弹窗（这是「需要你配合」的提示方式）────────────────────────────────
dialog() {  # dialog <正文>
  osascript -e "display dialog \"$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')\" \
    buttons {\"知道了\"} default button \"知道了\" with title \"微信 AI 助手 安装\"" >/dev/null 2>&1 || true
}
ask_yes_no() {  # ask_yes_no <正文> → 0=是 1=否
  osascript -e "display dialog \"$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')\" \
    buttons {\"跳过\",\"好\"} default button \"好\" with title \"微信 AI 助手 安装\"" 2>/dev/null \
    | grep -q "好"
}
ask_text() {  # ask_text <正文> → stdout = 使用者输入
  osascript -e "display dialog \"$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')\" \
    default answer \"\" buttons {\"取消\",\"确定\"} default button \"确定\" \
    with title \"微信 AI 助手 安装\"" 2>/dev/null \
    | sed -n 's/.*text returned:\(.*\)$/\1/p'
}


# ── JSON 运行时：优先 node（OpenClaw 装完就有），其次 python3 ──────────────
# 不直接用 python3，是因为全新的 Mac 上 `python3` 是个占位程序，
# 一调用就弹「要安装开发者工具吗」，对不懂技术的人是莫名其妙的打断。
JSONRT=""
pick_jsonrt() {
  if command -v node >/dev/null 2>&1; then JSONRT=node
  elif [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c '' 2>/dev/null; then JSONRT=/usr/bin/python3
  else JSONRT=""; fi
  log "json runtime: ${JSONRT:-none}"
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

  if ! curl -fsS --max-time 10 -o /dev/null https://www.google.com 2>/dev/null; then
    warn "连不上 Google。安装需要访问 Google 和 npm，请确认网络（可能需要代理）。"
    ask_yes_no "检测到连不上 Google。

安装过程需要下载 Google 的工具，如果你在中国大陆，
可能需要先打开代理软件。

现在继续，还是先去开代理？" || die "请开好网络后重新双击安装"
  else
    ok "网络正常"
  fi
  log "=== 安装开始 $(date) ==="
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
  step "配置 AI 大脑（Google Gemini）"

  local existing
  existing="$(openclaw config get models.providers.google.apiKey 2>/dev/null | grep -o 'AIza[A-Za-z0-9_-]*' | head -1)"
  if [[ -n "${existing:-}" ]]; then ok "已经配过密钥了"; return; fi

  dialog "接下来要拿一把「钥匙」，让助手能用上 Google 的 AI。

这是免费的，不需要信用卡。

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
    if [[ "$key" =~ ^AIza[A-Za-z0-9_-]{20,}$ ]]; then
      say "  正在验证这把钥匙能不能用…"
      if curl -fsS --max-time 25 \
          "https://generativelanguage.googleapis.com/v1beta/models?key=$key" \
          >/dev/null 2>>"$LOG"; then
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
# 从 Google 实际返回的模型列表里挑一个 flash，而不是写死名字——
# 模型名每隔几个月就会变，写死的话以后装就会挂。
choose_model() {
  local fallback="google/gemini-3-flash-preview"
  [[ -z "${JSONRT:-}" || -z "${GEMINI_KEY:-}" ]] && { echo "$fallback"; return; }
  local json
  json="$(curl -fsS --max-time 25 \
    "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_KEY" 2>/dev/null)" \
    || { echo "$fallback"; return; }
  local picked=""
  if [[ "$JSONRT" == node ]]; then
    picked="$(printf '%s' "$json" | node -e '
      let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
        let ms=[];try{ms=(JSON.parse(s).models||[])}catch(e){}
        const ok=ms.filter(m=>(m.supportedGenerationMethods||[]).includes("generateContent"))
                   .map(m=>(m.name||"").replace(/^models\//,""))
                   .filter(n=>n.includes("flash")&&!n.includes("image")&&!n.includes("tts")&&!n.includes("lite"));
        const pref=[/^gemini-3(\.\d+)?-flash$/,/^gemini-3(\.\d+)?-flash-preview$/,/^gemini-flash-latest$/];
        for(const re of pref){const h=ok.find(n=>re.test(n));if(h){console.log(h);return;}}
        console.log(ok[0]||"");
      });' 2>/dev/null)"
  else
    picked="$(printf '%s' "$json" | "$JSONRT" -c '
import sys,json,re
try: ms=json.load(sys.stdin).get("models",[])
except Exception: ms=[]
ok=[m.get("name","").replace("models/","") for m in ms
    if "generateContent" in m.get("supportedGenerationMethods",[])]
ok=[n for n in ok if "flash" in n and not any(x in n for x in ("image","tts","lite"))]
for pat in (r"^gemini-3(\.\d+)?-flash$", r"^gemini-3(\.\d+)?-flash-preview$", r"^gemini-flash-latest$"):
    hit=[n for n in ok if re.match(pat,n)]
    if hit: print(hit[0]); sys.exit()
print(ok[0] if ok else "")' 2>/dev/null)"
  fi
  [[ -n "$picked" ]] && echo "google/$picked" || echo "$fallback"
}

configure_agent() {
  step "设置助手的大脑和脾气"
  local model; model="$(choose_model)"
  log "chosen model: $model"
  openclaw config set agents.defaults.model.primary "$model" >>"$LOG" 2>&1 || true
  openclaw config set memory.search.enabled false >>"$LOG" 2>&1 || true

  # 只有本人能用；群里不说话
  openclaw config set channels.openclaw-weixin \
    '{"dmPolicy":"pairing","groupPolicy":"allowlist"}' --strict-json --merge >>"$LOG" 2>&1 || true

  # 能跑命令，但限制在 allowlist 内
  openclaw config set tools.exec.mode auto >>"$LOG" 2>&1 || true

  ok "大脑：${model#google/}（免费额度）"
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
    dialog "马上要让 Antigravity 登录你的 Google 账号。

点「知道了」之后，窗口里会出现一个设置界面，请这样操作：

1. 配色界面 → 直接按回车
2. 条款界面 → 建议按空格键取消勾选「分享数据」，再按回车
3. 登录界面 → 选「用浏览器登录」，在弹出的浏览器里登录 Google
4. 看到输入框（最下面有个 > ）就说明成功了
5. 这时候输入 /quit 再按回车，回到安装程序

整个过程大约 2 分钟。"
    agy || true
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
  openclaw gateway install >>"$LOG" 2>&1 || true
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
  openclaw channels login --channel openclaw-weixin || warn "扫码流程退出了"
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
pick_jsonrt
install_openclaw
pick_jsonrt
install_wechat_plugin
setup_gemini_key
configure_agent
install_agy
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
