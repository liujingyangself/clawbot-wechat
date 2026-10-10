# 诊断：这把密钥到底哪个模型能用（Windows）
# 专治「助手回复 429 / RESOURCE_EXHAUSTED」。
# 它会对每个候选模型真发一次最小的生成请求，而不是只问「模型列表」——
# 列表接口在额度为 0 时照样返回 200，验不出问题。

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:Path

Write-Host ''
Write-Host '微信 AI 助手 · 额度诊断' -Fore Cyan
Write-Host ('─' * 60)

# 1. 取出已配置的密钥和模型
$keyOut = (openclaw config get models.providers.google.apiKey 2>$null | Out-String)
$m = [regex]::Match($keyOut, 'AIza[A-Za-z0-9_\-]{20,}')
if (-not $m.Success) { Write-Host '没找到密钥，请先跑一遍安装程序。' -Fore Red; Read-Host '按回车关闭'; exit 1 }
$key = $m.Value
$cur = (openclaw config get agents.defaults.model.primary 2>$null | Out-String).Trim()
Write-Host "  密钥：$($key.Substring(0,8))…$($key.Substring($key.Length-4))"
Write-Host "  当前配置的模型：$cur"
Write-Host ''

# 2. 列出这把密钥能看到的 flash 系模型（这一步不花额度）
try {
  $all = Invoke-RestMethod -TimeoutSec 25 -UseBasicParsing `
    -Uri "https://generativelanguage.googleapis.com/v1beta/models?key=$key"
} catch { Write-Host "连不上 Google：$_" -Fore Red; Read-Host '按回车关闭'; exit 1 }

$flash = @($all.models |
  Where-Object { $_.supportedGenerationMethods -contains 'generateContent' } |
  ForEach-Object { $_.name -replace '^models/','' } |
  Where-Object { $_ -like '*flash*' -and $_ -notlike '*image*' -and $_ -notlike '*tts*' })

# 先试非 lite，再试 lite（lite 往往才是免费档真正有量的那个）
$ordered = @($flash | Where-Object { $_ -notlike '*lite*' }) + @($flash | Where-Object { $_ -like '*lite*' })
Write-Host "  能看到 $($flash.Count) 个 flash 模型，逐个真打一次最小请求："
Write-Host ''

# 3. 对每个模型真发一次生成请求
$works = @()
foreach ($mdl in $ordered) {
  $uri  = "https://generativelanguage.googleapis.com/v1beta/models/${mdl}:generateContent?key=$key"
  $body = '{"contents":[{"parts":[{"text":"hi"}]}],"generationConfig":{"maxOutputTokens":1}}'
  try {
    Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' `
      -Body $body -TimeoutSec 30 -UseBasicParsing | Out-Null
    Write-Host ("    [可用]   " + $mdl) -Fore Green
    $works += $mdl
  } catch {
    $code = $null
    try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
    switch ($code) {
      429 { Write-Host ("    [无额度] " + $mdl + "  (429 配额耗尽/免费档为 0)") -Fore Yellow }
      404 { Write-Host ("    [不存在] " + $mdl) -Fore DarkGray }
      403 { Write-Host ("    [无权限] " + $mdl + "  (403)") -Fore Yellow }
      default { Write-Host ("    [失败]   " + $mdl + "  (HTTP $code)") -Fore Red }
    }
  }
}

Write-Host ''
Write-Host ('─' * 60)
if ($works.Count -gt 0) {
  $pick = $works[0]
  Write-Host "  找到能用的模型：$pick" -Fore Green
  if ("google/$pick" -ne $cur) {
    Write-Host "  当前配的是 $cur，正在改成 google/$pick …"
    openclaw config set agents.defaults.model.primary "google/$pick" | Out-Null
    openclaw gateway restart | Out-Null
    Write-Host '  改好了，去微信里再发条消息试试。' -Fore Green
  } else {
    Write-Host '  配置已经是它了。那 429 多半是当天额度用完，等明天再试。' -Fore Yellow
  }
} else {
  Write-Host '  没有任何模型可用。' -Fore Red
  Write-Host ''
  Write-Host '  这说明这把密钥没有免费的生成额度。常见原因：'
  Write-Host '    1. 这个 Google 项目的免费档确实是 0（Google 在收紧免费额度）'
  Write-Host '    2. 当天的免费次数已经用完（免费档可能只有几十次/天）'
  Write-Host ''
  Write-Host '  可以做的：'
  Write-Host '    · 等 24 小时再试（如果是用完了）'
  Write-Host '    · 换一个 Google 账号重新申请密钥'
  Write-Host '    · 去 https://aistudio.google.com/apikey 开通计费（按量付费，很便宜）'
}
Write-Host ''
Read-Host '按回车关闭'
