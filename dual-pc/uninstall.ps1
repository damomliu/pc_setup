[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PC', 'NB')]
    [string]$Role,

    [switch]$KeepLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (
    -not $WhatIfPreference -and
    -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
) {
    throw '請以系統管理員身分執行 uninstall.ps1。'
}

Import-Module (Join-Path $PSScriptRoot 'DualPcProfiles.psm1') -Force
$config = Get-DppConfig -BasePath $PSScriptRoot
$installRoot = [string]$config.InstallRoot
$normalizedInstallRoot = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
$normalizedProgramFiles = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
if (
    -not $normalizedInstallRoot.StartsWith("$normalizedProgramFiles\", [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path $normalizedInstallRoot -Leaf) -ne 'DualPcProfiles'
) {
    throw "不安全的 InstallRoot：$installRoot"
}
$runtime = Join-Path $env:LOCALAPPDATA 'DualPcProfiles'
$marker = if ($Role -eq 'PC') {
    'dual-pc-profiles-NB-to-PC'
} else {
    'dual-pc-profiles-PC-to-NB'
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "移除 DualPcProfiles $Role")) {
    foreach ($taskType in @('Coordinator', 'Worker')) {
        foreach ($profile in @('PC', 'mix', 'NB')) {
            Unregister-ScheduledTask `
                -TaskName "$($config.TaskPrefix)-$taskType-$profile" `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        }
    }
    Unregister-ScheduledTask `
        -TaskName "$($config.TaskPrefix)-Notify" `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Dual PC Profiles.lnk'
    Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue

    Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" -ErrorAction SilentlyContinue |
        Where-Object CommandLine -like '*DualPcProfiles*hotkeys.ahk*' |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    $authorizedCandidates = @(
        (Join-Path $env:ProgramData 'ssh\administrators_authorized_keys')
        (Join-Path $env:USERPROFILE '.ssh\authorized_keys')
    )
    foreach ($path in $authorizedCandidates) {
        if (Test-Path $path -PathType Leaf) {
            $remaining = @(Get-Content $path | Where-Object { $_ -notmatch [regex]::Escape($marker) })
            $remaining | Set-Content $path -Encoding ascii
        }
    }

    $keyPath = Join-Path (Join-Path $env:USERPROFILE '.ssh') $config.SSH.KeyFileName
    Remove-Item $keyPath, "$keyPath.pub" -Force -ErrorAction SilentlyContinue

    Remove-NetFirewallRule `
        -DisplayName "$($config.TaskPrefix)-Spacedesk-NB" `
        -ErrorAction SilentlyContinue
    Remove-NetFirewallRule `
        -DisplayName "$($config.TaskPrefix)-SSH-Peer" `
        -ErrorAction SilentlyContinue

    $firewallStatePath = Join-Path (Join-Path $env:ProgramData 'DualPcProfiles') 'firewall-state.json'
    if (Test-Path $firewallStatePath -PathType Leaf) {
        $firewallState = Read-DppJson -Path $firewallStatePath
        foreach ($rule in @($firewallState.rules)) {
            if ([string]$rule.enabled -eq 'True') {
                Get-NetFirewallRule -Name ([string]$rule.name) -ErrorAction SilentlyContinue |
                    Enable-NetFirewallRule
            }
        }
    }

    Remove-Item (Join-Path $env:ProgramData 'DualPcProfiles') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $installRoot -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepLogs) {
        Remove-Item $runtime -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($WhatIfPreference) {
    Write-Host 'DualPcProfiles 卸載模擬完成，未變更系統。' -ForegroundColor Yellow
} else {
    Write-Host 'DualPcProfiles 已移除；PowerToys、Spacedesk、AutoHotkey 與日常 SSH 設定未變更。' -ForegroundColor Green
}
