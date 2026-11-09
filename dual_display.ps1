#Requires -Version 7
<#
.SYNOPSIS
  切換 Windows 主螢幕的解析度。

.DESCRIPTION
  無參數 -> 顯示目前螢幕狀態並開啟互動選單。
  -Mode Single|Single169|Single1610 -> 非互動，直接套用解析度。
  -WhatIf -> 查詢支援狀態並顯示動作，不變更解析度。
#>
[CmdletBinding()]
param(
    [ValidateSet('Single', 'Single169', 'Single1610')][string]$Mode,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ---- 設定 -------------------------------------------------------------------
# 單螢幕解析度 profile（鍵名對應選單 / -Mode）
$SingleProfiles = [ordered]@{
    Single     = @{ Label = '25:9';  Width = 2560; Height = 1080 }
    Single169  = @{ Label = '16:9';  Width = 1920; Height = 1080 }
    Single1610 = @{ Label = '16:10'; Width = 1920; Height = 1200 }
}
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

# ---- PC 端 ------------------------------------------------------------------
function Get-MonitorState {
    Add-Type -AssemblyName System.Windows.Forms
    $screens = [System.Windows.Forms.Screen]::AllScreens
    foreach ($screen in $screens) {
        [pscustomobject]@{
            DeviceName = $screen.DeviceName
            Primary    = $screen.Primary
            Width      = $screen.Bounds.Width
            Height     = $screen.Bounds.Height
        }
    }
}

function Get-PrimaryResolution {
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    [pscustomobject]@{ DeviceName = $screen.DeviceName; Width = $screen.Bounds.Width; Height = $screen.Bounds.Height }
}

# 設定主螢幕解析度。優先選同解析度中最高刷新率。回傳 $true 表示已套用或已是目標。
function Set-DisplayResolution([int]$Width, [int]$Height) {
    if (-not ('DualDisplayNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DualDisplayNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2;
        public int dmPanningWidth, dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll")]
    private static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    private const int ENUM_CURRENT_SETTINGS = -1;
    private const int CDS_UPDATEREGISTRY = 0x01;
    private const int CDS_TEST = 0x02;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int ERR_UNSUPPORTED = -100;
    public const int ERR_TEST_FAILED = -101;

    // 回傳刷新率；找不到則 -1
    public static int FindBestFrequency(int width, int height) {
        var dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        int best = -1;
        for (int i = 0; EnumDisplaySettings(null, i, ref dm); i++) {
            if (dm.dmPelsWidth == width && dm.dmPelsHeight == height && dm.dmDisplayFrequency > best) {
                best = dm.dmDisplayFrequency;
            }
        }
        return best;
    }

    // 回傳 ChangeDisplaySettings 結果碼；ERR_* 為前置失敗
    public static int Apply(int width, int height, int frequency) {
        var mode = new DEVMODE();
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref mode)) {
            return ERR_UNSUPPORTED;
        }
        mode.dmPelsWidth = width;
        mode.dmPelsHeight = height;
        mode.dmDisplayFrequency = frequency;
        // DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY
        mode.dmFields = 0x80000 | 0x100000 | 0x400000;
        int test = ChangeDisplaySettings(ref mode, CDS_TEST);
        if (test != DISP_CHANGE_SUCCESSFUL) return ERR_TEST_FAILED - test;
        return ChangeDisplaySettings(ref mode, CDS_UPDATEREGISTRY);
    }
}
'@
    }

    $cur = Get-PrimaryResolution
    if ($cur.Width -eq $Width -and $cur.Height -eq $Height) {
        Write-Ok "解析度已是 ${Width}x${Height}"
        return $true
    }

    $freq = [DualDisplayNative]::FindBestFrequency($Width, $Height)
    if ($freq -lt 0) {
        Write-Fail "顯示器不支援 ${Width}x${Height}"
        return $false
    }

    Write-Step "設定解析度 ${Width}x${Height}@${freq}Hz"
    $script:resChanged = $false
    $null = Invoke-Step "ChangeDisplaySettings ${Width}x${Height}@${freq}" {
        $code = [DualDisplayNative]::Apply($Width, $Height, $freq)
        if ($code -ne [DualDisplayNative]::DISP_CHANGE_SUCCESSFUL) {
            Write-Fail "ChangeDisplaySettings 失敗 (code $code)"
            return
        }
        $script:resChanged = $true
    }
    if ($WhatIf) { return $true }
    if (-not $script:resChanged) { return $false }

    if (Wait-Until {
            $r = Get-PrimaryResolution
            $r.Width -eq $Width -and $r.Height -eq $Height
        } 5) {
        Write-Ok "解析度 ${Width}x${Height}"
        return $true
    }
    $now = Get-PrimaryResolution
    Write-Warn "解析度未變更 (目前 $($now.Width)x$($now.Height))"
    return $false
}

# ---- 狀態與解析度切換 -------------------------------------------------------
function Show-Status {
    Write-Host ''
    Write-Host '── 螢幕狀態 ──' -ForegroundColor White
    $screens = @(Get-MonitorState | Sort-Object @{ Expression = 'Primary'; Descending = $true }, DeviceName)
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $screen = $screens[$i]
        $primary = if ($screen.Primary) { '，主螢幕' } else { '' }
        Write-Host "螢幕$($i + 1): $($screen.DeviceName) $($screen.Width)x$($screen.Height)$primary"
    }
    if ($screens.Count -lt 2) {
        Write-Warn '未偵測到第二台已連接螢幕'
    }
    Write-Host ''
}

function Invoke-Single([string]$ProfileKey) {
    $profile = $SingleProfiles[$ProfileKey]
    if (-not $profile) { Write-Fail "未知的解析度 profile: $ProfileKey"; return }
    $resolution = "$($profile.Width)x$($profile.Height)"
    Write-Host "=== 設定主螢幕 $($profile.Label) ($resolution) ===" -ForegroundColor White
    $null = Set-DisplayResolution -Width $profile.Width -Height $profile.Height
}

if ($Mode) {
    Invoke-Single -ProfileKey $Mode
    return
}

while ($true) {
    Show-Status
    Write-Host '(R) 更新狀態  (1) 螢幕1 25:9  (2560x1080)  (9) 螢幕1 16:9 (1920x1080)  (0) 螢幕1 16:10 (1920x1200)  (Q) 退出'
    switch ((Read-Host '選擇').Trim().ToUpper()) {
        'R' { continue }
        '1' { Invoke-Single -ProfileKey 'Single' }
        '9' { Invoke-Single -ProfileKey 'Single169' }
        '0' { Invoke-Single -ProfileKey 'Single1610' }
        'Q' { return }
        default { Write-Warn '無效的選項' }
    }
}
