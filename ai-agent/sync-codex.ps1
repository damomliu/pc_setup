<#
.SYNOPSIS
    在 repo 的 ai-agent/ 與 Windows、WSL 之間同步 Codex 設定與規則。

.DESCRIPTION
    預設：repo -> Windows 與 WSL。
      AGENTS.md         -> ~/.codex/AGENTS.md（整檔覆寫；Codex 完整指引）
      AGENTS.md 的 pstack 區塊 -> ~/.codex/pstack-models.md（由 sync 產生的本機配套檔，供 pstack session hook 讀取）
      codex-config.toml -> ~/.codex/config.toml（只合併 repo 列出的 key，其餘設定原樣保留）
    pstack 區塊以 <!-- pstack-models:begin --> / <!-- pstack-models:end --> 包住，內含標題、角色 mapping、
      default effort 與 session hook；是唯一人工維護來源，區塊缺少或無法解析時，推送與 Pull 都在寫入任何檔案前中止。
      配套檔被單獨修改時 -CheckVerbose 會顯示差異；Pull 以來源的 AGENTS.md 為準，不會用配套檔反向覆寫。
    忽略欄位：config.toml 頂層的 model、model_reasoning_effort。
      比對時排除；推送保留各目標原值、缺值不補入（含首次建立）；Pull 保留 repo 原值、不新增。
    config.toml 合併規則：repo 檔只能有 [section] header 與單行 key = value（不含 [[array]]、dotted key、多行值）；
      key 依所屬 section 比對（第一個 [ header 之前為 top-level），同名 key 就地取代，缺的 key 插在該 section 尾端，
      目標檔沒有該 section 就接在檔尾新增。key 排列順序不影響比對。
      沿用目標檔的換行字元，UTF-8 無 BOM；目標不存在則只用 repo 列出的受管 key 建立。
    狀態：missing（目標不存在）、same（內容已一致）、update（只缺 key，直接補上不需 -Force）、
      differs（受管 key 已存在但值不同，例如在 Codex 用 /permissions 改過）。
    有 differs 時整批中止，不寫入；確認要覆蓋加 -Force，要保留本機變更先用 -PullWin / -PullWsl 收回。
    -PullWin / -PullWsl：Windows 或 WSL -> repo（AGENTS.md 整檔複製，先驗證 pstack 區塊；codex-config.toml 只把已列出的 key 改為來源現值，不新增 key）。
    -Check：只比對，列出每個目標的狀態，不寫入。
    -CheckVerbose：唯讀；在 -Check 之外列出受管 key 的「本機 → 預期」值與文字檔逐行 diff。
      敏感路徑（env 子樹，或路徑含 token / secret / password / auth / credential、key 類名稱）的值顯示 ***。
    -Check / -CheckVerbose 不能與 -PullWin / -PullWsl / -Force 併用，兩種 Pull 也互斥；衝突時在任何 I/O 前拒絕。
    需要 PowerShell 7。
#>
param(
    [switch]$PullWin,
    [switch]$PullWsl,
    [switch]$Check,
    [switch]$CheckVerbose,
    [switch]$Force,
    [string]$Distro = 'Ubuntu-24.04',
    [Parameter(DontShow)][string]$TestWinHome,
    [Parameter(DontShow)][string]$TestWslRoot
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\sync-common.ps1"
Assert-SyncArgs $PSBoundParameters
$repo = $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)

# repo 檔 -> 家目錄下的相對路徑
$map = [ordered]@{
    'AGENTS.md'         = '.codex\AGENTS.md'
    'codex-config.toml' = '.codex\config.toml'
}
# 由 AGENTS.md 的 pstack 區塊產生的配套檔
$derivedRel = '.codex\pstack-models.md'
# config.toml 的忽略欄位（僅頂層）
$ignoreKeys = @('model', 'model_reasoning_effort')

# 取出 AGENTS.md 的 pstack 區塊內容（即配套檔內容）；缺少或格式不符時 throw
function Read-PstackBlock([string]$text, [string]$name) {
    $lines = @($text -split '\r?\n')
    $begin = @(0..($lines.Count - 1) | Where-Object { $lines[$_].Trim() -ceq '<!-- pstack-models:begin -->' })
    $end = @(0..($lines.Count - 1) | Where-Object { $lines[$_].Trim() -ceq '<!-- pstack-models:end -->' })
    if ($begin.Count -ne 1 -or $end.Count -ne 1 -or $begin[0] -ge $end[0]) {
        throw "$name 的 pstack 區塊缺少或重複（需要恰好一組 begin / end 標記）"
    }
    $inner = if ($end[0] - $begin[0] -gt 1) { @($lines[($begin[0] + 1)..($end[0] - 1)]) } else { @() }
    $roles = 0; $effort = 0; $hook = 0
    for ($i = 0; $i -lt $inner.Count; $i++) {
        $l = $inner[$i].Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        if ($l -cmatch '^default effort:\s*\S') { $effort++ }
        elseif ($l -cmatch '^session hook:\s*(on|off)$') { $hook++ }
        elseif ($l -imatch '^session hook') { throw "$name 的 pstack 區塊 session hook 只接受 on 或 off（區塊內第 $($i + 1) 行）" }
        elseif ($l -match '^[^:#][^:]*:\s*\S') { $roles++ }
        else { throw "$name 的 pstack 區塊無法解析（區塊內第 $($i + 1) 行不是「名稱: 值」）" }
    }
    if ($roles -lt 1 -or $effort -ne 1 -or $hook -ne 1) {
        throw "$name 的 pstack 區塊不完整（需要角色 mapping、恰好一行 default effort 與一行 session hook）"
    }
    # 每行去除前後空白，hook 才能精確讀到 "session hook: off" 這類整行
    (($inner | ForEach-Object { $_.Trim() -replace '^(session hook|default effort):\s*', '$1: ' }) -join "`n").Trim("`n") + "`n"
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
            if ($toml.Lines[$i] -cmatch ('^\s*\[\s*' + [regex]::Escape($section) + '\s*\]\s*(#.*)?$')) { $start = $i + 1; break }
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
        if ($toml.Lines[$i] -cmatch ('^\s*' + [regex]::Escape($key) + '\s*=\s*(.*?)\s*$')) {
            return [pscustomobject]@{ Index = $i; Value = $Matches[1] }
        }
    }
    $null
}

