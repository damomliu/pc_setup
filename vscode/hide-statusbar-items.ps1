<#
.SYNOPSIS
    將指定 Status Bar 項目加入所有現有 VS Code Profiles 的隱藏清單。
.DESCRIPTION
    需要 sqlite3。保留其他隱藏項目，並備份修改前的值到 repo 的 backup/。
    建議關閉 VS Code 後執行；執行中套用時，須重新開啟 VS Code 才會載入。
#>
param()

$ErrorActionPreference = 'Stop'
$sqlite = (Get-Command sqlite3 -ErrorAction Stop).Source
$userRoot = Join-Path $env:APPDATA 'Code\User'
$targets = @('status.problems', 'mhutchie.git-graph', 'Anthropic.claude-code')
$profiles = @([pscustomobject]@{ name = 'Default'; location = $null })
$storage = Get-Content (Join-Path $userRoot 'globalStorage\storage.json') -Raw | ConvertFrom-Json
$profiles += @($storage.userDataProfiles)
$backupRoot = Join-Path $PSScriptRoot "..\backup\vscode-statusbar-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

foreach ($profile in $profiles) {
    $root = if ($profile.location) { Join-Path $userRoot "profiles\$($profile.location)" } else { $userRoot }
    $db = Join-Path $root 'globalStorage\state.vscdb'
    $old = $null
    if (Test-Path -LiteralPath $db) {
        $old = & $sqlite -batch $db "SELECT value FROM ItemTable WHERE key='workbench.statusbar.hidden';"
        if ($LASTEXITCODE -ne 0) { throw "Cannot read $db" }
    }
    $hidden = if ($old) { @($old | ConvertFrom-Json) } else { @() }
    $missing = @($targets | Where-Object { $_ -cnotin $hidden })
    if ($missing.Count -eq 0) {
        Write-Host "[$($profile.name)] already hidden"
        continue
    }
    $backupName = if ($profile.location) { $profile.location -replace '[/\\]', '_' } else { 'Default' }
    @{ database = $db; previousValue = $old } | ConvertTo-Json | Set-Content (Join-Path $backupRoot "$backupName.json") -Encoding utf8
    $json = ConvertTo-Json -InputObject @($hidden + $missing) -Compress
    $escaped = $json.Replace("'", "''")
    New-Item -ItemType Directory -Path (Split-Path $db) -Force | Out-Null
    $sql = "BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB); INSERT OR REPLACE INTO ItemTable (key,value) VALUES ('workbench.statusbar.hidden','$escaped'); COMMIT;"
    $sql | & $sqlite -batch -cmd '.timeout 5000' $db
    if ($LASTEXITCODE -ne 0) { throw "Cannot update $db" }
    $actual = & $sqlite -batch $db "SELECT value FROM ItemTable WHERE key='workbench.statusbar.hidden';"
    if ($LASTEXITCODE -ne 0 -or $actual -cne $json) { throw "Verification failed: $db" }
    Write-Host "[$($profile.name)] hidden and verified"
}
Write-Host 'Restart VS Code to load the updated Status Bar state.'
