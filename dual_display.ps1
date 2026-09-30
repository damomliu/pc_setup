#Requires -Version 7
<#
.SYNOPSIS
  切換 單螢幕 / 雙螢幕 (Spacedesk)。PC 為 driver、NB 為 Viewer。

.DESCRIPTION
  無參數 -> 互動選單。
  -Mode Single|Dual -> 非互動，直接套用。
  -WhatIf -> 只印出會做的事，不改任何狀態 (唯讀的狀態查詢仍會執行)。
  -Install / -Uninstall -> 一次性安裝/還原 (需要 admin，會自我提升，跳一次 UAC)。

  成功判定: Viewer 連上後 PC 才會多一個虛擬螢幕，所以以「PC 螢幕數」為準；
  NB 端的程序狀態只是輔助資訊。
#>
[CmdletBinding()]
param(
    [ValidateSet('Single', 'Dual')][string]$Mode,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$WhatIf,
    # 內部使用: 自我提升時傳入原本的使用者，排程工作才會綁到正確帳號
    [string]$AsUser
)

$ErrorActionPreference = 'Stop'

# ---- 設定 -------------------------------------------------------------------
$ServiceName    = 'spacedeskService'
$TrayExe        = 'C:\Program Files\datronicsoft\spacedesk\spacedeskServiceTray.exe'
$TaskStart      = 'DualDisplay-StartDriver'
$TaskStop       = 'DualDisplay-StopDriver'
$AdapterName    = 'spacedesk Graphics Adapter'
$NbHost         = 'nb'
$ViewerProcess  = 'spacedeskAppUWP'
$ViewerAumid    = 'datronicsoft.spacedesk_aa4z72nd5cmx4!App'
$NbViewerTask   = 'DualDisplay-StartViewer'   # NB 上的互動排程工作 (啟動時自動建立)
$PhysicalScreens = 1     # 單螢幕模式預期的螢幕數
$WaitScreenSec  = 15     # 雙螢幕模式等虛擬螢幕出現
$WaitStopSec    = 10     # 單螢幕模式等虛擬螢幕消失
# -----------------------------------------------------------------------------

function Write-Step([string]$Text) { Write-Host "▶ $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "✔ $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "⚠ $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text) { Write-Host "✘ $Text" -ForegroundColor Red }

# 會改變狀態的動作一律走這裡，-WhatIf 時只印不做。回傳 $true 表示有實際執行。
function Invoke-Step([string]$Description, [scriptblock]$StepBlock) {
    if ($WhatIf) {
        Write-Host "[WhatIf] $Description" -ForegroundColor DarkGray
        return $false
    }
    & $StepBlock
    return $true
}

function Wait-Until([scriptblock]$Condition, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return [bool](& $Condition)
}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 以 admin 執行一段 PowerShell (UAC)。回傳 exit code。
function Invoke-Elevated([string]$Command) {
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $p = Start-Process pwsh -Verb RunAs -Wait -PassThru -ArgumentList '-NoProfile', '-EncodedCommand', $enc
    return $p.ExitCode
}

# ---- PC 端 ------------------------------------------------------------------
function Get-ScreenCount {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Screen]::AllScreens.Count
}

function Get-PcService { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue }

