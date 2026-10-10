# 微信 AI 助手 一键安装（Windows）
# 面向完全不懂代码的使用者：每一步都有中文说明，需要人工配合时会弹窗。

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$RepoDir = Split-Path -Parent $PSScriptRoot
$LogDir  = Join-Path $env:LOCALAPPDATA 'clawbot-wechat'
$Log     = Join-Path $LogDir 'install.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# ── 输出与日志 ───────────────────────────────────────────────────────────
function Write-Log  { param($m) "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $Log -Append -Encoding utf8 }
function Say   { param($m) Write-Host $m;                        Write-Log $m }
function Step  { param($m) Write-Host "`n▶ $m" -Fore Cyan;       Write-Log "STEP: $m" }
function OK    { param($m) Write-Host "  ✓ $m" -Fore Green;      Write-Log "OK: $m" }
function Warn  { param($m) Write-Host "  ! $m" -Fore Yellow;     Write-Log "WARN: $m" }
function Die   { param($m)
  Write-Host "  ✗ $m" -Fore Red; Write-Log "FAIL: $m"
  Dlg "安装中断了：$m`n`n详细日志在：`n$Log`n`n把这个文件发给帮你装的人就能看出问题。"
  Read-Host "`n按回车键关闭"; exit 1
}

# ── 弹窗（这是「需要你配合」的提示方式）────────────────────────────────
function Dlg { param($m)
  [System.Windows.Forms.MessageBox]::Show($m, '微信 AI 助手 安装',
    'OK', 'Information') | Out-Null
}
function AskYesNo { param($m)
  $r = [System.Windows.Forms.MessageBox]::Show($m, '微信 AI 助手 安装',
    'YesNo', 'Question')
  return ($r -eq 'Yes')
}
function AskText { param($m)
  return [Microsoft.VisualBasic.Interaction]::InputBox($m, '微信 AI 助手 安装', '')
}

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path','User')
  foreach ($p in @("$env:USERPROFILE\.local\bin", "$env:LOCALAPPDATA\Programs")) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
  }
}
function Has { param($c) [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Banner {
  Clear-Host
  Write-Host @'
  ┌──────────────────────────────────────────────┐
  │                                              │
  │        微信 AI 助手  ·  一键安装              │
  │                                              │
  │   装完之后，你在微信里发消息它就会回你        │
  │                                              │
  └──────────────────────────────────────────────┘

  安装过程中需要你配合 3 次（扫码 / 登录 / 复制密钥），
  到时候会弹窗提醒你，现在可以先去忙别的。

'@ -Fore Cyan
}

# ── 0. 环境检查 ──────────────────────────────────────────────────────────
function Preflight {
  Step '检查电脑环境'
  $v = [Environment]::OSVersion.Version
  if ($v.Major -lt 10) { Die 'Windows 版本太旧，需要 Windows 10 或更新的系统' }
  OK "系统：Windows $($v.Major) ($env:PROCESSOR_ARCHITECTURE)"

  try { Invoke-WebRequest -Uri 'https://www.google.com' -TimeoutSec 10 -UseBasicParsing | Out-Null
        OK '网络正常' }
  catch {
    Warn '连不上 Google'
    if (-not (AskYesNo "检测到连不上 Google。`n`n安装过程需要下载 Google 的工具，如果你在中国大陆，可能需要先打开代理软件。`n`n现在继续吗？（点「否」去开代理）")) {
      Die '请开好网络后重新运行安装程序'
    }
  }
  Write-Log "=== 安装开始 $(Get-Date) ==="
}

# ── 1. OpenClaw（助手的运行底座，自带 Node）──────────────────────────────
function Install-OpenClaw {
  Step '安装运行底座 OpenClaw（这步最久，3-10 分钟）'
  Refresh-Path
  if (Has 'openclaw') { OK "已经装过了：$(openclaw --version 2>$null | Select-Object -First 1)"; return }
  Say '  正在下载安装，请不要关窗口…'
  try {
    $s = Invoke-RestMethod -Uri 'https://openclaw.ai/install.ps1' -UseBasicParsing
    & ([scriptblock]::Create($s)) -NoOnboard *>> $Log
  } catch { Die "OpenClaw 安装失败：$_" }
  Refresh-Path
  if (-not (Has 'openclaw')) { Die "装完了但找不到 openclaw 命令，日志：$Log" }
  OK "OpenClaw $(openclaw --version 2>$null | Select-Object -First 1)"
}

# ── 2. 微信通道插件（腾讯官方）───────────────────────────────────────────
function Install-WeChatPlugin {
  Step '安装微信插件（腾讯官方出品）'
  if ((openclaw plugins list 2>$null | Out-String) -match 'openclaw-weixin') {
    OK '已经装过了'
  } else {
    openclaw plugins install '@tencent-weixin/openclaw-weixin' *>> $Log
    if ($LASTEXITCODE -ne 0) { Die "微信插件安装失败，日志：$Log" }
    OK '微信插件装好了'
  }
  openclaw config set plugins.entries.openclaw-weixin.enabled true *>> $Log
}

# ── 3. Gemini 密钥（免费，不用绑卡）──────────────────────────────────────
function Setup-GeminiKey {
  Step '配置 AI 大脑（Google Gemini）'
  $existing = (openclaw config get models.providers.google.apiKey 2>$null | Out-String)
  if ($existing -match 'AIza[A-Za-z0-9_\-]{20,}') { OK '已经配过密钥了'; return }

  Dlg @"
接下来要拿一把「钥匙」，让助手能用上 Google 的 AI。

这是免费的，不需要信用卡。

点「确定」之后我会帮你打开网页，你照着做：

1. 用你的 Google 账号登录
2. 点蓝色按钮「Create API key」（创建密钥）
3. 复制出来的那一长串（以 AIza 开头）
4. 回到这里粘贴

如果网页是英文的，不用怕，按钮位置是固定的。
"@
  Start-Process 'https://aistudio.google.com/apikey'

  for ($i = 0; $i -lt 3; $i++) {
    $key = (AskText '把复制到的密钥粘贴到下面（以 AIza 开头的那一长串）：') -replace '\s',''
    if ($key -match '^AIza[A-Za-z0-9_\-]{20,}$') {
      Say '  正在验证这把钥匙能不能用…'
      try {
        Invoke-RestMethod -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$key" `
          -TimeoutSec 25 -UseBasicParsing | Out-Null
        openclaw config set models.providers.google "{`"apiKey`":`"$key`"}" --strict-json --merge *>> $Log
        $script:GeminiKey = $key
        OK '密钥验证通过'; return
      } catch { Warn '这把钥匙 Google 不认，可能是复制时少了几位' }
    } else { Warn '格式不像（应该以 AIza 开头、很长一串）' }
  }
  Die '密钥试了 3 次都不对。可以稍后重新运行安装程序再来一次。'
}

# ── 4. 选模型 + 装助手的行为规则 ─────────────────────────────────────────
# 从 Google 实际返回的模型列表里挑一个 flash，而不是写死名字——
# 模型名每隔几个月就会变，写死的话以后装就会挂。
function Choose-Model {
  $fallback = 'google/gemini-3-flash-preview'
  if (-not $script:GeminiKey) { return $fallback }
  try {
    $r = Invoke-RestMethod -TimeoutSec 25 -UseBasicParsing `
      -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$($script:GeminiKey)"
  } catch { return $fallback }
  $ok = @($r.models |
    Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } |
    ForEach-Object { $_.name -replace '^models/','' } |
    Where-Object { $_ -like '*flash*' -and $_ -notlike '*image*' `
                   -and $_ -notlike '*tts*' -and $_ -notlike '*lite*' })
  foreach ($re in @('^gemini-3(\.\d+)?-flash$','^gemini-3(\.\d+)?-flash-preview$','^gemini-flash-latest$')) {
    $hit = $ok | Where-Object { $_ -match $re } | Select-Object -First 1
    if ($hit) { return "google/$hit" }
  }
  if ($ok.Count -gt 0) { return "google/$($ok[0])" }
  return $fallback
}

