[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Request', 'Coordinator', 'Worker', 'Remote', 'Notify', 'Diagnose', 'ResetState')]
    [string]$Command,

    [ValidateSet('PC', 'mix', 'NB')]
    [string]$Profile,

    [switch]$Force,

    [ValidateSet('PC', 'NB')]
    [string]$Role,

    [string]$RequestId,

    [string]$OriginalCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'DualPcProfiles.psm1') -Force
$config = Get-DppConfig -BasePath $PSScriptRoot
$machineArguments = @{
    BasePath = $PSScriptRoot
}
if ($Role) {
    $machineArguments.Role = $Role
}
$machine = Get-DppMachineConfig @machineArguments
$localRole = [string]$machine.Role
$runtime = Get-DppRuntimePath
$taskPrefix = [string]$config.TaskPrefix

function Start-ProfileTask {
    param(
        [Parameter(Mandatory)][ValidateSet('Coordinator', 'Worker')][string]$TaskType,
        [Parameter(Mandatory)][ValidateSet('PC', 'mix', 'NB')][string]$TargetProfile
    )

    $taskName = "$taskPrefix-$TaskType-$TargetProfile"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $task) {
        throw "找不到排程工作：$taskName"
    }
    Start-ScheduledTask -TaskName $taskName
}

function Submit-CoordinatorRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('PC', 'mix', 'NB')][string]$TargetProfile,
        [Parameter(Mandatory)][bool]$ForcePhysicalPrompt,
        [Parameter(Mandatory)][ValidateSet('PC', 'NB')][string]$OriginRole,
        [Parameter(Mandatory)][string]$Id
    )

    $busyPath = Join-Path $runtime 'coordinator-busy.json'
    $pendingPath = Join-Path $runtime "requests\coordinator-$TargetProfile.json"
    $resultPath = Join-Path $runtime "results\$Id.json"
    if (Test-Path $resultPath -PathType Leaf) {
        return Read-DppJson -Path $resultPath
    }
    $existingBusy = Read-DppJson -Path $busyPath
    if ($existingBusy -and $existingBusy.requestId -eq $Id) {
        $age = (Get-Date) - [datetime]$existingBusy.createdAt
        if ($age.TotalSeconds -le [int]$config.Timeouts.StaleLockSeconds) {
            return Wait-DppResult -RequestId $Id -Config $config
        }
    }
    New-DppBusyMarker -Path $busyPath -RequestId $Id -Config $config
    try {
        Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
        Write-DppJsonAtomic -Path $pendingPath -Value ([ordered]@{
            requestId = $Id
            profile = $TargetProfile
            force = $ForcePhysicalPrompt
            originRole = $OriginRole
            createdAt = (Get-Date).ToString('o')
        })
        Start-ProfileTask -TaskType Coordinator -TargetProfile $TargetProfile
        Wait-DppResult -RequestId $Id -Config $config
    } catch {
        Remove-Item $busyPath -Force -ErrorAction SilentlyContinue
        Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Submit-LocalWorkerRequest {
    param(
        [Parameter(Mandatory)][ValidateSet('PC', 'mix', 'NB')][string]$TargetProfile,
        [Parameter(Mandatory)][string]$Id
    )

    $busyPath = Join-Path $runtime 'worker-busy.json'
    $pendingPath = Join-Path $runtime "requests\worker-$TargetProfile.json"
    $resultPath = Join-Path $runtime "results\$Id.json"
    if (Test-Path $resultPath -PathType Leaf) {
        return Read-DppJson -Path $resultPath
    }
    $existingBusy = Read-DppJson -Path $busyPath
    if ($existingBusy -and $existingBusy.requestId -eq $Id) {
        $age = (Get-Date) - [datetime]$existingBusy.createdAt
        if ($age.TotalSeconds -le [int]$config.Timeouts.StaleLockSeconds) {
            return Wait-DppResult -RequestId $Id -Config $config
        }
    }
    New-DppBusyMarker -Path $busyPath -RequestId $Id -Config $config
    try {
        Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
        Write-DppJsonAtomic -Path $pendingPath -Value ([ordered]@{
            requestId = $Id
            profile = $TargetProfile
            createdAt = (Get-Date).ToString('o')
        })
        Start-ProfileTask -TaskType Worker -TargetProfile $TargetProfile
        Wait-DppResult -RequestId $Id -Config $config
    } catch {
        Remove-Item $busyPath -Force -ErrorAction SilentlyContinue
        Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

function ConvertFrom-RemoteResult {
    param([Parameter(Mandatory)][string]$Output)

    $lines = @($Output -split "\r?\n" | Where-Object { $_.Trim() })
    if ($lines.Count -eq 0) {
        throw '遠端命令未回傳結果。'
    }
    try {
        $lines[-1] | ConvertFrom-Json
    } catch {
        throw "遠端結果不是有效 JSON：$($lines[-1])"
    }
}

function Invoke-Request {
    if (-not $Profile) {
        throw 'Request 需要 -Profile。'
    }

    $id = [guid]::NewGuid().ToString()
    try {
        if ($localRole -eq 'PC') {
            $result = Submit-CoordinatorRequest -TargetProfile $Profile -ForcePhysicalPrompt $Force.IsPresent -OriginRole PC -Id $id
        } else {
            Test-DppSupportedNetwork -Config $config
            $forceValue = if ($Force) { 1 } else { 0 }
            $remote = Invoke-DppSsh -TargetRole PC -Command "submit $Profile $forceValue $id" -Config $config
            $result = ConvertFrom-RemoteResult -Output $remote.StdOut
        }

        if (-not $result.success) {
            Show-DppNotification -Message ([string]$result.message) -Kind Error
            exit 1
        }
        $result | ConvertTo-Json -Compress -Depth 8
    } catch {
        Write-DppLog -Level ERROR -Event 'request-failed' -RequestId $id -Profile $Profile -Data @{
            role = $localRole
            error = $_.Exception.Message
        }
        Show-DppNotification -Message $_.Exception.Message -Kind Error
        throw
    }
}

function Invoke-Coordinator {
    if ($localRole -ne 'PC') {
        throw 'Coordinator 只能在 PC 執行。'
    }
    if (-not $Profile) {
        throw 'Coordinator 需要 -Profile。'
    }

    $busyPath = Join-Path $runtime 'coordinator-busy.json'
    $pendingPath = Join-Path $runtime "requests\coordinator-$Profile.json"
    $request = Read-DppJson -Path $pendingPath
    if (-not $request) {
        return
    }
    $id = [string]$request.requestId
    $lockAfterCompletion = $false
    $mutex = [Threading.Mutex]::new($false, 'Global\DualPcProfiles.Coordinator.v1')
    $mutexAcquired = $false

    try {
        try {
            $mutexAcquired = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw '另一個 coordinator worker 正在執行。'
        }

        Test-DppInteractiveSession
        Test-DppSupportedNetwork -Config $config
        Write-DppLog -Level INFO -Event 'coordinator-started' -RequestId $id -Profile $Profile -Data @{
            originRole = [string]$request.originRole
            force = [bool]$request.force
        }

        $remote = Invoke-DppSsh -TargetRole NB -Command "apply $Profile $id" -Config $config
        $nbResult = ConvertFrom-RemoteResult -Output $remote.StdOut
        if (-not $nbResult.success) {
            throw "NB 套用失敗：$($nbResult.message)"
        }

        $pcSteps = Invoke-DppLocalProfile -Profile $Profile -Role PC -Config $config -RequestId $id
        $statePath = Join-Path $runtime 'state.json'
        $previous = Read-DppJson -Path $statePath
        $previousProfile = if ($previous -and $previous.status -eq 'success') {
            [string]$previous.profile
        } else {
            'unknown'
        }
        $crossesNbBoundary = $previousProfile -ne $Profile -and ($previousProfile -eq 'NB' -or $Profile -eq 'NB')
        $promptPhysical = [bool]$request.force -or $previousProfile -eq 'unknown' -or $crossesNbBoundary
        $message = Get-DppSuccessMessage -Profile $Profile -PromptPhysicalSwitch $promptPhysical
        $allSteps = @($nbResult.steps) + @($pcSteps)

        if ($Profile -eq 'NB') {
            $promptValue = if ($promptPhysical) { 1 } else { 0 }
            Invoke-DppSsh -TargetRole NB -Command "notify $Profile $promptValue" -Config $config | Out-Null
            $lockAfterCompletion = $true
        }

        Write-DppJsonAtomic -Path $statePath -Value ([ordered]@{
            profile = $Profile
            status = 'success'
            requestId = $id
            completedAt = (Get-Date).ToString('o')
        })
        Write-DppResult -RequestId $id -Success $true -Profile $Profile -Message $message -Steps $allSteps
        Write-DppLog -Level INFO -Event 'coordinator-completed' -RequestId $id -Profile $Profile -Data @{
            promptPhysical = $promptPhysical
            steps = $allSteps
        }

        if ($Profile -ne 'NB') {
            try {
                Show-DppNotification -Message $message
            } catch {
                Write-DppLog -Level WARN -Event 'notification-failed' -RequestId $id -Profile $Profile -Data @{
                    error = $_.Exception.Message
                }
            }
        }
    } catch {
        $message = $_.Exception.Message
        Write-DppJsonAtomic -Path (Join-Path $runtime 'state.json') -Value ([ordered]@{
            profile = 'unknown'
            status = 'failed'
            requestId = $id
            failedAt = (Get-Date).ToString('o')
            error = $message
        })
        Write-DppResult -RequestId $id -Success $false -Profile $Profile -Message $message
        Write-DppLog -Level ERROR -Event 'coordinator-failed' -RequestId $id -Profile $Profile -Data @{
            error = $message
        }
    } finally {
        Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
        Remove-Item $busyPath -Force -ErrorAction SilentlyContinue
        if ($mutexAcquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }

    if ($lockAfterCompletion) {
        Start-Process "$env:SystemRoot\System32\rundll32.exe" -ArgumentList 'user32.dll,LockWorkStation'
    }
}

function Invoke-Worker {
    if ($localRole -ne 'NB') {
        throw 'Worker 只能在 NB 執行。'
    }
    if (-not $Profile) {
        throw 'Worker 需要 -Profile。'
    }

    $busyPath = Join-Path $runtime 'worker-busy.json'
    $pendingPath = Join-Path $runtime "requests\worker-$Profile.json"
    $request = Read-DppJson -Path $pendingPath
    if (-not $request) {
        return
    }
    $id = [string]$request.requestId
    $mutex = [Threading.Mutex]::new($false, 'Global\DualPcProfiles.Worker.v1')
    $mutexAcquired = $false

    try {
        try {
            $mutexAcquired = $mutex.WaitOne(0)
        } catch [Threading.AbandonedMutexException] {
            $mutexAcquired = $true
        }
        if (-not $mutexAcquired) {
            throw '另一個 NB worker 正在執行。'
        }

        $steps = Invoke-DppLocalProfile -Profile $Profile -Role NB -Config $config -RequestId $id
        Write-DppResult -RequestId $id -Success $true -Profile $Profile -Message 'NB 本機狀態已套用。' -Steps $steps
    } catch {
        Write-DppResult -RequestId $id -Success $false -Profile $Profile -Message $_.Exception.Message
        Write-DppLog -Level ERROR -Event 'worker-failed' -RequestId $id -Profile $Profile -Data @{
            error = $_.Exception.Message
        }
    } finally {
        Remove-Item $pendingPath -Force -ErrorAction SilentlyContinue
        Remove-Item $busyPath -Force -ErrorAction SilentlyContinue
        if ($mutexAcquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Invoke-Remote {
    $incoming = if ($OriginalCommand) {
        $OriginalCommand.Trim()
    } else {
        ([string]$env:SSH_ORIGINAL_COMMAND).Trim()
    }
    if (-not $incoming) {
        throw '缺少 SSH_ORIGINAL_COMMAND。'
    }

    if ($localRole -eq 'PC' -and $incoming -match '^submit (PC|mix|NB) ([01]) ([0-9a-fA-F-]{36})$') {
        $result = Submit-CoordinatorRequest -TargetProfile $Matches[1] -ForcePhysicalPrompt ($Matches[2] -eq '1') -OriginRole NB -Id $Matches[3]
        $result | ConvertTo-Json -Compress -Depth 8
        return
    }

    if ($localRole -eq 'PC' -and $incoming -match '^reset ([0-9a-fA-F-]{36})$') {
        Write-DppJsonAtomic -Path (Join-Path $runtime 'state.json') -Value ([ordered]@{
            profile = 'unknown'
            status = 'reset'
            requestId = $Matches[1]
            resetAt = (Get-Date).ToString('o')
        })
        '{"success":true}'
        return
    }

    if ($localRole -eq 'NB' -and $incoming -match '^apply (PC|mix|NB) ([0-9a-fA-F-]{36})$') {
        $result = Submit-LocalWorkerRequest -TargetProfile $Matches[1] -Id $Matches[2]
        $result | ConvertTo-Json -Compress -Depth 8
        return
    }

    if ($localRole -eq 'NB' -and $incoming -match '^notify (PC|mix|NB) ([01])$') {
        Write-DppJsonAtomic -Path (Join-Path $runtime 'notification.json') -Value ([ordered]@{
            profile = $Matches[1]
            promptPhysical = $Matches[2] -eq '1'
            createdAt = (Get-Date).ToString('o')
        })
        $taskName = "$taskPrefix-Notify"
        if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
            throw "找不到排程工作：$taskName"
        }
        Start-ScheduledTask -TaskName $taskName
        '{"success":true}'
        return
    }

    throw '拒絕未授權或格式錯誤的遠端命令。'
}

function Invoke-Notify {
    $path = Join-Path $runtime 'notification.json'
    $notification = Read-DppJson -Path $path
    if (-not $notification) {
        throw '找不到 notification.json。'
    }
    try {
        $message = Get-DppSuccessMessage -Profile ([string]$notification.profile) -PromptPhysicalSwitch ([bool]$notification.promptPhysical)
        Show-DppNotification -Message $message
    } finally {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
}

function Reset-ProfileState {
    $id = [guid]::NewGuid().ToString()
    if ($localRole -eq 'PC') {
        Write-DppJsonAtomic -Path (Join-Path $runtime 'state.json') -Value ([ordered]@{
            profile = 'unknown'
            status = 'reset'
            requestId = $id
            resetAt = (Get-Date).ToString('o')
        })
    } else {
        try {
            Invoke-DppSsh -TargetRole PC -Command "reset $id" -Config $config | Out-Null
        } catch {
            Write-DppLog -Level WARN -Event 'remote-state-reset-failed' -RequestId $id -Data @{
                error = $_.Exception.Message
            }
        }
    }
}

function Invoke-Diagnose {
    $checks = [System.Collections.Generic.List[object]]::new()

    function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
        $checks.Add([pscustomobject]@{
            Check = $Name
            Passed = $Passed
            Detail = $Detail
        })
    }

    Add-Check '角色' ($localRole -in @('PC', 'NB')) "$localRole / $env:COMPUTERNAME / $env:USERNAME"
    $expected = $config[$localRole]
    Add-Check '電腦名稱' ($env:COMPUTERNAME -eq $expected.ComputerName) "預期 $($expected.ComputerName)"
    Add-Check '使用者' ($env:USERNAME -eq $expected.UserName) "預期 $($expected.UserName)"

    $networkOk = $false
    try {
        Test-DppSupportedNetwork -Config $config
        $networkOk = $true
    } catch {
    }
    Add-Check '受支援內網' $networkOk "$($config.NetworkPrefix)*"

    foreach ($commandName in @('pwsh.exe', 'ssh.exe')) {
        Add-Check $commandName ([bool](Get-Command $commandName -ErrorAction SilentlyContinue)) '必備命令'
    }
    $autoHotkeyPath = Get-DppAutoHotkeyPath
    Add-Check 'AutoHotkey v2' ([bool]$autoHotkeyPath) $(if ($autoHotkeyPath) { $autoHotkeyPath } else { '找不到 AutoHotkey64.exe' })
    $powerToys = Get-Process -Name $config.PowerToys.ProcessName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    Add-Check 'PowerToys' ([bool]$powerToys) '程序必須執行中'
    if ($powerToys) {
        $powerToysRoot = Split-Path $powerToys.Path -Parent
        $settingsExecutable = Join-Path $powerToysRoot $config.PowerToys.SettingsExecutable
        $dscModule = Join-Path $powerToysRoot $config.PowerToys.DscModule
        $dscSupported = Test-Path $dscModule -PathType Leaf
        if ($dscSupported) {
            $dscSupported = (Get-Content $dscModule -Raw) -match 'General\.Enabled\.MouseWithoutBorders'
        }
        foreach ($path in @($settingsExecutable, $dscModule)) {
            $signature = Get-AuthenticodeSignature $path
            $dscSupported = $dscSupported -and
                $signature.Status -eq 'Valid' -and
                $signature.SignerCertificate.Subject -match 'Microsoft Corporation'
        }
        Add-Check 'PowerToys DSC bridge' (
            (Test-Path $settingsExecutable -PathType Leaf) -and $dscSupported
        ) $settingsExecutable
    }
    $policyName = 'ConfigureEnabledUtilityMouseWithoutBorders'
    $policyValues = @(
        foreach ($policyPath in @(
            'HKLM:\Software\Policies\PowerToys'
            'HKCU:\Software\Policies\PowerToys'
        )) {
            $value = Get-ItemPropertyValue $policyPath $policyName -ErrorAction SilentlyContinue
            if ($null -ne $value) {
                "$policyPath=$value"
            }
        }
    )
    Add-Check 'Mouse Without Borders 政策' ($policyValues.Count -eq 0) $(if ($policyValues) {
        $policyValues -join '; '
    } else {
        '未設定，可由 profile 切換'
    })

    $keyPath = Join-Path (Join-Path $env:USERPROFILE '.ssh') $config.SSH.KeyFileName
    Add-Check 'profile SSH 私鑰' (Test-Path $keyPath -PathType Leaf) $keyPath

    $peerRole = if ($localRole -eq 'PC') { 'NB' } else { 'PC' }
    $peer = $config[$peerRole]
    $peerSshReachable = Test-NetConnection `
        -ComputerName $peer.IP `
        -Port $config.SSH.Port `
        -InformationLevel Quiet `
        -WarningAction SilentlyContinue
    Add-Check 'Peer 內網 SSH' $peerSshReachable "$($peer.IP):$($config.SSH.Port)"

    $sshRule = Get-NetFirewallRule -DisplayName "$taskPrefix-SSH-Peer" -ErrorAction SilentlyContinue |
        Where-Object Enabled -eq 'True' |
        Select-Object -First 1
    $sshFirewallOk = $false
    if ($sshRule) {
        $sshPortFilter = $sshRule | Get-NetFirewallPortFilter
        $sshAddressFilter = $sshRule | Get-NetFirewallAddressFilter
        $sshFirewallOk =
            $sshPortFilter.Protocol -eq 'TCP' -and
            [string]$sshPortFilter.LocalPort -eq [string]$config.SSH.Port -and
            $sshAddressFilter.RemoteAddress -contains $peer.IP
    }
    Add-Check 'Peer SSH 防火牆' $sshFirewallOk "只允許 $($peer.IP):$($config.SSH.Port)"

    $taskType = if ($localRole -eq 'PC') { 'Coordinator' } else { 'Worker' }
    foreach ($targetProfile in @('PC', 'mix', 'NB')) {
        $name = "$taskPrefix-$taskType-$targetProfile"
        Add-Check $name ([bool](Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) '互動式排程工作'
    }
    if ($localRole -eq 'NB') {
        $name = "$taskPrefix-Notify"
        Add-Check $name ([bool](Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) '通知排程工作'
        $viewer = Get-StartApps | Where-Object Name -match $config.Spacedesk.ViewerAppNamePattern
        $viewerDetail = if ($viewer) {
            "$($viewer.Name) / $($viewer.AppID)"
        } else {
            $config.Spacedesk.ViewerAppNamePattern
        }
        Add-Check 'Spacedesk Viewer' ([bool]$viewer) $viewerDetail
    } else {
        $service = Get-Service -Name $config.Spacedesk.DriverServiceName -ErrorAction SilentlyContinue
        Add-Check 'Spacedesk Driver' ($service -and $service.Status -eq 'Running') $config.Spacedesk.DriverServiceName
        $ruleName = "$taskPrefix-Spacedesk-NB"
        $restrictedRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue |
            Where-Object Enabled -eq 'True' |
            Select-Object -First 1
        $firewallOk = $false
        if ($restrictedRule) {
            $portFilter = $restrictedRule | Get-NetFirewallPortFilter
            $addressFilter = $restrictedRule | Get-NetFirewallAddressFilter
            $firewallOk =
                $portFilter.Protocol -eq 'TCP' -and
                [string]$portFilter.LocalPort -eq [string]$config.Spacedesk.Port -and
                $addressFilter.RemoteAddress -contains $config.NB.IP
        }
        $broadRule = Get-NetFirewallRule -DisplayName $config.Spacedesk.DriverServiceName -ErrorAction SilentlyContinue |
            Where-Object Enabled -eq 'True'
        Add-Check 'Spacedesk 防火牆' ($firewallOk -and -not $broadRule) "只允許 $($config.NB.IP):$($config.Spacedesk.Port)"
    }

    $checks | Format-Table -AutoSize
    if ($checks.Passed -contains $false) {
        exit 1
    }
}

switch ($Command) {
    'Request' { Invoke-Request }
    'Coordinator' { Invoke-Coordinator }
    'Worker' { Invoke-Worker }
    'Remote' { Invoke-Remote }
    'Notify' { Invoke-Notify }
    'Diagnose' { Invoke-Diagnose }
    'ResetState' { Reset-ProfileState }
}