# 解析 repo 的 codex-config.toml：只允許 [section] header 與單行 key = value，其他一律 throw；頂層忽略欄位不列入受管 key
function Read-ManagedKeys([string]$file) {
    $section = ''
    $n = 0
    foreach ($raw in [System.IO.File]::ReadAllText($file) -split '\r?\n') {
        $n++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[([A-Za-z0-9_.-]+)\]$') { $section = $Matches[1]; continue }
        if ($line -notmatch '^([A-Za-z0-9_-]+)\s*=\s*(\S.*)$') { throw "無法解析 $file 第 $n 行（只支援 [section] 與單行 key = value）" }
        if (-not $section -and $Matches[1] -cin $ignoreKeys) { continue }
        [pscustomobject]@{ Section = $section; Key = $Matches[1]; Value = $Matches[2] }
    }
}

# 把受管 key 合併進目標檔文字，回傳 Bytes、State（update / differs / same）與 Changes（key 的本機值與預期值）
function Merge-Toml([string]$text, $keys) {
    $toml = Split-Toml $text
    $state = 'same'
    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $keys) {
        $hit = Find-Key $toml $k.Section $k.Key
        $line = "$($k.Key) = $($k.Value)"
        if ($hit) {
            if ($hit.Value -cne $k.Value) {
                $toml.Lines[$hit.Index] = $line
                $state = 'differs'
                $changes.Add([pscustomobject]@{ Section = $k.Section; Key = $k.Key; Local = $hit.Value; Want = $k.Value })
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
            $changes.Add([pscustomobject]@{ Section = $k.Section; Key = $k.Key; Local = '(missing)'; Want = $k.Value })
        }
    }
    [pscustomobject]@{ State = $state; Bytes = $utf8.GetBytes($toml.Lines -join $toml.Nl); Changes = $changes }
}

function Get-TextItem([string]$target, [byte[]]$bytes) {
    $exists = Test-Path $target
    [pscustomobject]@{
        State = if (-not $exists) { 'missing' } elseif ([System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($target), $bytes)) { 'same' } else { 'differs' }
        Target = $target; Bytes = $bytes; Kind = 'text'
        Local = if ($exists) { [System.IO.File]::ReadAllText($target) } else { '' }; Want = $utf8.GetString($bytes)
    }
}

$roots = Get-SyncRoots $PSBoundParameters $Distro
$wslRoot = $roots.Wsl

if ($PullWin -or $PullWsl) {
    $srcRoot = if ($PullWsl) { $wslRoot } else { $roots.Win }
    $srcName = if ($PullWsl) { 'WSL' } else { 'Windows' }
    # 先驗證來源 AGENTS.md 的 pstack 區塊、算好 config.toml，全部成功才寫入 repo
    $from = Join-Path $srcRoot $map['AGENTS.md']
    $agentsBytes = [System.IO.File]::ReadAllBytes($from)
    Read-PstackBlock $utf8.GetString($agentsBytes) "$srcName AGENTS.md" | Out-Null
    $to = Join-Path $repo 'AGENTS.md'

    # codex-config.toml：只回收 repo 已列出的（非忽略）key 的值
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
    [System.IO.File]::WriteAllBytes($to, $agentsBytes)
    Write-Host "$from -> $to"
    [System.IO.File]::WriteAllBytes($cfgTo, $utf8.GetBytes($want.Lines -join $want.Nl))
    Write-Host "$cfgFrom -> $cfgTo（僅受管 key）"
    return
}

# 組出所有寫入計畫：Target、Bytes、State
$keys = @(Read-ManagedKeys (Join-Path $repo 'codex-config.toml'))
$agentsBytes = [System.IO.File]::ReadAllBytes((Join-Path $repo 'AGENTS.md'))
$derivedBytes = $utf8.GetBytes((Read-PstackBlock $utf8.GetString($agentsBytes) 'repo AGENTS.md'))
$plan = foreach ($root in $roots.Win, $wslRoot) {
    Get-TextItem (Join-Path $root $map['AGENTS.md']) $agentsBytes
    Get-TextItem (Join-Path $root $derivedRel) $derivedBytes
    $target = Join-Path $root $map['codex-config.toml']
    $exists = Test-Path $target
    $m = Merge-Toml $(if ($exists) { [System.IO.File]::ReadAllText($target) } else { '' }) $keys
    [pscustomobject]@{ State = $(if ($exists) { $m.State } else { 'missing' }); Target = $target; Bytes = $m.Bytes; Kind = 'toml'; Changes = $m.Changes }
}

if ($Check -or $CheckVerbose) {
    Write-PlanOverview $plan
    if ($CheckVerbose) {
        foreach ($p in $plan | Where-Object State -ne 'same') {
            Write-Host "== $($p.State): $($p.Target)"
            if ($p.State -eq 'missing') { continue }
            if ($p.Kind -eq 'text') { Write-TextDiff $p.Local $p.Want; continue }
            foreach ($c in $p.Changes) {
                Write-ValueDiff (@($c.Section -split '\.' | Where-Object { $_ }) + $c.Key) $c.Local $c.Want
            }
        }
    }
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