function Configure-Agent {
  Step '设置助手的大脑和脾气'
  $model = Choose-Model
  Write-Log "chosen model: $model"
  openclaw config set agents.defaults.model.primary $model *>> $Log
  openclaw config set memory.search.enabled false *>> $Log
  openclaw config set channels.openclaw-weixin '{"dmPolicy":"pairing","groupPolicy":"allowlist"}' --strict-json --merge *>> $Log
  openclaw config set tools.exec.mode auto *>> $Log

  OK "大脑：$($model -replace '^google/','')（免费额度）"
  OK '只有你能用它，群聊里它不说话'
}

# ── 5. Antigravity CLI（干重活用，免费）──────────────────────────────────
function Install-Agy {
  Step '安装「干重活」的工具 Antigravity（免费）'
  Refresh-Path
  if (Has 'agy') {
    OK "已经装过了：$(agy --version 2>$null | Select-Object -First 1)"
  } else {
    try {
      $s = Invoke-RestMethod -Uri 'https://antigravity.google/cli/install.ps1' -UseBasicParsing
      & ([scriptblock]::Create($s)) *>> $Log
    } catch { Warn '安装失败，跳过这一步（不影响聊天功能）'; return }
    Refresh-Path
  }
  if (-not (Has 'agy')) { Warn '找不到 agy，跳过（不影响聊天功能）'; return }

  $settings = Join-Path $env:USERPROFILE '.gemini\antigravity-cli\settings.json'
  if ((Test-Path $settings) -and ((Get-Content $settings -Raw) -match '"permissions"')) {
    OK '已经登录并配置过了'
  } else {
    Dlg @"
马上要让 Antigravity 登录你的 Google 账号。

点「确定」之后，窗口里会出现一个设置界面，请这样操作：

1. 配色界面 → 直接按回车
2. 条款界面 → 建议按空格键取消勾选「分享数据」，再按回车
3. 登录界面 → 选「用浏览器登录」，在弹出的浏览器里登录 Google
4. 看到输入框（最下面有个 > ）就说明成功了
5. 这时候输入 /quit 再按回车，回到安装程序

整个过程大约 2 分钟。
"@
    agy
  }
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'agy-permissions.ps1') *>> $Log
  if ($LASTEXITCODE -eq 0) { OK '已限制它只能在「桌面」和「文档」里干活' } else { Warn "权限收紧失败，日志：$Log" }

  $agyPath = (Get-Command agy -ErrorAction SilentlyContinue).Source
  if ($agyPath) { openclaw approvals allowlist add --agent main $agyPath *>> $Log }
  OK 'Antigravity 装好了'
}

