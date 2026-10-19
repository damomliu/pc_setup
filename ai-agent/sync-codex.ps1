<#
.SYNOPSIS
    在 repo 的 ai-agent/ 與 Windows、WSL 之間同步 Codex 設定與共用規則。

.DESCRIPTION
    預設：repo -> Windows 與 WSL。
      AGENTS.md         -> ~/.codex/AGENTS.md（整檔覆寫）
      codex-config.toml -> ~/.codex/config.toml（只合併 repo 列出的 key，其餘設定原樣保留）
    config.toml 合併規則：repo 檔只能有 [section] header 與單行 key = value（不含 [[array]]、dotted key、多行值）；
      key 依所屬 section 比對（第一個 [ header 之前為 top-level），同名 key 就地取代，缺的 key 插在該 section 尾端，
      目標檔沒有該 section 就接在檔尾新增。
      沿用目標檔的換行字元，UTF-8 無 BOM；目標不存在則直接用 repo 內容建立。
    狀態：missing（目標不存在）、same（內容已一致）、update（只缺 key，直接補上不需 -Force）、
      differs（受管 key 已存在但值不同，例如在 Codex 用 /permissions 改過）。
    有 differs 時整批中止，不寫入；確認要覆蓋加 -Force，要保留本機變更先用 -PullWin / -PullWsl 收回。
    -PullWin / -PullWsl：Windows 或 WSL -> repo（AGENTS.md 整檔複製；codex-config.toml 只把已列出的 key 改為來源現值，不新增 key）。
    -Check：只比對，不寫入。
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
    'AGENTS.md'         = '.codex\AGENTS.md'
    'codex-config.toml' = '.codex\config.toml'
}

# 把 TOML 文字拆成：行陣列與換行字元
function Split-Toml([string]$text) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($text -split '\r?\n'))
    [pscustomobject]@{ Lines = $lines; Nl = $nl }
}

# 取得 section 內容的行範圍 [Start, End)；section 為空字串代表 top-level（第一個 [ header 之前）；找不到回傳 $null
function Get-Section($toml, [string]$section) {
    $start = 0
    if ($section) {
        $start = -1
        for ($i = 0; $i -lt $toml.Lines.Count; $i++) {
            if ($toml.Lines[$i] -match ('^\s*\[\s*' + [regex]::Escape($section) + '\s*\]\s*(#.*)?$')) { $start = $i + 1; break }
        }
        if ($start -lt 0) { return $null }
    }
    $end = $toml.Lines.Count
    for ($i = $start; $i -lt $toml.Lines.Count; $i++) {
        if ($toml.Lines[$i] -match '^\s*\[') { $end = $i; break }
    }
    [pscustomobject]@{ Start = $start; End = $end }
}

# 讀 section 中 key 的行號與值；找不到回傳 $null
function Find-Key($toml, [string]$section, [string]$key) {
    $range = Get-Section $toml $section
    if (-not $range) { return $null }
    for ($i = $range.Start; $i -lt $range.End; $i++) {
        if ($toml.Lines[$i] -match ('^\s*' + [regex]::Escape($key) + '\s*=\s*(.*?)\s*$')) {
            return [pscustomobject]@{ Index = $i; Value = $Matches[1] }
        }
    }
    $null
}

# 解析 repo 的 codex-config.toml：只允許 [section] header 與單行 key = value，其他一律 throw
function Read-ManagedKeys([string]$file) {
    $section = ''
    foreach ($raw in [System.IO.File]::ReadAllText($file) -split '\r?\n') {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([A-Za-z0-9_.-]+)\]$') { $section = $Matches[1]; continue }
        if ($line -notmatch '^([A-Za-z0-9_-]+)\s*=\s*(\S.*)$') { throw "無法解析 $file 的這一行（只支援 [section] 與單行 key = value）：$line" }
        [pscustomobject]@{ Section = $section; Key = $Matches[1]; Value = $Matches[2] }
    }
}

