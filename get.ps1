# 一行安装的引导脚本（Windows）
#
#   irm https://raw.githubusercontent.com/liujingyangself/clawbot-wechat/main/get.ps1 | iex
#
# 它只做三件事：把仓库下载下来、放到一个固定位置、然后把安装交给 scripts\install.ps1。

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Repo   = 'liujingyangself/clawbot-wechat'
$Branch = if ($env:CLAWBOT_BRANCH) { $env:CLAWBOT_BRANCH } else { 'main' }
$Dest   = if ($env:CLAWBOT_DIR)    { $env:CLAWBOT_DIR }    else { Join-Path $env:USERPROFILE 'clawbot-wechat' }

function Die { param($m) Write-Host "✗ $m" -Fore Red; Read-Host '按回车键关闭'; exit 1 }

Write-Host ''
Write-Host '微信 AI 助手 · 正在准备安装' -Fore Cyan
Write-Host ''

# 安装过程要扫二维码、要在 Antigravity 登录界面按键，必须有真正的控制台。
if ($Host.Name -eq 'Default Host' -or [Console]::IsInputRedirected) {
  Die '需要在 PowerShell 窗口里运行。请在开始菜单搜索 PowerShell 打开，再把那条命令粘进去回车。'
}

# TLS 1.2：Windows PowerShell 5.1 默认可能谈不下来 GitHub 的连接
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$tmp = Join-Path $env:TEMP ("clawbot-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zip = Join-Path $tmp 'src.zip'

try {
  Write-Host '  正在下载安装包…'
  Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/refs/heads/$Branch" `
    -OutFile $zip -UseBasicParsing -TimeoutSec 120
} catch {
  Die '下载失败。检查网络（在中国大陆可能需要先开代理），然后重新运行。'
}

if (-not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) { Die '下载下来是空的，请重试。' }

try {
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
} catch { Die '解压失败，请重试。' }

$src = Get-ChildItem $tmp -Directory | Select-Object -First 1
if (-not $src) { Die '安装包结构不对，请重试。' }

# 重装时先清掉旧的，避免新旧文件混在一起
if (Test-Path $Dest) {
  Write-Host '  发现已有副本，正在更新…'
  Remove-Item $Dest -Recurse -Force
}
Move-Item $src.FullName $Dest -Force
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

$installer = Join-Path $Dest 'scripts\install.ps1'
if (-not (Test-Path $installer)) { Die '安装包不完整（缺 scripts\install.ps1），请重试。' }

# GitHub 下载的文件会被标记为「来自网络」，不解除的话执行会被挡
Get-ChildItem $Dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

Write-Host "  ✓ 准备好了：$Dest" -Fore Green
Write-Host ''

& $installer
