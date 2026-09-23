[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('PC', 'NB')]
    [string]$Role,

    [string]$PeerPublicKeyPath,

    [switch]$SkipFirewall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '請以系統管理員身分執行 install.ps1。'
    }
}

function Find-AutoHotkeyV2 {
    $path = Get-DppAutoHotkeyPath
    if (-not $path) {
        throw '找不到 AutoHotkey v2。請先安裝 v2 後再執行安裝器。'
    }
    $path
}

function Get-AuthorizedKeysPath {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    }
    Join-Path $env:USERPROFILE '.ssh\authorized_keys'
}

function Install-PeerPublicKey {
    param(
        [Parameter(Mandatory)][string]$PublicKeyPath,
        [Parameter(Mandatory)][string]$WrapperPath,
        [Parameter(Mandatory)][string]$SourceRole
    )

    if (-not (Test-Path $PublicKeyPath -PathType Leaf)) {
        throw "找不到 peer 公鑰：$PublicKeyPath"
    }
    $publicKey = (Get-Content $PublicKeyPath -Raw).Trim()
    if ($publicKey -notmatch '^(ssh-ed25519|sk-ssh-ed25519@\S+) [A-Za-z0-9+/=]+(?:\s+.*)?$') {
        throw 'peer 公鑰不是支援的 Ed25519 OpenSSH 格式。'
    }
    $parts = $publicKey -split '\s+'
    $marker = "dual-pc-profiles-$SourceRole-to-$Role"
    $sourceIp = [string]$config[$SourceRole].IP
    $options = "from=`"$sourceIp`",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding"
    $escapedWrapper = $WrapperPath.Replace('\', '\\')
    $line = "$options,command=`"$escapedWrapper`" $($parts[0]) $($parts[1]) $marker"
    $authorizedKeys = Get-AuthorizedKeysPath
    $directory = Split-Path $authorizedKeys -Parent
    New-Item $directory -ItemType Directory -Force | Out-Null
    $existing = if (Test-Path $authorizedKeys) { @(Get-Content $authorizedKeys) } else { @() }
    $updated = @($existing | Where-Object { $_ -notmatch [regex]::Escape($marker) }) + $line
    $updated | Set-Content $authorizedKeys -Encoding ascii

    if ($authorizedKeys -like "$env:ProgramData\ssh\*") {
        & icacls.exe $authorizedKeys /inheritance:r /grant '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "無法設定 $authorizedKeys 的 ACL。"
        }
    }
}

if (-not $WhatIfPreference) {
    Assert-Administrator
}
Import-Module (Join-Path $PSScriptRoot 'DualPcProfiles.psm1') -Force
$config = Get-DppConfig -BasePath $PSScriptRoot
$expected = $config[$Role]
if ($env:COMPUTERNAME -ne $expected.ComputerName) {
    throw "角色 $Role 應安裝於 $($expected.ComputerName)，目前是 $env:COMPUTERNAME。"
}
if ($env:USERNAME -ne $expected.UserName) {
    throw "角色 $Role 應由使用者 $($expected.UserName) 安裝，目前是 $env:USERNAME。"
}