# 把受管 key 合併進目標檔文字，回傳 Bytes 與 State（update / differs / same）
function Merge-Toml([string]$text, $keys) {
    $toml = Split-Toml $text
    $state = 'same'
    foreach ($k in $keys) {
        $hit = Find-Key $toml $k.Section $k.Key
        $line = "$($k.Key) = $($k.Value)"
        if ($hit) {
            if ($hit.Value -ne $k.Value) {
                $toml.Lines[$hit.Index] = $line
                $state = 'differs'
            }
        } else {
            $range = Get-Section $toml $k.Section
            if ($range) {
                # 插在 section 最後一個非空行之後
                $at = $range.End
                while ($at -gt $range.Start -and -not $toml.Lines[$at - 1].Trim()) { $at-- }
                $toml.Lines.Insert($at, $line)
            } else {
                # section 不存在：接在檔尾最後一個非空行之後
                $at = $toml.Lines.Count
                while ($at -gt 0 -and -not $toml.Lines[$at - 1].Trim()) { $at-- }
                $new = @("[$($k.Section)]", $line)
                if ($at -gt 0) { $new = @('') + $new }
                $toml.Lines.InsertRange($at, [string[]]$new)
            }
            if ($state -eq 'same') { $state = 'update' }
        }
    }
    [pscustomobject]@{ State = $state; Bytes = $utf8.GetBytes($toml.Lines -join $toml.Nl) }
}

function Test-SameBytes([string]$target, [byte[]]$bytes) {
    [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($target), $bytes)
}

# 取得 WSL 家目錄
$wslHome = (wsl -d $Distro -- printenv HOME | Out-String).Trim()
if (-not $wslHome) { throw "讀不到 WSL ($Distro) 的 HOME" }
$wslRoot = "\\wsl.localhost\$Distro" + ($wslHome -replace '/', '\')

if ($PullWin -or $PullWsl) {
    $srcRoot = if ($PullWsl) { $wslRoot } else { $HOME }
    $srcName = if ($PullWsl) { 'WSL' } else { 'Windows' }
    # AGENTS.md：整檔複製
    $from = Join-Path $srcRoot $map['AGENTS.md']
    $to = Join-Path $repo 'AGENTS.md'
    Copy-Item $from $to -Force
    Write-Host "$from -> $to"

    # codex-config.toml：只回收 repo 已列出的 key 的值
    $cfgFrom = Join-Path $srcRoot $map['codex-config.toml']
    $cfgTo = Join-Path $repo 'codex-config.toml'
    $have = Split-Toml ([System.IO.File]::ReadAllText($cfgFrom))
    $want = Split-Toml ([System.IO.File]::ReadAllText($cfgTo))
    foreach ($k in Read-ManagedKeys $cfgTo) {
        $label = if ($k.Section) { "$($k.Section).$($k.Key)" } else { $k.Key }
        $src = Find-Key $have $k.Section $k.Key
        if (-not $src) { Write-Warning "$srcName config.toml 沒有 $label，略過"; continue }
        $dst = Find-Key $want $k.Section $k.Key
        $want.Lines[$dst.Index] = "$($k.Key) = $($src.Value)"
    }
    [System.IO.File]::WriteAllBytes($cfgTo, $utf8.GetBytes($want.Lines -join $want.Nl))
    Write-Host "$cfgFrom -> $cfgTo（僅受管 key）"
    return
}

# 組出所有寫入計畫：Target、Bytes、State
$keys = @(Read-ManagedKeys (Join-Path $repo 'codex-config.toml'))
$plan = foreach ($src in $map.Keys) {
    $srcBytes = [System.IO.File]::ReadAllBytes((Join-Path $repo $src))
    foreach ($root in $HOME, $wslRoot) {
        $target = Join-Path $root $map[$src]
        $bytes = $srcBytes
        if (-not (Test-Path $target)) {
            $state = 'missing'
        } elseif ($src -eq 'codex-config.toml') {
            $m = Merge-Toml ([System.IO.File]::ReadAllText($target)) $keys
            $bytes = $m.Bytes
            $state = $m.State
        } else {
            $state = if (Test-SameBytes $target $bytes) { 'same' } else { 'differs' }
        }
        [pscustomobject]@{ State = $state; Target = $target; Bytes = $bytes }
    }
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
