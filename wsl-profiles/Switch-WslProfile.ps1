<#
Switch-WslProfile.ps1
用法:
  Switch-WslProfile.ps1        互動模式：顯示目前狀態，再詢問要不要切換
  Switch-WslProfile.ps1 A      直接切換到 A（Win-WPF + Docker Postgres，輕量）
  Switch-WslProfile.ps1 B      直接切換到 B（WSL-Python 開發，重度；A/B 同時開發也用這個）
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('A', 'B')]
    [string]$Profile
)

$ErrorActionPreference = 'Stop'
$profileDir = $PSScriptRoot
$wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'

function Get-CurrentProfileName {
    if (-not (Test-Path $wslConfigPath)) {
        return $null
    }
    $current = Get-Content $wslConfigPath -Raw
    foreach ($p in 'A', 'B') {
        $candidate = Join-Path $profileDir "$p.wslconfig"
        if ((Test-Path $candidate) -and ((Get-Content $candidate -Raw) -eq $current)) {
            return $p
        }
    }
    return '不明'
}

function Show-CurrentState {
    Write-Host ''
    Write-Host '=== 目前 Profile ===' -ForegroundColor Cyan
    $matched = Get-CurrentProfileName
    if ($null -eq $matched) {
        Write-Host '目前沒有 ~/.wslconfig（WSL2 使用預設值）' -ForegroundColor Yellow
    }
    elseif ($matched -eq '不明') {
        Write-Host '不明（~/.wslconfig 內容跟 A、B 都不一致，可能被手動改過）' -ForegroundColor Yellow
    }
    else {
        Write-Host "$matched" -ForegroundColor Green
    }

    Write-Host ''
    Write-Host '=== 目前 WSL distro 狀態 ===' -ForegroundColor Cyan
    wsl -l -v

    Write-Host ''
    Write-Host '=== 目前 Docker container ===' -ForegroundColor Cyan
    if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        Write-Host '(Docker Desktop 未執行)'
    }
    else {
        $job = Start-Job -ScriptBlock { docker ps }
        if (Wait-Job -Job $job -Timeout 5) {
            Receive-Job -Job $job
        }
        else {
            Write-Host '(Docker 未回應，略過)'
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Test-DockerDesktopRunning {
    [bool](Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)
}

function Stop-DockerDesktop {
    if (-not (Test-DockerDesktopRunning)) {
        Write-Host 'Docker Desktop 已是關閉狀態。' -ForegroundColor Green
        return
    }

    Write-Host '關閉 Docker Desktop...' -ForegroundColor Cyan
    Stop-Process -Name 'Docker Desktop' -Force -ErrorAction SilentlyContinue
    $timeout = 20
    while ((Test-DockerDesktopRunning) -and $timeout -gt 0) {
        Start-Sleep -Seconds 1
        $timeout--
    }
    if (Test-DockerDesktopRunning) {
        Write-Warning 'Docker Desktop 逾時仍未關閉。'
    }
    else {
        Write-Host 'Docker Desktop 已關閉。' -ForegroundColor Green
    }
}

function Start-DockerDesktop {
    if (Test-DockerDesktopRunning) {
        Write-Host 'Docker Desktop 已在執行。' -ForegroundColor Green
        return
    }
    if (-not (Test-Path $dockerExe)) {
        Write-Warning "找不到 Docker Desktop.exe ($dockerExe)，請手動啟動。"
        return
    }
    Start-Process $dockerExe
    Write-Host '已啟動 Docker Desktop...' -ForegroundColor Green
}

function Get-WslDistroNames {
    $previous = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'
    try {
        wsl -l -q | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ }
    }
    finally {
        if ($null -eq $previous) {
            Remove-Item Env:WSL_UTF8 -ErrorAction SilentlyContinue
        }
        else {
            $env:WSL_UTF8 = $previous
        }
    }
}

function Start-UbuntuDistro {
    $names = @(Get-WslDistroNames | Where-Object { $_ -notmatch '(?i)docker-desktop' })
    $ubuntu = $names | Where-Object { $_ -match '(?i)ubuntu' } | Select-Object -First 1
    if (-not $ubuntu) {
        Write-Warning '找不到 Ubuntu distro，略過啟動。'
        if ($names.Count -gt 0) {
            Write-Host "可用 distro: $($names -join ', ')"
        }
        return
    }

    Write-Host "啟動 $ubuntu ..." -ForegroundColor Cyan
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        wsl -d $ubuntu --exec /bin/true
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$ubuntu 已啟動。" -ForegroundColor Green
        }
        else {
            Write-Warning "$ubuntu 啟動失敗 (exit $LASTEXITCODE)。"
        }
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
}

function Confirm-DockerDesktop {
    Write-Host ''
    $status = if (Test-DockerDesktopRunning) { '開啟' } else { '關閉' }
    $choice = Read-Host "Docker Desktop 目前$status。要開啟還是關閉？(o=開啟 / c=關閉，Enter 維持現狀)"
    switch -Regex ($choice) {
        '^[oO]$' { Start-DockerDesktop }
        '^[cC]$' { Stop-DockerDesktop }
        default { Write-Host "維持$status。" }
    }
}

function Invoke-Switch([string]$Target) {
    $sourceFile = Join-Path $profileDir "$Target.wslconfig"
    if (-not (Test-Path $sourceFile)) {
        Write-Error "找不到設定檔: $sourceFile"
        return
    }

    Write-Host ''
    Write-Host "切換到 Profile $Target 會執行 'wsl --shutdown'，上面列出的 WSL distro 與 container 都會被中斷。" -ForegroundColor Yellow
    $confirm = Read-Host '按 Enter 繼續，或輸入 n 取消'
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Host '已取消。'
        return
    }

    if (Test-DockerDesktopRunning) {
        Write-Host '偵測到 Docker Desktop 正在執行，shutdown 前先關閉，避免它跳錯誤通知...' -ForegroundColor Cyan
        Stop-DockerDesktop
    }

    Copy-Item -Path $sourceFile -Destination $wslConfigPath -Force
    Write-Host "已套用 $Target.wslconfig -> $wslConfigPath" -ForegroundColor Green

    wsl --shutdown
    Write-Host 'WSL 已 shutdown。' -ForegroundColor Green

    if ($Target -eq 'B') {
        Start-UbuntuDistro
    }

    Confirm-DockerDesktop

    Write-Host ''
    Write-Host "完成，目前為 Profile $Target。" -ForegroundColor Green
}

if ($Profile) {
    Show-CurrentState
    Invoke-Switch -Target $Profile
    return
}

# 互動模式（桌面捷徑走這條路）
Show-CurrentState
Write-Host ''
Write-Host '  A = Win-WPF 開發 + Docker Postgres（輕量：memory=8GB, processors=4）'
Write-Host '  B = WSL-Python 開發（重度：memory=36GB, processors=20；A/B 同時開發也用這個）'
Write-Host ''
$choice = Read-Host '要切換到哪個 profile？(a/b，直接 Enter 離開)'

switch -Regex ($choice) {
    '^[aA]$' { Invoke-Switch -Target 'A' }
    '^[bB]$' { Invoke-Switch -Target 'B' }
    default { Write-Host '未切換，離開。' }
}
