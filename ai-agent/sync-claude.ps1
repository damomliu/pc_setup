<#
.SYNOPSIS
    在 repo 的 ai-agent/ 與 Windows、WSL 之間同步 Claude Code 設定與規則。

.DESCRIPTION
    預設：repo -> Windows 與 WSL。
      claude-settings.json      -> ~/.claude/settings.json（WSL 版先合併 claude-settings.wsl.json）
      claude-keybindings.json   -> ~/.claude/keybindings.json
      claude-statusline.py      -> ~/.claude/statusline.py
      CLAUDE.md                 -> ~/.claude/CLAUDE.md（Claude 完整指引，引用 @~/.claude/pstack-models.md）
      claude-pstack-models.md   -> ~/.claude/pstack-models.md（pstack 角色 model、default effort、session hook）
    忽略欄位：settings.json 頂層的 model、effortLevel（modelSettings.*.effortLevel 仍受管）。
      比對時排除；推送保留各目標原值、缺值不補入（含首次建立）；Pull 保留 repo 原值、不新增。
    任何目標內容與 repo 不同（Claude Code 自己會寫 settings.json）時整批中止，不寫入；
    確認要覆蓋加 -Force，要保留本機變更先用 -PullWin / -PullWsl 收回。
    -PullWin：Windows -> repo（WSL 專屬差異請手動改 claude-settings.wsl.json）。
    -PullWsl：WSL -> repo；WSL settings.json 須等於 repo 合併結果（忽略欄位除外；不同即中止，請手動改 claude-settings.json 或 claude-settings.wsl.json），
      相同則略過 settings.json，其餘檔案收回。
    -Check：只比對，列出每個目標的狀態（missing / same / differs），不寫入。
    -CheckVerbose：唯讀；在 -Check 之外列出差異（JSON 設定路徑與「本機 → 預期」值、文字檔逐行 diff）。
      敏感路徑（env 子樹，或路徑含 token / secret / password / auth / credential、key 類名稱）的值顯示 ***。
    -Check / -CheckVerbose 不能與 -PullWin / -PullWsl / -Force 併用，兩種 Pull 也互斥；衝突時在任何 I/O 前拒絕。
    JSON 比對忽略 object key 順序與排版，array 保持順序。
    WSL settings.json 合併規則：object 逐層合併；permissions 底下的陣列取聯集；其餘值由 override 取代。
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
    'claude-settings.json'     = '.claude\settings.json'
    'claude-keybindings.json'  = '.claude\keybindings.json'
    'claude-statusline.py'     = '.claude\statusline.py'
    'CLAUDE.md'                = '.claude\CLAUDE.md'
    'claude-pstack-models.md'  = '.claude\pstack-models.md'
}
# settings.json 的忽略欄位（僅頂層）
$ignoreKeys = @('model', 'effortLevel')

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

# 解析失敗時不帶出原始內容，避免診斷訊息洩漏設定值
function Read-Json([string]$file) {
    try { [System.IO.File]::ReadAllText($file) | ConvertFrom-Json -AsHashtable }
    catch { throw "無法讀取或解析 JSON：$file" }
}

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

# 去掉頂層忽略欄位後的受管內容
function Select-Managed($obj, [string[]]$ignore) {
    $o = [ordered]@{}
    foreach ($k in $obj.Keys) { if ($k -cnotin $ignore) { $o[$k] = $obj[$k] } }
    $o
}

function Test-JsonSame($a, $b, [string[]]$ignore) {
    $ja = ConvertTo-Sorted (Select-Managed $a $ignore) | ConvertTo-Json -Depth 32 -Compress
    $jb = ConvertTo-Sorted (Select-Managed $b $ignore) | ConvertTo-Json -Depth 32 -Compress
    $ja -ceq $jb
}

# 依 $order 的 key 順序組出結果：受管 key 取 $managed，忽略 key 取 $ignoredFrom（沒有就不放）
function Join-Ignored($managed, $order, $ignoredFrom, [string[]]$ignore) {
    $o = [ordered]@{}
    foreach ($k in $order.Keys) {
        if ($k -cin $ignore) { if ($ignoredFrom.Contains($k)) { $o[$k] = $ignoredFrom[$k] } }
        elseif ($managed.Contains($k)) { $o[$k] = $managed[$k] }
    }
    foreach ($k in $managed.Keys) { if ($k -cnotin $ignore -and -not $o.Contains($k)) { $o[$k] = $managed[$k] } }
    foreach ($k in $ignoredFrom.Keys) { if ($k -cin $ignore -and -not $o.Contains($k)) { $o[$k] = $ignoredFrom[$k] } }
    $o
}

function ConvertTo-JsonBytes($obj) { $utf8.GetBytes(($obj | ConvertTo-Json -Depth 32) + "`n") }

# 展平成 路徑 -> 值(JSON)，供逐路徑比對
function Get-Flat($v, [string[]]$seg, $map) {
    if ($v -is [System.Collections.IDictionary] -and $v.Count) {
        foreach ($k in $v.Keys) { Get-Flat $v[$k] ($seg + [string]$k) $map }
    } elseif ($v -is [System.Collections.IList] -and $v.Count) {
        for ($i = 0; $i -lt $v.Count; $i++) { Get-Flat $v[$i] ($seg + "[$i]") $map }
    } else {
        $json = if ($v -is [System.Collections.IDictionary]) { '{}' } elseif ($v -is [System.Collections.IList]) { '[]' } else { ConvertTo-Json -InputObject $v -Compress }
        $map[($seg -join '.')] = [pscustomobject]@{ Seg = $seg; Json = $json }
    }
}