function Get-AdapterDevice {
    Get-CimInstance Win32_PnPEntity -Filter "Name='$AdapterName'" -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-AdapterDisabled {
    $d = Get-AdapterDevice
    return ($d -and $d.ConfigManagerErrorCode -eq 22)
}

function Test-TasksInstalled {
    [bool](Get-ScheduledTask -TaskName $TaskStart -ErrorAction SilentlyContinue) -and
    [bool](Get-ScheduledTask -TaskName $TaskStop -ErrorAction SilentlyContinue)
}

function Start-PcDriver {
    if (-not $WhatIf -and -not (Test-TasksInstalled)) {
        Write-Fail '尚未安裝排程工作，請先執行: dual_display.ps1 -Install'
        return $false
    }
    if (Test-AdapterDisabled) {
        Write-Step "重新啟用 $AdapterName (需要 UAC)"
        $id = (Get-AdapterDevice).PNPDeviceID
        $null = Invoke-Step "Enable-PnpDevice $id" {
            $code = Invoke-Elevated "Enable-PnpDevice -InstanceId '$id' -Confirm:`$false"
            if ($code -ne 0) { Write-Warn "Enable-PnpDevice 結束碼 $code" }
        }
    }
    Write-Step "PC: 啟動 $ServiceName"
    $ran = Invoke-Step "Start-ScheduledTask $TaskStart" { Start-ScheduledTask -TaskName $TaskStart }
    if ($ran -and -not (Wait-Until { (Get-PcService).Status -eq 'Running' } 10)) {
        Write-Fail "$ServiceName 未在 10 秒內進入 Running"
        return $false
    }
    Write-Step 'PC: 啟動 Tray'
    $null = Invoke-Step "Start-Process $TrayExe" {
        if (-not (Get-Process spacedeskServiceTray -ErrorAction SilentlyContinue)) { Start-Process $TrayExe }
    }
    return $true
}

function Stop-PcDriver {
    Write-Step 'PC: 關閉 Tray'
    $null = Invoke-Step 'Stop-Process spacedeskServiceTray' {
        Get-Process spacedeskServiceTray -ErrorAction SilentlyContinue | Stop-Process -Force
    }
    if (-not $WhatIf -and -not (Test-TasksInstalled)) {
        Write-Fail '尚未安裝排程工作，請先執行: dual_display.ps1 -Install'
        return $false
    }
    Write-Step "PC: 停止 $ServiceName"
    $ran = Invoke-Step "Start-ScheduledTask $TaskStop" { Start-ScheduledTask -TaskName $TaskStop }
    if ($ran -and -not (Wait-Until { (Get-PcService).Status -eq 'Stopped' } 10)) {
        Write-Fail "$ServiceName 未在 10 秒內進入 Stopped"
        return $false
    }
    return $true
}

# ---- NB 端 (ssh，遠端預設 shell 是 cmd.exe，所以一律用 EncodedCommand) -----------
function Invoke-Nb([string]$Script) {
    $full = "`$ProgressPreference='SilentlyContinue'; $Script"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $out = & ssh -n -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR $NbHost pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2>&1
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Output = (($out | ForEach-Object { "$_" }) -join "`n").Trim() }
}

# 回傳 $null = 連不上；否則 @{ Running; Sessions }
function Get-NbViewerState {
    $r = Invoke-Nb "Get-Process $ViewerProcess -ErrorAction SilentlyContinue | ForEach-Object { `$_.SessionId }; exit 0"
    if (-not $r.Ok) { return $null }
    $sessions = @($r.Output -split '\s+' | Where-Object { $_ })
    [pscustomobject]@{ Running = ($sessions.Count -gt 0); Sessions = $sessions }
}

function Stop-NbViewer {
    Write-Step 'NB: 停止 Viewer'
    $ok = $true
    $null = Invoke-Step "ssh $NbHost Stop-Process $ViewerProcess" {
        $r = Invoke-Nb "Get-Process $ViewerProcess -ErrorAction SilentlyContinue | Stop-Process -Force; exit 0"
        if (-not $r.Ok) { $script:nbStopFailed = $true; Write-Warn "NB 無法連線或指令失敗: $($r.Output)" }
    }
    if ($script:nbStopFailed) { $ok = $false; $script:nbStopFailed = $false }
    return $ok
}

function Start-NbViewer {
    Write-Step 'NB: 啟動 Viewer'
    $ok = $true
    # SSH 在 session 0，直接 Start-Process 看不到桌面。改在 NB 上建立「互動桌面」排程工作再觸發 (每次重建，免安裝)
    $null = Invoke-Step "ssh $NbHost Start-ScheduledTask $NbViewerTask" {
        $r = Invoke-Nb @"
`$a = New-ScheduledTaskAction -Execute 'explorer.exe' -Argument 'shell:AppsFolder\$ViewerAumid'
`$p = New-ScheduledTaskPrincipal -UserId "`$env:USERDOMAIN\`$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName '$NbViewerTask' -Action `$a -Principal `$p -Force | Out-Null
Start-ScheduledTask -TaskName '$NbViewerTask'
"@
        if (-not $r.Ok) { $script:nbStartFailed = $true; Write-Warn "NB 啟動指令失敗: $($r.Output)" }
    }
    if ($script:nbStartFailed) { $ok = $false; $script:nbStartFailed = $false }
    return $ok
}

