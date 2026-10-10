#!/usr/bin/env python3
"""改完脚本必须跑这个。

存在的原因：之前有两次把跑不起来的脚本推上了线。
`bash -n` 和「here-string 配对」这类检查对下面这些错误完全无效：

  · 批量替换时连带删掉了函数定义 —— 语法合法，运行时才 command not found
  · 字符串尾部多一个引号 —— PowerShell 要到解析时才报错，Mac 上查不出来
  · .ps1 丢了 UTF-8 BOM —— 中文 Windows 用 GBK 解析，汉字会破坏引号闭合
  · google provider 少写 api / baseUrl —— 配置能写进去，每次调用才失败

用法：  python3 scripts/selfcheck.py
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FAIL: list[str] = []
WARN: list[str] = []


def fail(msg: str) -> None:
    FAIL.append(msg)
    print(f"  ✗ {msg}")


def ok(msg: str) -> None:
    print(f"  ✓ {msg}")


# ── 1. .ps1 必须带 UTF-8 BOM ──────────────────────────────────────────────
# 中文 Windows 的 PowerShell 5.1 默认按 GBK/CP936 解析无 BOM 的 .ps1，
# 多字节汉字会破坏引号和花括号的闭合，报 "The string is missing the terminator"。
def check_bom() -> None:
    print("\n[1] PowerShell 脚本的 UTF-8 BOM")
    for p in sorted(ROOT.rglob("*.ps1")):
        if ".git" in p.parts:
            continue
        rel = p.relative_to(ROOT)
        if p.read_bytes()[:3] == b"\xef\xbb\xbf":
            ok(f"{rel}")
        else:
            fail(f"{rel} 缺 UTF-8 BOM —— 中文 Windows 上必然语法报错")


# ── 2. bash 语法 ──────────────────────────────────────────────────────────
def check_bash_syntax() -> None:
    print("\n[2] bash 语法")
    for p in sorted(list(ROOT.rglob("*.sh")) + list(ROOT.rglob("*.command"))):
        if ".git" in p.parts:
            continue
        rel = p.relative_to(ROOT)
        r = subprocess.run(["bash", "-n", str(p)], capture_output=True, text=True)
        if r.returncode == 0:
            ok(f"{rel}")
        else:
            fail(f"{rel}: {r.stderr.strip().splitlines()[0] if r.stderr.strip() else '语法错误'}")


# ── 3. 调用了但没定义的函数 ────────────────────────────────────────────────
# 这是前两次翻车的真正原因：批量替换切掉了一整段函数定义，
# 而语法检查完全看不出来。
BASH_BUILTIN = {
    "echo", "printf", "read", "local", "return", "export", "source", "command", "eval",
    "cat", "curl", "chmod", "mkdir", "rm", "cp", "mv", "sleep", "trap", "hash", "exec",
    "grep", "sed", "awk", "tr", "wc", "head", "tail", "find", "date", "seq", "tar",
    "osascript", "open", "node", "python3", "openclaw", "agy", "mb", "git", "ls", "which",
    "xattr", "scutil", "sw_vers", "uname", "nc", "ping", "dirname", "basename", "mktemp",
    "pwd", "cd", "test", "set", "unset", "shift", "exit", "true", "false", "type", "jq",
    "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
}

PS_BUILTIN_RE = re.compile(
    r"^(Write|Read|Get|Set|New|Add|Remove|Start|Stop|Restart|Test|Join|Split|Select|Where|"
    r"ForEach|Invoke|Convert|ConvertTo|ConvertFrom|Out|Copy|Move|Expand|Enable|Disable|"
    r"Unblock|Clear|Import|Export|Measure|Sort|Compare|Resolve|Push|Pop)-"
)


def check_bash_funcs(p: pathlib.Path) -> list[str]:
    t = p.read_text()
    defined = set(re.findall(r"^([a-z_][a-z0-9_]*)\s*\(\)\s*\{", t, re.M))
    called = set()
    for m in re.finditer(r"(?:^|\n)\s*([a-z_][a-z0-9_]{2,})(?=\s+[\"'$]|\s*$)", t):
        called.add(m.group(1))
    return sorted(c for c in called if c not in defined and c not in BASH_BUILTIN)


def check_ps_funcs(p: pathlib.Path) -> list[str]:
    t = p.read_text(encoding="utf-8-sig")
    defined = set(re.findall(r"^function\s+([A-Za-z][\w-]*)", t, re.M))
    called = set()
    for m in re.finditer(r"(?:^|\n)\s*([A-Z][\w]*-[\w]+|Dlg|AskYesNo|AskText|OK|NG|ER|Say|Step|Warn|Die|Has)\b", t):
        called.add(m.group(1))
    return sorted(
        c for c in called
        if c not in defined and not PS_BUILTIN_RE.match(c)
    )


def check_undefined() -> None:
    print("\n[3] 调用了但没定义的函数")
    for p in sorted(ROOT.rglob("*.sh")):
        if ".git" in p.parts:
            continue
        miss = check_bash_funcs(p)
        rel = p.relative_to(ROOT)
        ok(f"{rel}") if not miss else fail(f"{rel} 调用了未定义的: {', '.join(miss)}")
    for p in sorted(ROOT.rglob("*.ps1")):
        if ".git" in p.parts:
            continue
        miss = check_ps_funcs(p)
        rel = p.relative_to(ROOT)
        ok(f"{rel}") if not miss else fail(f"{rel} 调用了未定义的: {', '.join(miss)}")


# ── 4. PowerShell here-string 配对 ────────────────────────────────────────
def check_herestrings() -> None:
    print("\n[4] PowerShell here-string 配对")
    for p in sorted(ROOT.rglob("*.ps1")):
        if ".git" in p.parts:
            continue
        t = p.read_text(encoding="utf-8-sig")
        rel = p.relative_to(ROOT)
        opened = t.count('@"')
        closed = t.count('"@')
        if opened == closed:
            ok(f"{rel}")
        else:
            fail(f"{rel} here-string 不配对（{opened} 开 / {closed} 闭）")


# ── 5. google provider 的三件套 ───────────────────────────────────────────
# 少任何一个都会出现「配置写进去了但每次调用都失败」，而报错完全看不出关联。
def check_google_decl() -> None:
    print("\n[5] google provider 必须同时有 api / baseUrl / 模型级 api")
    for name in ("scripts/install.sh", "scripts/install.ps1"):
        p = ROOT / name
        t = p.read_text(encoding="utf-8-sig")
        missing = []
        if t.count("google-generative-ai") < 2:
            missing.append("模型级 api（provider 级和模型级各需要一个）")
        if "generativelanguage.googleapis.com/v1beta" not in t:
            missing.append("baseUrl")
        ok(name) if not missing else fail(f"{name} 缺: {', '.join(missing)}")


def main() -> int:
    print("微信 AI 助手 · 脚本自检")
    print("=" * 56)
    check_bom()
    check_bash_syntax()
    check_undefined()
    check_herestrings()
    check_google_decl()
    print("\n" + "=" * 56)
    if FAIL:
        print(f"✗ {len(FAIL)} 项不通过，不要提交：")
        for f in FAIL:
            print(f"    · {f}")
        return 1
    print("✓ 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
