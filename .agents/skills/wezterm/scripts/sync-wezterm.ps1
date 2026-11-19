$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')
$src = Join-Path $repoRoot 'wezterm\config\wezterm.lua'
$dest = Join-Path $env:USERPROFILE '.wezterm.lua'
if (-not (Test-Path -LiteralPath $src)) {
  throw "找不到 $src"
}
$launcher = Join-Path $repoRoot 'wezterm\src\start-herdr.ps1'
$supportDir = Join-Path $env:USERPROFILE '.config\wezterm'
New-Item -ItemType Directory -Path $supportDir -Force | Out-Null
Copy-Item -LiteralPath $launcher -Destination $supportDir -Force
Copy-Item -LiteralPath $src -Destination $dest -Force
Write-Output "synced $src -> $dest"