# ── 6. 启动服务 ──────────────────────────────────────────────────────────
function Start-Gateway {
  Step '让助手开机自动运行'
  openclaw config set gateway.mode local *>> $Log
  openclaw gateway install *>> $Log
  openclaw gateway restart *>> $Log
  Start-Sleep -Seconds 8
  if ((openclaw gateway status 2>$null | Out-String) -match 'running') {
    OK '服务已启动，以后开机自动运行'
  } else { Warn '服务可能没起来，装完后可以运行 openclaw gateway status 看看' }
}


function Install-AgentRules {
  Step '写入助手的行为规则'
  $ws  = Join-Path $env:USERPROFILE '.openclaw\workspace'
  $src = Join-Path $RepoDir 'assets\AGENTS-friend.md'
  if (-not (Test-Path $src)) { Warn '找不到规则文件，跳过'; return }
  New-Item -ItemType Directory -Force -Path $ws | Out-Null
  $dst = Join-Path $ws 'AGENTS.md'
  $marker = '## 微信助手的行为规则'
  if ((Test-Path $dst) -and ((Get-Content $dst -Raw -Encoding utf8) -like "*$marker*")) {
    OK '规则已经写过了（重跑不会重复追加）'; return
  }
  Get-Content $src -Raw -Encoding utf8 | Out-File $dst -Append -Encoding utf8
  OK '规则写好了（说人话、不群发、防止被别人指使）'
}

