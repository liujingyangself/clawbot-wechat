# 给 Antigravity CLI 配一套有界的权限，避免它读到密钥或动系统。（Windows）
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Settings = Join-Path $env:USERPROFILE '.gemini\antigravity-cli\settings.json'
if (-not (Test-Path $Settings)) { Write-Host 'agy 还没登录过，跳过'; exit 0 }
Copy-Item $Settings "$Settings.bak" -Force -ErrorAction SilentlyContinue

$H = $env:USERPROFILE -replace '\\','/'
$cfg = Get-Content $Settings -Raw -Encoding utf8 | ConvertFrom-Json

$deny = @(
  "read_file($H/.ssh)", "read_file($H/.aws)", "read_file($H/.gnupg)",
  "read_file($H/.config)", "read_file($H/AppData/Roaming/Microsoft/Crypto)",
  "read_file($H/.gemini/antigravity-cli/settings.json)",
  "write_file($H/.openclaw)", "write_file($H/AppData)",
  "write_file(C:/Windows)", "write_file(C:/Program Files)",
  'command(runas)', 'command(del)', 'command(rm)', 'command(Remove-Item)',
  'command(shutdown)', 'command(reg)', 'command(sc)', 'command(schtasks)',
  'command(net)', 'command(ssh)', 'command(scp)', 'command(curl)', 'command(wget)',
  'command(Invoke-WebRequest)', 'command(Invoke-RestMethod)',
  'command(git push)', 'command(npm publish)', 'command(gh release)',
  # 下面这些能读任意路径，会绕过上面的 read_file 限制，所以一并封掉；
  # 读文件走 agy 自己的原生工具（那条路受 read_file 约束）。
  'command(type)', 'command(Get-Content)', 'command(cat)', 'command(more)',
  'command(findstr)', 'command(Select-String)', 'command(copy)', 'command(Copy-Item)',
  'command(move)', 'command(tar)', 'command(certutil)',
  'command(python -c)', 'command(python3 -c)', 'command(node -e)',
  'command(powershell -c)', 'command(powershell -Command)',
  'execute_url(*)'
)

$allow = @(
  "read_file($H/Desktop)",   "write_file($H/Desktop)",
  "read_file($H/Documents)", "write_file($H/Documents)",
  'command(dir)', 'command(where)',
  'command(git status)', 'command(git diff)', 'command(git log)', 'command(git show)',
  'command(git branch)', 'command(git add)',
  'command(regex:npm run (build|lint|test|typecheck))',
  'command(npm test)', 'command(pytest)', 'command(python -m pytest)'
)

# 注意：不要加 ask 通配（比如 command(*)）。优先级 Deny > Ask > Allow，
# 通配 ask 会把上面所有 allow 规则盖掉，导致一个工具都用不了。
# 没匹配到任何规则的本来就默认 Ask，不需要显式写。
$perm = [ordered]@{ deny = $deny; allow = $allow }

if ($cfg.PSObject.Properties.Name -contains 'permissions') {
  $cfg.permissions = $perm
} else {
  $cfg | Add-Member -NotePropertyName permissions -NotePropertyValue $perm
}

$cfg | ConvertTo-Json -Depth 10 | Out-File $Settings -Encoding utf8
Write-Host '权限已收紧'
exit 0
