# sync.ps1、sync-claude.ps1、sync-codex.ps1 共用：參數檢查、家目錄解析、差異輸出。以 dot-source 載入。

# 參數衝突一律在任何檔案 I/O 與 WSL 呼叫前拒絕
function Assert-SyncArgs($Bound) {
    $on = { param($n) $Bound.ContainsKey($n) -and $Bound[$n] }
    $pull = (& $on 'PullWin') -or (& $on 'PullWsl')
    if ((& $on 'PullWin') -and (& $on 'PullWsl')) { throw '-PullWin 與 -PullWsl 不能同時使用' }
    if (((& $on 'Check') -or (& $on 'CheckVerbose')) -and ($pull -or (& $on 'Force'))) {
        throw '-Check / -CheckVerbose 只能唯讀檢查，不能與 -PullWin / -PullWsl / -Force 併用'
    }
    if ($Bound.ContainsKey('TestWinHome') -ne $Bound.ContainsKey('TestWslRoot')) {
        throw '-TestWinHome 與 -TestWslRoot 必須成對指定'
    }
    if ($Bound.ContainsKey('TestWinHome') -and ([string]::IsNullOrWhiteSpace($Bound.TestWinHome) -or [string]::IsNullOrWhiteSpace($Bound.TestWslRoot))) {
        throw '-TestWinHome 與 -TestWslRoot 不能是空字串'
    }
}

# Windows 與 WSL 的家目錄；成對的測試路徑會跳過 WSL 查詢
function Get-SyncRoots($Bound, [string]$Distro) {
    if ($Bound.ContainsKey('TestWinHome')) {
        return [pscustomobject]@{ Win = $Bound.TestWinHome; Wsl = $Bound.TestWslRoot }
    }
    $wslHome = (wsl -d $Distro -- printenv HOME | Out-String).Trim()
    if (-not $wslHome) { throw "讀不到 WSL ($Distro) 的 HOME" }
    [pscustomobject]@{ Win = $HOME; Wsl = "\\wsl.localhost\$Distro" + ($wslHome -replace '/', '\') }
}

# 設定路徑是否敏感（大小寫不敏感）：任一路徑段含 token / secret / password / auth / credential、
# 為 key 類名稱，或位於 env 子樹
function Test-SensitivePath([string[]]$Segments) {
    foreach ($s in $Segments) {
        if ($s -imatch 'token|secret|password|auth|credential') { return $true }
        if ($s -imatch '^(key|api[_-]?key|access[_-]?key|private[_-]?key)$') { return $true }
        if ($s -ieq 'env') { return $true }
    }
    $false
}

# 輸出一筆設定差異「路徑: 本機 → 預期」；敏感路徑的值一律顯示 ***
function Write-ValueDiff([string[]]$Segments, [string]$Local, [string]$Want) {
    if (Test-SensitivePath $Segments) { $Local = '***'; $Want = '***' }
    Write-Host ("  {0}: {1} → {2}" -f (($Segments -join '.') -replace '\.\[', '['), $Local, $Want)
}

# 逐行差異（LCS），'-' 為本機、'+' 為預期，只列出不同的行
function Get-LineDiff([string[]]$a, [string[]]$b) {
    $n = $a.Count; $m = $b.Count
    $t = New-Object 'int[,]' ($n + 1), ($m + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        for ($j = $m - 1; $j -ge 0; $j--) {
            $t[$i, $j] = if ($a[$i] -ceq $b[$j]) { $t[($i + 1), ($j + 1)] + 1 } else { [Math]::Max($t[($i + 1), $j], $t[$i, ($j + 1)]) }
        }
    }
    $i = 0; $j = 0
    while ($i -lt $n -and $j -lt $m) {
        if ($a[$i] -ceq $b[$j]) { $i++; $j++ }
        elseif ($t[($i + 1), $j] -ge $t[$i, ($j + 1)]) { "- $($a[$i])"; $i++ }
        else { "+ $($b[$j])"; $j++ }
    }
    while ($i -lt $n) { "- $($a[$i])"; $i++ }
    while ($j -lt $m) { "+ $($b[$j])"; $j++ }
}

function Write-TextDiff([string]$Local, [string]$Want) {
    $lines = @(Get-LineDiff ($Local.TrimEnd("`r", "`n") -split '\r?\n') ($Want.TrimEnd("`r", "`n") -split '\r?\n'))
    if (-not $lines) { Write-Host '  （僅換行字元或結尾空行不同）'; return }
    Write-Host '  - 本機 / + 預期'
    $lines | ForEach-Object { Write-Host "  $_" }
}

function Write-PlanOverview($plan) {
    foreach ($p in $plan) { Write-Host ("{0,-8} {1}" -f $p.State, $p.Target) }
}
