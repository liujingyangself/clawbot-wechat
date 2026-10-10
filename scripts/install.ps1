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
Add-Type -AssemblyName System.Drawing
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

# ── 提示（需要使用者配合时）──────────────────────────────────────────────
# 设计原则：**终端永远打印一份，弹窗只是加强提醒**。
# 弹窗可能被别的窗口挡住、可能在非交互环境下根本不显示，
# 如果它是唯一的渠道，使用者就会对着一个没反应的窗口发呆。
# 所以这里永远先写到终端，再尝试弹窗；弹窗失败就退回终端交互。

# 判断有没有可用的交互桌面。被 AI 代理或 CI 以重定向方式调起时为 false。
$script:Interactive = $true
$script:RealConsole = $true
try {
  if ([Console]::IsInputRedirected -or $Host.Name -eq 'Default Host') { $script:Interactive = $false }
  # 输出被捕获时，二维码这类「画在屏幕上」的东西使用者根本看不到——
  # 它们会进到调用方（比如 AI 代理）的缓冲区里。
  if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { $script:RealConsole = $false }
  if ($env:TERM_PROGRAM -eq 'vscode' -and -not [Console]::IsOutputRedirected) { $script:RealConsole = $true }
} catch { $script:Interactive = $false; $script:RealConsole = $false }