function Write-JsonDiff($local, $want) {
    $a = [ordered]@{}; Get-Flat $local @() $a
    $b = [ordered]@{}; Get-Flat $want @() $b
    foreach ($k in @($b.Keys) + @($a.Keys | Where-Object { -not $b.Contains($_) })) {
        $l = if ($a.Contains($k)) { $a[$k].Json } else { '(missing)' }
        $w = if ($b.Contains($k)) { $b[$k].Json } else { '(missing)' }
        if ($l -ceq $w) { continue }
        $seg = if ($b.Contains($k)) { $b[$k].Seg } else { $a[$k].Seg }
        Write-ValueDiff $seg $l $w
    }
}

# 單一目標的同步計畫。IsWsl 的 settings.json 先合併 WSL 專屬設定
function New-PlanItem([string]$src, [string]$root, [bool]$isWsl) {
    $target = Join-Path $root $map[$src]
    $exists = Test-Path $target
    $srcPath = Join-Path $repo $src
    if ($src -like '*.json') {
        $ignore = if ($src -eq 'claude-settings.json') { $ignoreKeys } else { @() }
        $base = Read-Json $srcPath
        if ($isWsl -and $src -eq 'claude-settings.json') {
            $base = Merge-Settings $base (Read-Json (Join-Path $repo 'claude-settings.wsl.json'))
        }
        $local = if ($exists) { Read-Json $target } else { @{} }
        $same = $exists -and (Test-JsonSame $local $base $ignore)
        $bytes = if ($ignore) { ConvertTo-JsonBytes (Join-Ignored $base $base $local $ignore) } else { [System.IO.File]::ReadAllBytes($srcPath) }
        return [pscustomobject]@{
            Target = $target; Bytes = $bytes; Kind = 'json'
            State = if (-not $exists) { 'missing' } elseif ($same) { 'same' } else { 'differs' }
            Local = Select-Managed $local $ignore; Want = Select-Managed $base $ignore
        }
    }
    $bytes = [System.IO.File]::ReadAllBytes($srcPath)
    [pscustomobject]@{
        Target = $target; Bytes = $bytes; Kind = 'text'
        State = if (-not $exists) { 'missing' } elseif ([System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($target), $bytes)) { 'same' } else { 'differs' }
        Local = if ($exists) { [System.IO.File]::ReadAllText($target) } else { '' }; Want = $utf8.GetString($bytes)
    }
}

$roots = Get-SyncRoots $PSBoundParameters $Distro
$wslRoot = $roots.Wsl

if ($PullWin -or $PullWsl) {
    $srcRoot = if ($PullWsl) { $wslRoot } else { $roots.Win }
    $skip = @()
    if ($PullWsl) {
        # WSL settings.json 須等於 repo 合併結果（忽略欄位除外），否則無法判斷該回收到母版還是 WSL 專屬檔
        $wslSettings = Join-Path $wslRoot $map['claude-settings.json']
        $merged = Merge-Settings (Read-Json (Join-Path $repo 'claude-settings.json')) (Read-Json (Join-Path $repo 'claude-settings.wsl.json'))
        if (-not (Test-JsonSame (Read-Json $wslSettings) $merged $ignoreKeys)) {
            Write-Error "已中止，未收回任何檔案。WSL settings.json 與 repo 合併結果不同：$wslSettings`n請手動編輯 claude-settings.json 或 claude-settings.wsl.json。"
        }
        $skip = @('claude-settings.json')
    }
    # 先讀完所有來源、算好內容，再一次寫入
    $writes = foreach ($src in $map.Keys | Where-Object { $_ -notin $skip }) {
        $from = Join-Path $srcRoot $map[$src]
        $to = Join-Path $repo $src
        if ($src -eq 'claude-settings.json') {
            $have = Read-Json $from
            $mine = Read-Json $to
            $bytes = if (Test-JsonSame $have $mine $ignoreKeys) { $null } else { ConvertTo-JsonBytes (Join-Ignored $have $mine $mine $ignoreKeys) }
        } else {
            $bytes = [System.IO.File]::ReadAllBytes($from)
        }
        [pscustomobject]@{ From = $from; To = $to; Bytes = $bytes }
    }
    foreach ($w in $writes) {
        if ($null -eq $w.Bytes) { Write-Host "[same] $($w.To)"; continue }
        [System.IO.File]::WriteAllBytes($w.To, $w.Bytes)
        Write-Host "$($w.From) -> $($w.To)"
    }
    return
}

$plan = foreach ($src in $map.Keys) {
    New-PlanItem $src $roots.Win $false
    New-PlanItem $src $wslRoot $true
}

if ($Check -or $CheckVerbose) {
    Write-PlanOverview $plan
    if ($CheckVerbose) {
        foreach ($p in $plan | Where-Object State -ne 'same') {
            Write-Host "== $($p.State): $($p.Target)"
            if ($p.State -eq 'missing') { continue }
            if ($p.Kind -eq 'json') { Write-JsonDiff $p.Local $p.Want } else { Write-TextDiff $p.Local $p.Want }
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