# ── 7. 微信扫码 ──────────────────────────────────────────────────────────
function Login-WeChat {
  Step '连接你的微信'
  if ((openclaw channels status 2>$null | Out-String) -match 'openclaw-weixin.*running') {
    OK '微信已经连上了'; return
  }
  Dlg @"
最后一步：连接微信。

点「确定」之后，这个窗口里会出现一个二维码。

请用手机微信「扫一扫」，然后在手机上点确认。

如果手机要你输入一串数字配对码，就把它敲进这个窗口再回车。

二维码有效期约 8 分钟，扫不上可以重新运行安装程序。
"@
  openclaw channels login --channel openclaw-weixin
  Start-Sleep -Seconds 3
  if ((openclaw channels status 2>$null | Out-String) -match 'openclaw-weixin') {
    OK '微信连上了'
  } else { Warn '没检测到微信连接，可以稍后重新运行安装程序' }
}

# ── 8. 绘画（可选，要钱）─────────────────────────────────────────────────
function Setup-Drawing {
  Step '绘画功能（可选）'
  $msg = @"
要开通「画图」功能吗？

⚠️ 画图是要花钱的：Google 对图像生成没有免费额度，
一张图大约 1 块钱人民币，从你的 Google 账号扣。

需要你去 Google 开通计费（绑一张信用卡）。

• 点「是」→ 我带你去开通
• 点「否」→ 其他功能照常用，以后想加随时可以

（建议先选「否」，等用熟了再决定）
"@
  if (AskYesNo $msg) {
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'add-drawing.ps1')
  } else {
    OK '跳过了（以后双击 scripts\添加绘画-Windows.bat 可以加上）'
  }
}

# ── 9. 自检 ──────────────────────────────────────────────────────────────
function Verify {
  Step '自检'
  $bad = 0
  if ((openclaw gateway status 2>$null | Out-String) -match 'running') { OK '服务在跑' }
    else { Warn '服务没在跑'; $bad = 1 }
  if ((openclaw channels status 2>$null | Out-String) -match 'weixin')  { OK '微信已连' }
    else { Warn '微信没连上'; $bad = 1 }
  if (Has 'agy') { OK 'Antigravity 可用' } else { Warn 'Antigravity 没装上（不影响聊天）' }

  Say ''
  Say '  正在让助手回一句话试试（可能要等十几秒）…'
  $reply = (openclaw agent --message '用一句话介绍你自己，不超过20个字' 2>&1 | Out-String).Trim()
  if ($reply) { OK "助手回话了：$reply" } else { Warn '助手没回话'; $bad = 1 }
  return $bad
}

# ── main ─────────────────────────────────────────────────────────────────
Banner
Preflight
Install-OpenClaw
Install-WeChatPlugin
Setup-GeminiKey
Configure-Agent
Install-Agy
Start-Gateway
Install-AgentRules
Login-WeChat
Setup-Drawing

if ((Verify) -eq 0) {
  Dlg "装好了！🎉`n`n现在打开微信，给那个助手发条消息试试，比如：`n`n    你好`n`n或者：`n`n    今天天气怎么样`n`n它应该几秒钟内就会回你。`n`n有问题看 docs\常见问题.md"
  Say ''
  Write-Host '  装好了！打开微信发条消息试试。' -Fore Green
} else {
  Dlg "基本装完了，但有几项没通过自检。`n`n请打开 docs\常见问题.md 对照排查，`n或者把这个日志发给帮你装的人：`n$Log"
}
Say ''
Say "  日志：$Log"
Read-Host '  按回车键关闭窗口'