# 二维码、agy 的登录界面这些必须真人盯着屏幕看。
# 但这个安装器的设计目标是「丢给 AI 代理全自动装完，人只辅助扫码」，
# 所以输出被捕获时**不能停下来让人手动跑**——那等于把活又推回给人。
# 正确做法：自己弹一个使用者看得见的新窗口来做这一步，跑完自动回到主流程。
function Invoke-Visible { param($Title, $Command, $Hint)
  if ($script:RealConsole) {
    # 已经在真终端里，直接跑就行，不用多开窗口
    Write-Host ''
    Write-Host "  $Hint" -Fore Yellow
    Invoke-Expression $Command
    return $true
  }

  Write-Host ''
  Write-Host ('─' * 64) -Fore Yellow
  Write-Host "  正在弹出一个新窗口：$Title" -Fore Yellow
  Write-Host "  $Hint"
  Write-Host '  请在那个新窗口里操作，完成后它会自动回到这里继续。'
  Write-Host ('─' * 64) -Fore Yellow
  Write-Log "VISIBLE-STEP: $Title"

  $inner = @"
`$host.UI.RawUI.WindowTitle = '$Title'
`$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ';' + `$env:Path
Write-Host ''
Write-Host '  $Hint' -Fore Yellow
Write-Host ''
$Command
Write-Host ''
Write-Host '  这一步完成了。' -Fore Green
Start-Sleep -Seconds 2
"@
  $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
  try {
    $proc = Start-Process -FilePath 'powershell.exe' `
      -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$b64 `
      -PassThru -WindowStyle Normal -ErrorAction Stop
  } catch {
    ER "弹不出新窗口：$($_.Exception.Message)"
    return $false
  }
  # 最多等 15 分钟（扫码二维码本身约 8 分钟就过期）
  if (-not $proc.WaitForExit(900000)) {
    try { $proc.Kill() } catch {}
    Warn "$Title 超时了"
    return $false
  }
  return $true
}

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

  Write-Log "=== 安装开始 $(Get-Date) ===""
}


# ── 代理（中国大陆几乎必需）──────────────────────────────────────────────
# 要解决的坑：使用者开着 Clash 的「系统代理」，浏览器能上 Google，以为网络没问题；
# 但 Node.js 不读系统代理，OpenClaw 的后台服务照样连不上 Gemini，
# 报的错还完全看不出是代理问题。
$script:ProxyUrl = ''

# 只探 http://：OpenClaw 的 proxy.proxyUrl 不支持 socks5
$script:ProxyCandidates = @(
  'http://127.0.0.1:7890',   # Clash / Clash for Windows
  'http://127.0.0.1:7897',   # Clash Verge Rev
  'http://127.0.0.1:10809',  # v2rayN
  'http://127.0.0.1:1087',
  'http://127.0.0.1:8889',
  'http://127.0.0.1:2080',   # Nekoray
  'http://127.0.0.1:8080'
)

function Test-Google { param($ProxyUrl)
  try {
    if ($ProxyUrl) {
      Invoke-WebRequest 'https://www.google.com' -Proxy $ProxyUrl -TimeoutSec 8 -UseBasicParsing | Out-Null
    } else {
      Invoke-WebRequest 'https://www.google.com' -TimeoutSec 8 -UseBasicParsing | Out-Null
    }
    return $true
  } catch { return $false }
}

function Find-Proxy {
  # 先看 IE/系统代理设置里写了什么（Clash 的「系统代理」开关就是改这里）
  try {
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($reg.ProxyEnable -eq 1 -and $reg.ProxyServer) {
      $srv = $reg.ProxyServer
      if ($srv -notmatch '://') { $srv = "http://$srv" }
      if (Test-Google $srv) { return $srv }
    }
  } catch {}
  foreach ($u in $script:ProxyCandidates) { if (Test-Google $u) { return $u } }
  return ''
}

function Set-ProxyEnv {
  $env:HTTP_PROXY  = $script:ProxyUrl; $env:http_proxy  = $script:ProxyUrl
  $env:HTTPS_PROXY = $script:ProxyUrl; $env:https_proxy = $script:ProxyUrl
  $env:NO_PROXY    = 'localhost,127.0.0.1,::1'; $env:no_proxy = $env:NO_PROXY
  # PowerShell 的 Invoke-WebRequest 默认不读这些环境变量，要显式设默认代理
  try { [Net.WebRequest]::DefaultWebProxy = New-Object Net.WebProxy($script:ProxyUrl, $true) } catch {}
  Write-Log "proxy in use: $($script:ProxyUrl)"
}

function Setup-Proxy {
  Step '检查能不能连上 Google'

  # get.ps1 可能已经探到代理并传下来了。不先认领的话，下面的检测会因为
  # 带着环境变量而成功，误判成「能直连」，代理就不会写进 OpenClaw 配置。
  $inherited = if ($env:HTTPS_PROXY) { $env:HTTPS_PROXY } else { $env:https_proxy }
  if ($inherited) {
    $script:ProxyUrl = $inherited; Set-ProxyEnv
    OK "沿用上一步探到的代理：$($script:ProxyUrl)"; return
  }

  if (Test-Google $null) { OK '能直连，不需要代理'; return }

  Warn '连不上 Google'
  Say '  正在自动寻找你电脑上的代理软件…'
  $found = Find-Proxy
  if ($found) {
    $script:ProxyUrl = $found; Set-ProxyEnv
    OK "找到可用代理：$found"
    Dlg @"
检测到你在用代理软件，地址是：

    $found

我会让助手也走这个代理，这样它才能用上 Google 的 AI。

（微信的消息不会绕到国外——代理软件会自己按规则分流，
国内的网站和微信走直连。）
"@
    return
  }

  Dlg @"
连不上 Google，而且没找到正在运行的代理软件。

请先打开你的代理软件（Clash、v2rayN 这类），
确认浏览器能打开 google.com，然后点「确定」继续。

如果你的软件只开了 socks5 端口，需要在它的设置里
把「HTTP 代理」也打开——这个助手只能用 HTTP 代理。
"@
  $found = Find-Proxy
  if ($found) { $script:ProxyUrl = $found; Set-ProxyEnv; OK "找到了：$found"; return }

  $manual = (AskText '还是没找到。请手动填写代理端口号（只填数字，在你代理软件的设置里能看到，常见的是 7890）：') -replace '\D',''
  if ($manual) {
    $u = "http://127.0.0.1:$manual"
    if (Test-Google $u) { $script:ProxyUrl = $u; Set-ProxyEnv; OK "代理可用：$u"; return }
    Warn "通过 127.0.0.1:$manual 还是连不上 Google"
  }
  Die '没有可用的网络。请先确保代理软件正常工作（浏览器能打开 google.com），再重新运行安装程序。'
}

# OpenClaw 装好之后把代理写进它自己的配置。
# 必须写进 config——只设环境变量的话，后台服务重装时会丢。
function Configure-OpenClawProxy {
  if (-not $script:ProxyUrl) { return }
  Step '让助手也走代理'
  openclaw config set proxy.proxyUrl $script:ProxyUrl *>> $Log
  if ($LASTEXITCODE -ne 0) { Warn '写入代理配置失败'; return }
  # agy 是 Go 程序，会读 HTTPS_PROXY；写进服务的持久环境，
  # 这样后台服务拉起 agy 的时候也能走代理。
  $envf = Join-Path $env:USERPROFILE '.openclaw\.env'
  New-Item -ItemType Directory -Force -Path (Split-Path $envf) | Out-Null
  $keep = @()
  if (Test-Path $envf) {
    $keep = Get-Content $envf | Where-Object { $_ -notmatch '^(HTTPS?_PROXY|NO_PROXY)=' }
  }
  $keep += "HTTP_PROXY=$($script:ProxyUrl)"
  $keep += "HTTPS_PROXY=$($script:ProxyUrl)"
  $keep += 'NO_PROXY=localhost,127.0.0.1,::1'
  $keep | Set-Content $envf -Encoding utf8
  OK "助手的网络已指向 $($script:ProxyUrl)"
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
  Step '配置备用通道（Google Gemini）'
  $existing = (openclaw config get models.providers.google.apiKey 2>$null | Out-String)
  if ($existing -match '(AIza|AQ\.)[A-Za-z0-9_.\-]{20,}') {
    OK '已经配过密钥了'
    # 重跑时也要探一次。只认「配过」就跳过的话，等于在没验证的情况下配置模型——
    # 密钥可能早就没额度了，而使用者要到发消息时才发现。
    Say '  正在确认这把钥匙现在还能用…'
    if (Probe-AnyModel $matches[0]) { OK "可用模型：$($script:PickedModel)" }
    else { Warn '这把钥匙目前没有可用额度（多半是今天的免费次数用完了）' }
    return
  }

  Dlg @"
接下来拿一把「钥匙」，作为助手的备用通道。

免费、不用信用卡，但要先说清楚：
这个免费额度每天只有二十来次，所以它只是兜底，
日常干活靠的是上一步装的 Antigravity。

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
    if ($key -match '^(AIza[A-Za-z0-9_\-]{20,}|AQ\.[A-Za-z0-9_.\-]{20,})$') {
      Say '  正在验证这把钥匙能不能用…'
      try {
        # 必须真发一次生成请求：列模型接口在额度为 0 时照样返回 200
        if (-not (Probe-AnyModel $key)) { throw '这把钥匙没有可用的生成额度' }
        openclaw config set models.providers.google "{`"apiKey`":`"$key`"}" --strict-json --merge *>> $Log
        $script:GeminiKey = $key
        OK '密钥验证通过'; return
      } catch { Warn '这把钥匙 Google 不认，可能是复制时少了几位' }
    } else { Warn '格式不像（应该以 AIza 开头、很长一串）' }
  }
  Die '密钥试了 3 次都不对。可以稍后重新运行安装程序再来一次。'
}

