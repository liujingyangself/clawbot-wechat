#!/usr/bin/env bash
# 给 Antigravity CLI 配一套有界的权限，避免它读到密钥或动系统。（macOS / Linux）
#
# 优先用 node 处理 JSON：全新的 Mac 上 `python3` 是个占位程序，一调用就弹
# 「要安装开发者工具吗」，对不懂技术的使用者是莫名其妙的打断。
# OpenClaw 装完必然有 node，所以这里几乎总能走到 node 这一支。
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
[[ -f "$SETTINGS" ]] || { echo "agy 还没登录过，跳过"; exit 0; }
cp "$SETTINGS" "$SETTINGS.bak" 2>/dev/null || true

read -r -d '' PATCH_JS <<'JS'
const fs = require("fs"), os = require("os"), path = process.argv[2];
const H = os.homedir();
const cfg = JSON.parse(fs.readFileSync(path, "utf8"));
cfg.permissions = {
  // 优先级是 Deny > Ask > Allow，所以 deny 写在最前面、最硬。
  deny: [
    `read_file(${H}/.ssh)`, `read_file(${H}/.aws)`, `read_file(${H}/.gnupg)`,
    `read_file(${H}/.config)`, `read_file(${H}/Library/Keychains)`,
    `read_file(${H}/.gemini/antigravity-cli/settings.json)`,
    `write_file(${H}/.openclaw)`, `write_file(${H}/Library)`, `write_file(${H}/Applications)`,
    "command(sudo)", "command(rm)", "command(shutdown)", "command(reboot)",
    "command(diskutil)", "command(launchctl)", "command(security)", "command(defaults)",
    "command(ssh)", "command(scp)", "command(rsync)", "command(curl)", "command(wget)",
    "command(git push)", "command(npm publish)", "command(gh release)",
    // 下面这些命令能读任意路径，会绕过上面的 read_file 限制。
    // 读文件要走 agy 自己的原生工具，那条路才受 read_file 约束。
    "command(cat)", "command(head)", "command(tail)", "command(wc)", "command(grep)",
    "command(rg)", "command(find)", "command(xxd)", "command(strings)", "command(od)",
    "command(base64)", "command(cp)", "command(mv)", "command(tar)", "command(zip)",
    "command(python3 -c)", "command(python -c)", "command(node -e)", "command(perl -e)",
    "execute_url(*)",
  ],
  allow: [
    `read_file(${H}/Desktop)`,   `write_file(${H}/Desktop)`,
    `read_file(${H}/Documents)`, `write_file(${H}/Documents)`,
    "command(ls)", "command(which)",
    "command(git status)", "command(git diff)", "command(git log)", "command(git show)",
    "command(git branch)", "command(git add)",
    "command(regex:npm run (build|lint|test|typecheck))",
    "command(npm test)", "command(pytest)", "command(python3 -m pytest)",
  ],
  // 故意不写 ask 通配（比如 command(*)）：它优先级高于 allow，会把上面
  // 所有 allow 规则盖掉，结果是一个工具都用不了。没匹配到规则的本来就默认 Ask。
};
fs.writeFileSync(path, JSON.stringify(cfg, null, 2) + "\n");
console.log("权限已收紧");
JS

if command -v node >/dev/null 2>&1; then
  printf '%s' "$PATCH_JS" > /tmp/agy-perm.js && node /tmp/agy-perm.js "$SETTINGS" && rm -f /tmp/agy-perm.js
elif [[ -x /usr/bin/python3 ]] && /usr/bin/python3 -c '' 2>/dev/null; then
  /usr/bin/python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib, os
p = pathlib.Path(sys.argv[1]); H = os.path.expanduser("~")
cfg = json.loads(p.read_text())
cfg["permissions"] = {
    "deny": [
        f"read_file({H}/.ssh)", f"read_file({H}/.aws)", f"read_file({H}/.gnupg)",
        f"read_file({H}/.config)", f"read_file({H}/Library/Keychains)",
        f"read_file({H}/.gemini/antigravity-cli/settings.json)",
        f"write_file({H}/.openclaw)", f"write_file({H}/Library)", f"write_file({H}/Applications)",
        "command(sudo)", "command(rm)", "command(shutdown)", "command(reboot)",
        "command(diskutil)", "command(launchctl)", "command(security)", "command(defaults)",
        "command(ssh)", "command(scp)", "command(rsync)", "command(curl)", "command(wget)",
        "command(git push)", "command(npm publish)", "command(gh release)",
        "command(cat)", "command(head)", "command(tail)", "command(wc)", "command(grep)",
        "command(rg)", "command(find)", "command(xxd)", "command(strings)", "command(od)",
        "command(base64)", "command(cp)", "command(mv)", "command(tar)", "command(zip)",
        "command(python3 -c)", "command(python -c)", "command(node -e)", "command(perl -e)",
        "execute_url(*)",
    ],
    "allow": [
        f"read_file({H}/Desktop)",   f"write_file({H}/Desktop)",
        f"read_file({H}/Documents)", f"write_file({H}/Documents)",
        "command(ls)", "command(which)",
        "command(git status)", "command(git diff)", "command(git log)", "command(git show)",
        "command(git branch)", "command(git add)",
        "command(regex:npm run (build|lint|test|typecheck))",
        "command(npm test)", "command(pytest)", "command(python3 -m pytest)",
    ],
}
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
print("权限已收紧")
PY
else
  echo "没有 node 也没有可用的 python3，跳过权限收紧" >&2
  exit 1
fi
