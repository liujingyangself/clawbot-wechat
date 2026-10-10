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

$tarUrl = "https://codeload.github.com/$Repo/zip/refs/heads/$Branch"
$downloaded = $false

Write-Host '  正在下载安装包…'
try {
  Invoke-WebRequest -Uri $tarUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
  $downloaded = $true
} catch {
  # 直连不行，找找本机的代理软件再试一次（国内常见情况）
  Write-Host '  直连失败，正在找你电脑上的代理软件…'
  $cands = @('http://127.0.0.1:7890','http://127.0.0.1:7897','http://127.0.0.1:10809',
             'http://127.0.0.1:1087','http://127.0.0.1:8889','http://127.0.0.1:2080')
  # 系统代理设置里写的那个也试一下（Clash 的「系统代理」开关就是改这里）
  try {
    $reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($reg.ProxyEnable -eq 1 -and $reg.ProxyServer) {
      $s = $reg.ProxyServer; if ($s -notmatch '://') { $s = "http://$s" }
      $cands = @($s) + $cands
    }
  } catch {}
  foreach ($u in $cands) {
    try {
      Invoke-WebRequest -Uri $tarUrl -OutFile $zip -UseBasicParsing -TimeoutSec 90 -Proxy $u
      Write-Host "  ✓ 通过代理下载成功（$u）" -Fore Green
      # 传给安装脚本，省得它再探一遍
      $env:HTTP_PROXY = $u; $env:HTTPS_PROXY = $u
      $env:http_proxy = $u; $env:https_proxy = $u
      $env:NO_PROXY = 'localhost,127.0.0.1,::1'; $env:no_proxy = $env:NO_PROXY
      $downloaded = $true
      break
    } catch { }
  }
}

if (-not $downloaded -or -not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) {
  Die '下载失败。如果你在中国大陆，请先打开代理软件（Clash、v2rayN 这类），确认浏览器能打开 google.com，然后重新运行这条命令。'
}

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
