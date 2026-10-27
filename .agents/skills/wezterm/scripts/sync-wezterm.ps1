$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$src = Join-Path $repoRoot 'wezterm\config\wezterm.lua'
$dest = Join-Path $env:USERPROFILE '.wezterm.lua'
if (-not (Test-Path -LiteralPath $src)) {
  throw "找不到 $src"
}
Copy-Item -LiteralPath $src -Destination $dest -Force
Write-Output "synced $src -> $dest"
