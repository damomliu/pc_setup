<#
.SYNOPSIS
    在 repo 的 ai-agent/ 與 Windows、WSL 之間同步 Claude Code 設定與共用規則。

.DESCRIPTION
    預設：repo -> Windows 與 WSL。
      claude-settings.json      -> ~/.claude/settings.json（WSL 版先合併 claude-settings.wsl.json）
      claude-settings.cli.json  -> ~/.claude/settings.cli.json
      claude-keybindings.json   -> ~/.claude/keybindings.json
      claude-statusline.py      -> ~/.claude/statusline.py
      AGENTS.md                 -> ~/.claude/CLAUDE.md
    任何目標內容與 repo 不同（Claude Code 自己會寫 settings.json）時整批中止，不寫入；
    確認要覆蓋加 -Force，要保留本機變更先用 -PullWin / -PullWsl 收回。
    -PullWin：Windows -> repo（WSL 專屬差異請手動改 claude-settings.wsl.json）。
    -PullWsl：WSL -> repo；WSL settings.json 須等於 repo 合併結果（不同即中止，請手動改 claude-settings.json 或 claude-settings.wsl.json），
      相同則略過 settings.json，其餘檔案收回。
    -Check：只比對，不複製。
    WSL settings.json 合併規則：object 逐層合併；permissions 底下的陣列取聯集；其餘值由 override 取代。
    需要 PowerShell 7。
#>
param(
    [switch]$PullWin,
    [switch]$PullWsl,
    [switch]$Check,
    [switch]$Force,
    [string]$Distro = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)
if ($PullWin -and $PullWsl) { throw '-PullWin 與 -PullWsl 不能同時使用' }

# repo 檔 -> 家目錄下的相對路徑
$map = [ordered]@{
    'claude-settings.json'     = @('.claude\settings.json')
    'claude-settings.cli.json' = @('.claude\settings.cli.json')
    'claude-keybindings.json'  = @('.claude\keybindings.json')
    'claude-statusline.py'     = @('.claude\statusline.py')
    'AGENTS.md'                = @('.claude\CLAUDE.md')
}

function Merge-Settings($base, $over, [string]$path = '') {
    foreach ($k in $over.Keys) {
        $b = $base[$k]; $o = $over[$k]
        if ($b -is [System.Collections.IDictionary] -and $o -is [System.Collections.IDictionary]) {
            Merge-Settings $b $o "$path.$k" | Out-Null
        } elseif ($path -eq '.permissions' -and $b -is [System.Collections.IList] -and $o -is [System.Collections.IList]) {
            $base[$k] = @($b) + @($o | Where-Object { $_ -notin $b })
        } else {
            $base[$k] = $o
        }
    }
    $base
}

function Read-Json([string]$file) { Get-Content $file -Raw | ConvertFrom-Json -AsHashtable }

# 遞迴排序 object key（ordinal），array 保持原順序，供比對時忽略 key 順序
function ConvertTo-Sorted($v) {
    if ($v -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in [string[]]$v.Keys | Sort-Object { $_ } -CaseSensitive) { $o[$k] = ConvertTo-Sorted $v[$k] }
        return $o
    }
    if ($v -is [System.Collections.IList]) {
        return , @($v | ForEach-Object { ConvertTo-Sorted $_ })
    }
    $v
}

# 內容是否相同：JSON 比語意（忽略排版與 object key 順序），其他比 bytes
function Test-Same([string]$target, [byte[]]$bytes, [bool]$isJson) {
    if (-not (Test-Path $target)) { return $false }
    if ($isJson) {
        $want = ConvertTo-Sorted ($utf8.GetString($bytes) | ConvertFrom-Json -AsHashtable) | ConvertTo-Json -Depth 32 -Compress
        $have = ConvertTo-Sorted (Read-Json $target) | ConvertTo-Json -Depth 32 -Compress
        return $want -eq $have
    }
    return [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($target), $bytes)
}

# 取得 WSL 家目錄
$wslHome = (wsl -d $Distro -- printenv HOME | Out-String).Trim()
if (-not $wslHome) { throw "讀不到 WSL ($Distro) 的 HOME" }
$wslRoot = "\\wsl.localhost\$Distro" + ($wslHome -replace '/', '\')

# repo 合併 WSL 專屬設定後的 settings.json bytes
function Get-WslSettingsBytes {
    $merged = Merge-Settings (Read-Json (Join-Path $repo 'claude-settings.json')) (Read-Json (Join-Path $repo 'claude-settings.wsl.json'))
    $utf8.GetBytes(($merged | ConvertTo-Json -Depth 32) + "`n")
}

if ($PullWin -or $PullWsl) {
    $srcRoot = if ($PullWsl) { $wslRoot } else { $HOME }
    $skip = @()
    if ($PullWsl) {
        # WSL settings.json 須等於 repo 合併結果，否則無法判斷該回收到母版還是 WSL 專屬檔
        $wslSettings = Join-Path $wslRoot $map['claude-settings.json'][0]
        if (-not (Test-Same $wslSettings (Get-WslSettingsBytes) $true)) {
            Write-Error "已中止，未收回任何檔案。WSL settings.json 與 repo 合併結果不同：$wslSettings`n請手動編輯 claude-settings.json 或 claude-settings.wsl.json。"
        }
        $skip = @('claude-settings.json')
    }
    foreach ($src in $map.Keys | Where-Object { $_ -notin $skip }) {
        $from = Join-Path $srcRoot $map[$src][0]
        $to = Join-Path $repo $src
        Copy-Item $from $to -Force
        Write-Host "$from -> $to"
    }
    return
}

$plan = foreach ($src in $map.Keys) {
    $srcPath = Join-Path $repo $src
    $isJson = $src -like '*.json'
    $bytes = [System.IO.File]::ReadAllBytes($srcPath)
    foreach ($rel in $map[$src]) {
        [pscustomobject]@{ Target = Join-Path $HOME $rel; Bytes = $bytes; IsJson = $isJson }
        $wslBytes = $bytes
        if ($src -eq 'claude-settings.json') {
            $wslBytes = Get-WslSettingsBytes
        }
        [pscustomobject]@{ Target = Join-Path $wslRoot $rel; Bytes = $wslBytes; IsJson = $isJson }
    }
}

foreach ($p in $plan) {
    $p | Add-Member State $(if (-not (Test-Path $p.Target)) { 'missing' } elseif (Test-Same $p.Target $p.Bytes $p.IsJson) { 'same' } else { 'differs' })
}

if ($Check) {
    $plan | Select-Object State, Target | Format-Table -AutoSize
    return
}

$differs = @($plan | Where-Object State -eq 'differs')
if ($differs -and -not $Force) {
    $differs | ForEach-Object { Write-Warning "內容與 repo 不同：$($_.Target)" }
    Write-Error '已中止，未寫入任何檔案。要覆蓋加 -Force；要保留本機變更先跑 -PullWin / -PullWsl。'
}

foreach ($p in $plan | Where-Object State -ne 'same') {
    New-Item -ItemType Directory -Force (Split-Path $p.Target) | Out-Null
    [System.IO.File]::WriteAllBytes($p.Target, $p.Bytes)
    Write-Host "[$($p.State)] -> $($p.Target)"
}
Write-Host "已同步；$(@($plan | Where-Object State -eq 'same').Count) 個檔案原本就相同。"