# ---- 狀態 -------------------------------------------------------------------
function Show-Status {
    Write-Host ''
    Write-Host '── 狀態 (僅供參考，可能已過期) ──' -ForegroundColor White
    $svc = Get-PcService
    $svcText = if ($svc) { "$($svc.Status) / $($svc.StartType)" } else { '未安裝' }
    $tray = if (Get-Process spacedeskServiceTray -ErrorAction SilentlyContinue) { 'on' } else { 'off' }
    $adapter = if (Test-AdapterDisabled) { '，Adapter 已停用' } else { '' }
    Write-Host "PC  driver : $svcText (tray: $tray)$adapter"
    Write-Host "PC  螢幕數 : $(Get-ScreenCount)"
    $nb = Get-NbViewerState
    if ($null -eq $nb) {
        Write-Host 'NB  Viewer : 未知 (無法連線)' -ForegroundColor Yellow
    } elseif ($nb.Running) {
        Write-Host "NB  Viewer : 執行中 (session $($nb.Sessions -join ','))"
    } else {
        Write-Host 'NB  Viewer : 關閉'
    }
    Write-Host ''
}

# ---- 模式 -------------------------------------------------------------------
function Invoke-ForceUnload {
    $d = Get-AdapterDevice
    if (-not $d) { Write-Warn "找不到 $AdapterName"; return }
    Write-Step "強制卸載: 停用 $AdapterName (需要 UAC)"
    $id = $d.PNPDeviceID
    $null = Invoke-Step "Disable-PnpDevice $id" {
        $code = Invoke-Elevated "Disable-PnpDevice -InstanceId '$id' -Confirm:`$false"
        if ($code -ne 0) { Write-Warn "Disable-PnpDevice 結束碼 $code" }
        if (Wait-Until { (Get-ScreenCount) -le $PhysicalScreens } 5) {
            Write-Ok "螢幕數已回到 $(Get-ScreenCount)"
        } else {
            Write-Warn "螢幕數仍為 $(Get-ScreenCount)，可能需要重新開機"
        }
    }
}

function Invoke-Single {
    Write-Host '=== 單螢幕模式 ===' -ForegroundColor White
    $nbOk = Stop-NbViewer
    $pcOk = Stop-PcDriver
    if ($WhatIf) { return }

    if (Wait-Until { (Get-ScreenCount) -le $PhysicalScreens } $WaitStopSec) {
        if ($pcOk) { Write-Ok "單螢幕完成 (螢幕數 $(Get-ScreenCount))" }
    } else {
        Write-Warn "虛擬螢幕沒有消失 (目前 $(Get-ScreenCount) 個，預期 $PhysicalScreens)"
        if (-not $nbOk) { Write-Warn 'NB 無法連線，Viewer 可能仍在執行，這會讓虛擬螢幕殘留' }
        if ($script:NonInteractive) {
            Write-Warn '可從互動選單使用 (F) 強制卸載'
        } elseif ((Read-Host '要強制卸載虛擬顯示器嗎？[y/N]') -match '^[yY]') {
            Invoke-ForceUnload
        }
    }
    if (-not $nbOk) { Write-Warn 'NB 端狀態未知' }
}

function Invoke-Dual {
    Write-Host '=== 雙螢幕模式 ===' -ForegroundColor White
    # 完整重做: 先停 NB Viewer 讓虛擬螢幕消失，才能取得乾淨的基準螢幕數
    $nbOk = Stop-NbViewer
    if (-not $WhatIf -and $nbOk) { Start-Sleep -Seconds 2 }
    $baseline = Get-ScreenCount

    if (-not (Start-PcDriver)) { Write-Fail 'PC driver 啟動失敗，中止'; return }

    if ($nbOk) {
        $nbOk = Start-NbViewer
    }
    if (-not $nbOk) {
        Write-Warn 'PC: driver 已啟動 / NB: 未知 (無法連線或啟動失敗)，之後可用 (R) 重試'
        return
    }
    if ($WhatIf) { return }

    Write-Step "等待虛擬螢幕出現 (基準 $baseline，最多 $WaitScreenSec 秒)"
    if (Wait-Until { (Get-ScreenCount) -gt $baseline } $WaitScreenSec) {
        Write-Ok "雙螢幕完成 (螢幕數 $(Get-ScreenCount))"
        return
    }
    Write-Warn "螢幕數沒有增加 (仍為 $(Get-ScreenCount))"
    $nb = Get-NbViewerState
    if ($null -eq $nb)          { Write-Warn 'NB 無法連線，狀態未知' }
    elseif (-not $nb.Running)   { Write-Warn 'NB 上沒有 Viewer 程序，啟動可能失敗' }
    elseif ($nb.Sessions -contains '0' -and -not ($nb.Sessions | Where-Object { $_ -ne '0' })) {
        Write-Warn 'Viewer 只在 session 0 (SSH) 中啟動，看不到桌面。需改用 NB 上的互動排程工作方案'
    } else {
        Write-Warn 'Viewer 已在桌面執行，但未連上 PC，請檢查 Viewer 的自動連線設定'
    }
}

