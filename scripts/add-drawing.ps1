# 单独开通「画图」功能。需要 Google 已开通计费（图像生成没有免费额度）。
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms

$Log = Join-Path $env:LOCALAPPDATA 'clawbot-wechat\install.log'
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null

function Dlg { param($m)
  [System.Windows.Forms.MessageBox]::Show($m, '开通画图', 'OK', 'Information') | Out-Null }
function AskYesNo { param($m)
  ([System.Windows.Forms.MessageBox]::Show($m, '开通画图', 'YesNo', 'Question') -eq 'Yes') }

$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')
if (-not (Get-Command openclaw -ErrorAction SilentlyContinue)) {
  Dlg '请先运行主安装程序。'; exit 1
}

Dlg @"
开通画图需要两步：

第 1 步：去 Google 给你的账号开通计费（绑一张卡）
第 2 步：回来点确认

我现在帮你打开页面。

⚠️ 再提醒一次：画一张图大约 1 元人民币，按张计费。
不确定的话，现在直接关掉这个窗口就行，不影响其他功能。
"@
Start-Process 'https://aistudio.google.com/apikey'

if (-not (AskYesNo "开通好了吗？`n`n开通之后，原来那把密钥就能画图了，不用换新的。")) {
  Dlg '没关系，以后随时可以再来。'; exit 0
}

openclaw config set agents.defaults.mediaModels.image `
  '{"primary":"google/gemini-3-pro-image-preview"}' --strict-json --merge *>> $Log

$keyOut = (openclaw config get models.providers.google.apiKey 2>$null | Out-String)
$m = [regex]::Match($keyOut, 'AIza[A-Za-z0-9_\-]{20,}')
if (-not $m.Success) { Dlg '没找到密钥，请先跑一遍主安装程序。'; exit 1 }
$key = $m.Value

Write-Host '正在试画一张图确认计费是否生效…'
$uri  = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent?key=$key"
$body = '{"contents":[{"parts":[{"text":"a red circle on white background"}]}]}'
try {
  Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' `
    -Body $body -TimeoutSec 40 -UseBasicParsing | Out-Null
  openclaw gateway restart *>> $Log
  Dlg "画图开通成功！`n`n在微信里发一句「画一只戴帽子的柴犬」试试。"
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 429 -or $code -eq 403) {
    Dlg "密钥是好的，但画图被拒绝了（HTTP $code）。`n`n通常是计费还没真正生效，等几分钟再试一次。`n或者去 Google Cloud 确认账单账号已经关联到这个项目。"
  } else {
    Dlg "测试没能确认成功（$code）。`n`n配置已经写进去了，可以直接在微信里试「画一只猫」。`n还是不行的话看 docs\常见问题.md"
  }
}