$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
[void](Get-Command ssh.exe -ErrorAction Stop)
$sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
$autoHotkey = Find-AutoHotkeyV2
$installRoot = [string]$config.InstallRoot
$normalizedInstallRoot = [IO.Path]::GetFullPath($installRoot).TrimEnd('\')
$normalizedProgramFiles = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')
if (
    -not $normalizedInstallRoot.StartsWith("$normalizedProgramFiles\", [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path $normalizedInstallRoot -Leaf) -ne 'DualPcProfiles'
) {
    throw "不安全的 InstallRoot：$installRoot"
}
$programDataRoot = Join-Path $env:ProgramData 'DualPcProfiles'
$remoteWrapper = Join-Path $programDataRoot 'remote.cmd'
$runtime = Get-DppRuntimePath

if ($PSCmdlet.ShouldProcess($installRoot, "安裝 DualPcProfiles $Role")) {
    New-Item $installRoot -ItemType Directory -Force | Out-Null
    foreach ($name in @(
        'config.psd1'
        'DualPcProfiles.psm1'
        'dual-pc.ps1'
        'hotkeys.ahk'
    )) {
        Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $installRoot $name) -Force
    }

    @"
@{
    Role = '$Role'
    InstalledAt = '$((Get-Date).ToString('o'))'
}
"@ | Set-Content (Join-Path $installRoot 'machine.psd1') -Encoding utf8NoBOM

    New-Item $programDataRoot -ItemType Directory -Force | Out-Null
    @"
@echo off
"$pwsh" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$installRoot\dual-pc.ps1" -Command Remote
"@ | Set-Content $remoteWrapper -Encoding ascii
    & icacls.exe $programDataRoot /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "無法設定 $programDataRoot 的 ACL。"
    }

    $keyDirectory = Join-Path $env:USERPROFILE '.ssh'
    $keyPath = Join-Path $keyDirectory $config.SSH.KeyFileName
    New-Item $keyDirectory -ItemType Directory -Force | Out-Null
    if (-not (Test-Path $keyPath -PathType Leaf)) {
        Invoke-DppProcess -FilePath $sshKeygen -ArgumentList @(
            '-q'
            '-t'
            'ed25519'
            '-f'
            $keyPath
            '-N'
            ''
            '-C'
            "dual-pc-profiles-$Role"
        ) -TimeoutSeconds 30 | Out-Null
    }

    if ($PeerPublicKeyPath) {
        $sourceRole = if ($Role -eq 'PC') { 'NB' } else { 'PC' }
        Install-PeerPublicKey -PublicKeyPath $PeerPublicKeyPath -WrapperPath $remoteWrapper -SourceRole $sourceRole
    }

    $account = "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
    $logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $account
    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances Queue `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries
    $taskType = if ($Role -eq 'PC') { 'Coordinator' } else { 'Worker' }
    foreach ($profileName in @('PC', 'mix', 'NB')) {
        $taskName = "$($config.TaskPrefix)-$taskType-$profileName"
        $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installRoot\dual-pc.ps1`" -Command $taskType -Profile $profileName"
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $logonTrigger `
            -Principal $principal `
            -Settings $settings `
            -Description "Dual PC Profiles $taskType $profileName" `
            -Force | Out-Null
    }

    if ($Role -eq 'NB') {
        $taskName = "$($config.TaskPrefix)-Notify"
        $arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$installRoot\dual-pc.ps1`" -Command Notify"
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Principal $principal `
            -Settings $settings `
            -Description 'Dual PC Profiles notification' `
            -Force | Out-Null
    }

    $startup = [Environment]::GetFolderPath('Startup')
    $shortcutPath = Join-Path $startup 'Dual PC Profiles.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $autoHotkey
    $shortcut.Arguments = "`"$installRoot\hotkeys.ahk`""
    $shortcut.WorkingDirectory = $installRoot
    $shortcut.Description = 'Dual PC Profiles hotkeys'
    $shortcut.Save()

    Get-Process AutoHotkey64 -ErrorAction SilentlyContinue |
        Where-Object Path -eq $autoHotkey |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process $autoHotkey -ArgumentList "`"$installRoot\hotkeys.ahk`""

    if (-not $SkipFirewall) {
        $peerRoleForFirewall = if ($Role -eq 'PC') { 'NB' } else { 'PC' }
        $sshRuleName = "$($config.TaskPrefix)-SSH-Peer"
        Remove-NetFirewallRule -DisplayName $sshRuleName -ErrorAction SilentlyContinue
        New-NetFirewallRule `
            -DisplayName $sshRuleName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $config.SSH.Port `
            -RemoteAddress $config[$peerRoleForFirewall].IP `
            -Profile Any | Out-Null
    }

    if ($Role -eq 'PC' -and -not $SkipFirewall) {
        $ruleName = "$($config.TaskPrefix)-Spacedesk-NB"
        $firewallStatePath = Join-Path $programDataRoot 'firewall-state.json'
        $spacedeskRules = @(
            Get-NetFirewallRule -DisplayName $config.Spacedesk.DriverServiceName -ErrorAction SilentlyContinue |
                Where-Object DisplayName -ne $ruleName
        )
        if (-not (Test-Path $firewallStatePath -PathType Leaf)) {
            Write-DppJsonAtomic -Path $firewallStatePath -Value ([ordered]@{
                rules = @(
                    $spacedeskRules | ForEach-Object {
                        [ordered]@{
                            name = $_.Name
                            enabled = [string]$_.Enabled
                        }
                    }
                )
            })
        }
        $spacedeskRules |
            Where-Object Enabled -eq 'True' |
            Disable-NetFirewallRule

        Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $config.Spacedesk.Port `
            -RemoteAddress $config.NB.IP `
            -Profile Any | Out-Null
    }

}

if ($WhatIfPreference) {
    Write-Host "DualPcProfiles（$Role）安裝模擬完成，未變更系統。" -ForegroundColor Yellow
} else {
    Write-Host "已安裝 DualPcProfiles（$Role）。" -ForegroundColor Green
}
Write-Host "本機公鑰：$(Join-Path (Join-Path $env:USERPROFILE '.ssh') "$($config.SSH.KeyFileName).pub")"
if (-not $PeerPublicKeyPath) {
    Write-Warning '尚未授權 peer 公鑰。請將另一台電腦的 .pub 複製到本機後，以 -PeerPublicKeyPath 重新執行安裝器。'
}
$peerRole = if ($Role -eq 'PC') { 'NB' } else { 'PC' }
Write-Host "請先以 profile 金鑰手動 SSH 至 $($config[$peerRole].IP)，確認 host key 後再執行 diagnose。"