# ── 4. 选模型 + 装助手的行为规则 ─────────────────────────────────────────
# 挑模型：对候选逐个真发一次最小的生成请求，谁通用谁。
#
# 两条经验是实机踩出来的：
#  · flash 的免费档只有 20 次/天（Google 原话：limit: 20），flash-lite 高得多，
#    所以**优先 lite**——之前把 lite 排除掉是错的。
#  · 不能只看模型列表：列表接口在额度为 0 时照样返回 200，用它验证等于没验。
$script:PickedModel = ''
function Probe-AnyModel { param($key)
  try {
    $all = Invoke-RestMethod -TimeoutSec 25 -UseBasicParsing `
      -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$key"
  } catch { return '' }

  $flash = @($all.models |
    Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } |
    ForEach-Object { $_.name -replace '^models/','' } |
    Where-Object { $_ -like '*flash*' -and $_ -notlike '*image*' -and $_ -notlike '*tts*' })
  # lite 在前：它的免费额度最大
  $ordered = @($flash | Where-Object { $_ -like '*lite*' }) +
             @($flash | Where-Object { $_ -notlike '*lite*' })

  foreach ($m in $ordered) {
    try {
      Invoke-RestMethod -TimeoutSec 20 -UseBasicParsing -Method Post -ContentType 'application/json' `
        -Uri "https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent?key=$key" `
        -Body '{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}' | Out-Null
      Write-Log "probe $m -> OK"
      $script:PickedModel = $m
      return $m
    } catch { Write-Log "probe $m -> $($_.Exception.Message)" }
  }
  return ''
}

function Configure-Agent {
  Step '设置助手的大脑和脾气'
  $m = if ($script:PickedModel) { $script:PickedModel } else { 'gemini-flash-lite-latest' }
  Write-Log "chosen model: $m"
  # OpenClaw 自己的模型目录常常只认一两个 google 模型，lite 往往不在里面，
  # 直接 set primary 会报 Unknown model。所以先把它显式声明进 provider。
  # 两件事必须一起做：
  #  · 声明模型 —— OpenClaw 的目录里往往没有 lite，不声明会报 Unknown model
  #  · 指定 api  —— 一旦给 google 加了 models 数组，OpenClaw 会把它当成自定义
  #    provider，接口格式回落成 openai-responses，于是每次调用都失败
  #    （日志里会看到 `api=openai-responses model=...`）
  $decl = '{"api":"google-generative-ai","models":[{"id":"' + $m + '","input":["text"],"contextWindow":1000000,"contextTokens":200000,"maxTokens":8192,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0}}]}'
  openclaw config set models.providers.google $decl --strict-json --merge *>> $Log
  openclaw config set agents.defaults.model.primary "google/$m" *>> $Log
  openclaw config set memory.search.enabled false *>> $Log
  openclaw config set channels.openclaw-weixin '{"dmPolicy":"pairing","groupPolicy":"allowlist"}' --strict-json --merge *>> $Log
  openclaw config set tools.exec.mode auto *>> $Log

  OK "大脑：$m"
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
现在装助手的主力大脑：Antigravity。

这一步是整个安装里最重要的 —— 它用你的 Google 账号，
额度比后面那个备用通道大得多。跳过的话助手每天只能回二十来条消息。

点「确定」之后，窗口里会出现一个设置界面，请这样操作：

1. 配色界面 → 直接按回车
2. 条款界面 → 建议按空格键取消勾选「分享数据」，再按回车
3. 登录界面 → 选「用浏览器登录」，在弹出的浏览器里登录 Google
4. 看到输入框（最下面有个 > ）就说明成功了
5. 这时候输入 /quit 再按回车，回到安装程序

整个过程大约 2 分钟。
"@
    Invoke-Visible 'Antigravity 登录' 'agy' `
      '回车选配色 → 空格取消勾选分享数据 → 回车 → 选浏览器登录 → 看到 > 输入框后敲 /quit' | Out-Null

    # 必须确认登录真的成功了。之前的版本跑完 agy 就往下走，
    # 结果使用者在被捕获的环境里根本没完成登录，却一路显示「装好了」。
    $tries = 0
    while ((-not (Test-Path $settings)) -and $tries -lt 2) {
      $tries++
      Warn '没有检测到登录成功的痕迹'
      if (AskYesNo "看起来 Antigravity 还没登录成功。`n`n没有它，助手每天只能回二十来条消息就会停。`n`n要再试一次吗？`n`n• 是 → 再弹一次登录窗口`n• 否 → 先这样，以后重跑一次安装程序也能补上") {
        Invoke-Visible 'Antigravity 登录（重试）' 'agy' `
          '回车选配色 → 空格取消分享数据 → 回车 → 浏览器登录 → 敲 /quit 退出' | Out-Null
      } else { break }
    }
    if (Test-Path $settings) { OK 'Antigravity 登录成功' }
    else {
      Warn 'Antigravity 没登录成功 —— 助手会受每天二十来条的免费额度限制'
      Warn '以后想补：打开 PowerShell 敲 agy，照提示登录一次就行'
    }
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
  if ($script:ProxyUrl) { openclaw gateway install --force *>> $Log }
  else { openclaw gateway install *>> $Log }
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
  Invoke-Visible '微信扫码登录' 'openclaw channels login --channel openclaw-weixin' `
    '请用手机微信「扫一扫」扫下面的二维码，然后在手机上确认' | Out-Null
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

  # 先单独验证到 Gemini 的通路。不这么做的话，代理没配通会表现成
  # 「助手不回话」，使用者完全猜不到是网络问题。
  $keyOut = (openclaw config get models.providers.google.apiKey 2>$null | Out-String)
  $km = [regex]::Match($keyOut, '(AIza|AQ\.)[A-Za-z0-9_.\-]{20,}')
  if ($km.Success) {
    try {
      Invoke-RestMethod -TimeoutSec 25 -UseBasicParsing `
        -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$($km.Value)" | Out-Null
      OK '能连上 Google 的 AI 服务'
    } catch {
      Warn '连不上 Google 的 AI 服务'; $bad = 1
      if ($script:ProxyUrl) {
        Dlg "助手装好了，但连不上 Google 的 AI 服务。`n`n这是网络问题，不是助手坏了。`n`n你的代理是：$($script:ProxyUrl)`n`n请检查：`n1. 代理软件还开着吗？`n2. 浏览器能打开 google.com 吗？`n`n代理软件重启后端口可能会变。端口变了的话，`n重新运行一次安装程序就会自动重新探测。"
      } else {
        Dlg "助手装好了，但连不上 Google 的 AI 服务。`n`n这是网络问题，不是助手坏了。`n`n如果你在中国大陆，需要先打开代理软件（Clash、v2rayN 这类），`n然后重新运行一次安装程序，它会自动探测并配置好。"
      }
    }
  }
  Say ''
  Say '  正在让助手回一句话试试（可能要等十几秒）…'
  $reply = (openclaw agent --message '用一句话介绍你自己，不超过20个字' 2>&1 | Out-String).Trim()
  if ($reply) { OK "助手回话了：$reply" } else { Warn '助手没回话'; $bad = 1 }
  return $bad
}

# ── main ─────────────────────────────────────────────────────────────────
Banner
Preflight
Setup-Proxy
Install-OpenClaw
Configure-OpenClawProxy
Install-WeChatPlugin
Install-Agy
Setup-GeminiKey
Configure-Agent
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
