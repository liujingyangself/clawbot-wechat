#!/usr/bin/env bash
# 单独开通「画图」功能。需要 Google Cloud 已开通计费（图像生成没有免费额度）。
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
LOG="$HOME/Library/Logs/clawbot-wechat-install.log"

dlg() {
  osascript -e "display dialog \"$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/\"/\\\\\"/g')\" \
    buttons {\"知道了\"} default button \"知道了\" with title \"开通画图\"" >/dev/null 2>&1 || true
}

command -v openclaw >/dev/null || { dlg "请先运行主安装程序。"; exit 1; }

dlg "开通画图需要两步：

第 1 步：去 Google 给你的账号开通计费（绑一张卡）
第 2 步：回来点确认

我现在帮你打开页面。

⚠️ 再提醒一次：画一张图大约 1 元人民币，按张计费。
不确定的话，现在直接关掉这个窗口就行，不影响其他功能。"

open "https://aistudio.google.com/apikey" >/dev/null 2>&1 || true

osascript -e 'display dialog "开通好了吗？

开通之后，原来那把密钥就能画图了，不用换新的。" \
  buttons {"还没","开通好了"} default button "开通好了" with title "开通画图"' 2>/dev/null \
  | grep -q "开通好了" || { dlg "没关系，以后随时可以再来。"; exit 0; }

openclaw config set agents.defaults.mediaModels.image \
  '{"primary":"google/gemini-3-pro-image-preview"}' --strict-json --merge >>"$LOG" 2>&1

KEY="$(openclaw config get models.providers.google.apiKey 2>/dev/null \
       | grep -o 'AIza[A-Za-z0-9_-]*' | head -1)"

if [[ -z "${KEY:-}" ]]; then
  dlg "没找到密钥，请先跑一遍主安装程序。"
  exit 1
fi

echo "正在试画一张图确认计费是否生效…"
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 40 \
  -H 'Content-Type: application/json' -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent?key=$KEY" \
  -d '{"contents":[{"parts":[{"text":"a red circle on white background"}]}]}' 2>/dev/null)"

case "$CODE" in
  200)
    openclaw gateway restart >>"$LOG" 2>&1
    dlg "画图开通成功！

在微信里发一句「画一只戴帽子的柴犬」试试。" ;;
  429|403)
    dlg "密钥是好的，但画图被拒绝了（HTTP $CODE）。

通常是计费还没真正生效，等几分钟再试一次。
或者去 Google Cloud 确认账单账号已经关联到这个项目。" ;;
  *)
    dlg "测试返回 HTTP $CODE，没能确认成功。

配置已经写进去了，可以直接在微信里试「画一只猫」。
还是不行的话看 docs/常见问题.md" ;;
esac