# ---- 安裝 / 還原 (需要 admin) ------------------------------------------------
function Invoke-AsAdmin([string]$Switch) {
    if (Test-Admin) { return $false }
    if ($AsUser) {
        # 已是提升後的子程序卻仍非 admin: 不再重新提升，避免無限跳 UAC
        Write-Fail '提升後的程序仍不是 admin，中止 (不再重試)'
        Read-Host '按 Enter 關閉'
        exit 2
    }
    Write-Step 'UAC 提升權限中...'
    $elevArgs = @('-NoProfile', '-File', $PSCommandPath, $Switch, '-AsUser', "$env:USERDOMAIN\$env:USERNAME")
    if ($WhatIf) { $elevArgs += '-WhatIf' }
    $p = Start-Process pwsh -Verb RunAs -Wait -PassThru -ArgumentList $elevArgs
    if ($p.ExitCode -ne 0) { Write-Fail "提升後的執行失敗 (exit $($p.ExitCode))"; exit $p.ExitCode }
    return $true
}

function Invoke-Install {
    if (Invoke-AsAdmin '-Install') { return }
    $user = if ($AsUser) { $AsUser } else { "$env:USERDOMAIN\$env:USERNAME" }
    Write-Step "$ServiceName -> Manual"
    $null = Invoke-Step "Set-Service $ServiceName -StartupType Manual" { Set-Service $ServiceName -StartupType Manual }

    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    $tasks = @{
        $TaskStart = "Start-Service $ServiceName"
        $TaskStop  = "Stop-Service $ServiceName -Force"
    }
    foreach ($name in $tasks.Keys) {
        Write-Step "註冊排程工作 $name (使用者 $user，最高權限)"
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -WindowStyle Hidden -Command `"$($tasks[$name])`""
        $null = Invoke-Step "Register-ScheduledTask $name" {
            Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        }
    }
    Write-Ok '安裝完成'
}

function Invoke-Uninstall {
    if (Invoke-AsAdmin '-Uninstall') { return }
    foreach ($name in $TaskStart, $TaskStop) {
        Write-Step "移除排程工作 $name"
        $null = Invoke-Step "Unregister-ScheduledTask $name" {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    Write-Step "$ServiceName -> Automatic"
    $null = Invoke-Step "Set-Service $ServiceName -StartupType Automatic" { Set-Service $ServiceName -StartupType Automatic }
    Write-Ok '已還原'
}

# ---- 進入點 -----------------------------------------------------------------
if ($Install -or $Uninstall) {
    try {
        if ($Install) { Invoke-Install } else { Invoke-Uninstall }
    } catch {
        Write-Fail $_.Exception.Message
        if ($AsUser) { Read-Host '按 Enter 關閉'; exit 1 }
        throw
    }
    if ($AsUser) { Read-Host '完成，按 Enter 關閉' }
    return
}

if ($Mode) {
    $script:NonInteractive = $true
    switch ($Mode) {
        'Single' { Invoke-Single }
        'Dual'   { Invoke-Dual }
    }
    return
}

while ($true) {
    Show-Status
    Write-Host '(R) 更新狀態  (1) 單螢幕  (2) 雙螢幕  (F) 強制卸載虛擬顯示器  (Q) 退出'
    switch ((Read-Host '選擇').Trim().ToUpper()) {
        'R' { continue }
        '1' { Invoke-Single }
        '2' { Invoke-Dual }
        'F' { Invoke-ForceUnload }
        'Q' { return }
        default { Write-Warn '無效的選項' }
    }
}
