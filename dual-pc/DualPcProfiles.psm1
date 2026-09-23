Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DppConfig {
    param([Parameter(Mandatory)][string]$BasePath)

    $path = Join-Path $BasePath 'config.psd1'
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "找不到設定檔：$path"
    }

    Import-PowerShellDataFile -Path $path
}

function Get-DppMachineConfig {
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [ValidateSet('PC', 'NB')][string]$Role
    )

    if ($Role) {
        return @{ Role = $Role }
    }

    $path = Join-Path $BasePath 'machine.psd1'
    if (-not (Test-Path $path -PathType Leaf)) {
        throw "尚未安裝或缺少 machine.psd1。請先執行 install.ps1。"
    }

    Import-PowerShellDataFile -Path $path
}

function Get-DppRuntimePath {
    $path = Join-Path $env:LOCALAPPDATA 'DualPcProfiles'
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }

    foreach ($name in @('logs', 'requests', 'results')) {
        $child = Join-Path $path $name
        if (-not (Test-Path $child)) {
            New-Item -Path $child -ItemType Directory -Force | Out-Null
        }
    }

    $path
}

function Write-DppJsonAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $directory = Split-Path $Path -Parent
    if (-not (Test-Path $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth 8 | Set-Content -Path $temporaryPath -Encoding utf8NoBOM
    Move-Item -Path $temporaryPath -Destination $Path -Force
}

function Read-DppJson {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path -PathType Leaf)) {
        return $null
    }

    Get-Content -Path $Path -Raw -Encoding utf8 | ConvertFrom-Json
}

function Write-DppLog {
    param(
        [Parameter(Mandatory)][ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Event,
        [string]$RequestId,
        [string]$Profile,
        [hashtable]$Data = @{}
    )

    $runtime = Get-DppRuntimePath
    $entry = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        level = $Level
        event = $Event
        requestId = $RequestId
        profile = $Profile
        computer = $env:COMPUTERNAME
        user = $env:USERNAME
        data = $Data
    }
    $path = Join-Path $runtime "logs\$((Get-Date).ToString('yyyy-MM-dd')).jsonl"
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress -Depth 8) -Encoding utf8

    Get-ChildItem (Join-Path $runtime 'logs') -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Invoke-DppProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 30,
        [switch]$AllowFailure
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "無法啟動：$FilePath"
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $process.Kill($true)
        } catch {
        }
        throw "命令逾時（${TimeoutSeconds}s）：$FilePath"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    $result = [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }

    if (-not $AllowFailure -and $result.ExitCode -ne 0) {
        $detail = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { "exit $($result.ExitCode)" }
        throw "命令失敗：$FilePath；$detail"
    }

    $result
}

function Test-DppInteractiveSession {
    $sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $explorer = Get-Process explorer -ErrorAction SilentlyContinue |
        Where-Object SessionId -eq $sessionId |
        Select-Object -First 1
    if (-not $explorer) {
        throw '目前不是具有 Explorer 的本機互動式工作階段。'
    }
}

function Test-DppSupportedNetwork {
    param([Parameter(Mandatory)]$Config)

    $matched = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress.StartsWith([string]$Config.NetworkPrefix) -and
            $_.AddressState -eq 'Preferred'
        }
    if (-not $matched) {
        throw "目前不在受支援網路 $($Config.NetworkPrefix)*。"
    }
}

function Get-DppAutoHotkeyPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe')
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe')
        (Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $null
}

function Show-DppNotification {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = '雙電腦顯示切換',
        [ValidateSet('Info', 'Warning', 'Error')][string]$Kind = 'Info',
        [int]$TimeoutSeconds = 10
    )

    $icon = switch ($Kind) {
        'Error' { 16 }
        'Warning' { 48 }
        default { 64 }
    }
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Popup($Message, $TimeoutSeconds, $Title, $icon)
}

function Set-DppMouseWithoutBorders {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)]$Config
    )

    $powerToysProcess = Get-Process -Name $Config.PowerToys.ProcessName -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $powerToysProcess) {
        throw 'PowerToys 尚未啟動。'
    }

    $powerToysPath = $powerToysProcess.Path
    $powerToysRoot = Split-Path $powerToysPath -Parent
    $settingsExecutable = Join-Path $powerToysRoot $Config.PowerToys.SettingsExecutable
    $dscModule = Join-Path $powerToysRoot $Config.PowerToys.DscModule
    $generalSettings = Join-Path $env:LOCALAPPDATA $Config.PowerToys.GeneralSettingsPath
    foreach ($path in @($settingsExecutable, $dscModule, $generalSettings)) {
        if (-not (Test-Path $path -PathType Leaf)) {
            throw "缺少 PowerToys DSC 元件：$path"
        }
    }
    foreach ($path in @($settingsExecutable, $dscModule)) {
        $signature = Get-AuthenticodeSignature $path
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw "PowerToys DSC 元件簽章無效：$path"
        }
    }

    $dscSource = Get-Content $dscModule -Raw
    if ($dscSource -notmatch 'General\.Enabled\.MouseWithoutBorders') {
        throw '此 PowerToys 版本的內建 DSC 模組不支援 Mouse Without Borders。'
    }

    $policyName = 'ConfigureEnabledUtilityMouseWithoutBorders'
    foreach ($policyPath in @(
        'HKLM:\Software\Policies\PowerToys'
        'HKCU:\Software\Policies\PowerToys'
    )) {
        $policy = Get-ItemPropertyValue $policyPath $policyName -ErrorAction SilentlyContinue
        if ($null -ne $policy -and [bool][int]$policy -ne $Enabled) {
            throw "PowerToys 政策 $policyPath\$policyName 與目標狀態衝突。"
        }
    }

    $settings = Get-Content $generalSettings -Raw | ConvertFrom-Json
    $configured = [bool]$settings.enabled.MouseWithoutBorders
    $running = [bool](Get-Process -Name $Config.PowerToys.MouseWithoutBordersProcessName -ErrorAction SilentlyContinue)
    if ($configured -eq $Enabled -and $running -eq $Enabled) {
        return
    }

    Get-Process -Name 'PowerToys.Settings' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name $Config.PowerToys.ProcessName -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction Stop
    try {
        Invoke-DppProcess -FilePath $settingsExecutable -ArgumentList @(
            'set'
            'General.Enabled.MouseWithoutBorders'
            ([string]$Enabled)
        ) -TimeoutSeconds 20 | Out-Null
    } finally {
        if (-not (Get-Process -Name $Config.PowerToys.ProcessName -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $powerToysPath
        }
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        $powerToysRunning = [bool](Get-Process -Name $Config.PowerToys.ProcessName -ErrorAction SilentlyContinue)
        $running = [bool](Get-Process -Name $Config.PowerToys.MouseWithoutBordersProcessName -ErrorAction SilentlyContinue)
        if ($powerToysRunning -and $running -eq $Enabled) {
            return
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    $expected = if ($Enabled) { '啟用' } else { '停用' }
    throw "PowerToys DSC 完成，但 Mouse Without Borders 未在 15 秒內$expected。"
}

function Stop-DppSpacedeskViewer {
    param([Parameter(Mandatory)]$Config)

    foreach ($name in $Config.Spacedesk.ViewerProcessNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction Stop
    }
}

function Start-DppSpacedeskViewer {
    param([Parameter(Mandatory)]$Config)

    foreach ($name in $Config.Spacedesk.ViewerProcessNames) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
            return
        }
    }

    $app = Get-StartApps |
        Where-Object Name -match $Config.Spacedesk.ViewerAppNamePattern |
        Select-Object -First 1
    if (-not $app) {
        throw "找不到符合 $($Config.Spacedesk.ViewerAppNamePattern) 的 Spacedesk Viewer。"
    }

    Start-Process explorer.exe -ArgumentList "shell:AppsFolder\$($app.AppID)"
    $deadline = (Get-Date).AddSeconds([int]$Config.Timeouts.SpacedeskSeconds)
    do {
        foreach ($name in $Config.Spacedesk.ViewerProcessNames) {
            if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
                return
            }
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw 'Spacedesk Viewer 未在期限內啟動。'
}

function Test-DppSpacedeskMonitor {
    param([Parameter(Mandatory)]$Config)

    $patterns = @($Config.Spacedesk.MonitorPatterns)
    $values = @()
    $values += Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
        ForEach-Object {
            [Text.Encoding]::ASCII.GetString([byte[]]($_.ManufacturerName + $_.UserFriendlyName)).Trim([char]0)
        }
    $values += Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
        Where-Object PNPClass -eq 'Monitor' |
        ForEach-Object { "$($_.Name) $($_.Manufacturer) $($_.DeviceID)" }

    foreach ($value in $values) {
        foreach ($pattern in $patterns) {
            if ($value -match [regex]::Escape([string]$pattern)) {
                return $true
            }
        }
    }

    $false
}

function Wait-DppSpacedeskMonitor {
    param([Parameter(Mandatory)]$Config)

    $deadline = (Get-Date).AddSeconds([int]$Config.Timeouts.SpacedeskSeconds)
    do {
        if (Test-DppSpacedeskMonitor -Config $Config) {
            return
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw 'PC 未在期限內偵測到 Spacedesk 虛擬顯示器。'
}

function Set-DppDisplayMode {
    param([Parameter(Mandatory)][ValidateSet('Internal', 'Extend')][string]$Mode)

    $argument = if ($Mode -eq 'Internal') { '/internal' } else { '/extend' }
    Invoke-DppProcess -FilePath "$env:SystemRoot\System32\DisplaySwitch.exe" -ArgumentList @($argument) -TimeoutSeconds 10 | Out-Null
    Start-Sleep -Seconds 2
}

function Invoke-DppLocalProfile {
    param(
        [Parameter(Mandatory)][ValidateSet('PC', 'mix', 'NB')][string]$Profile,
        [Parameter(Mandatory)][ValidateSet('PC', 'NB')][string]$Role,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$RequestId
    )

    Test-DppInteractiveSession
    Test-DppSupportedNetwork -Config $Config
    $steps = [System.Collections.Generic.List[string]]::new()

    if ($Role -eq 'NB') {
        switch ($Profile) {
            'PC' {
                Set-DppDisplayMode -Mode Internal
                $steps.Add('NB 顯示模式：僅內建')
                Start-DppSpacedeskViewer -Config $Config
                $steps.Add('Spacedesk Viewer：已啟動')
                Set-DppMouseWithoutBorders -Enabled $false -Config $Config
                $steps.Add('Mouse Without Borders：已停用')
            }
            'mix' {
                Stop-DppSpacedeskViewer -Config $Config
                $steps.Add('Spacedesk Viewer：已停止')
                Set-DppDisplayMode -Mode Internal
                $steps.Add('NB 顯示模式：僅內建')
                Set-DppMouseWithoutBorders -Enabled $true -Config $Config
                $steps.Add('Mouse Without Borders：已啟用')
            }
            'NB' {
                Stop-DppSpacedeskViewer -Config $Config
                $steps.Add('Spacedesk Viewer：已停止')
                Set-DppDisplayMode -Mode Extend
                $steps.Add('NB 顯示模式：延伸')
                Set-DppMouseWithoutBorders -Enabled $false -Config $Config
                $steps.Add('Mouse Without Borders：已停用')
            }
        }
    } else {
        switch ($Profile) {
            'PC' {
                Wait-DppSpacedeskMonitor -Config $Config
                $steps.Add('Spacedesk 虛擬顯示器：已連線')
                Set-DppDisplayMode -Mode Extend
                $steps.Add('PC 顯示模式：延伸')
                Set-DppMouseWithoutBorders -Enabled $false -Config $Config
                $steps.Add('Mouse Without Borders：已停用')
            }
            'mix' {
                Set-DppDisplayMode -Mode Internal
                $steps.Add('PC 顯示模式：僅 LG')
                Set-DppMouseWithoutBorders -Enabled $true -Config $Config
                $steps.Add('Mouse Without Borders：已啟用')
            }
            'NB' {
                Set-DppMouseWithoutBorders -Enabled $false -Config $Config
                $steps.Add('Mouse Without Borders：已停用')
            }
        }
    }

    Write-DppLog -Level INFO -Event 'local-profile-applied' -RequestId $RequestId -Profile $Profile -Data @{
        role = $Role
        steps = @($steps)
    }
    @($steps)
}

function Invoke-DppSsh {
    param(
        [Parameter(Mandatory)][ValidateSet('PC', 'NB')][string]$TargetRole,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)]$Config
    )

    $target = $Config[$TargetRole]
    $keyPath = Join-Path (Join-Path $env:USERPROFILE '.ssh') $Config.SSH.KeyFileName
    if (-not (Test-Path $keyPath -PathType Leaf)) {
        throw "找不到 profile SSH 私鑰：$keyPath"
    }

    $arguments = @(
        '-i', $keyPath
        '-T'
        '-p', [string]$Config.SSH.Port
        '-o', 'BatchMode=yes'
        '-o', "ConnectTimeout=$($Config.SSH.ConnectTimeoutSeconds)"
        '-o', 'StrictHostKeyChecking=yes'
        "$($target.UserName)@$($target.IP)"
        $Command
    )

    $lastError = $null
    for ($attempt = 0; $attempt -le [int]$Config.SSH.RetryCount; $attempt++) {
        try {
            return Invoke-DppProcess -FilePath (Get-Command ssh.exe).Source -ArgumentList $arguments -TimeoutSeconds $Config.SSH.CommandTimeoutSeconds
        } catch {
            $lastError = $_
            if ($attempt -lt [int]$Config.SSH.RetryCount) {
                Start-Sleep -Seconds 1
            }
        }
    }

    throw $lastError
}

function New-DppBusyMarker {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)]$Config
    )

    if (Test-Path $Path) {
        $existing = Read-DppJson -Path $Path
        $isStale = $false
        if ($existing -and $existing.createdAt) {
            $age = (Get-Date) - [datetime]$existing.createdAt
            $isStale = $age.TotalSeconds -gt [int]$Config.Timeouts.StaleLockSeconds
        }
        if ($isStale) {
            Remove-Item $Path -Force
        } else {
            throw '正在切換，新的要求已拒絕。'
        }
    }

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.Encoding]::UTF8.GetBytes((@{
            requestId = $RequestId
            createdAt = (Get-Date).ToString('o')
        } | ConvertTo-Json -Compress))
        $stream.Write($bytes, 0, $bytes.Length)
    } catch [System.IO.IOException] {
        throw '正在切換，新的要求已拒絕。'
    } finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function Wait-DppResult {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)]$Config
    )

    $path = Join-Path (Get-DppRuntimePath) "results\$RequestId.json"
    $deadline = (Get-Date).AddSeconds([int]$Config.Timeouts.RequestSeconds)
    do {
        if (Test-Path $path -PathType Leaf) {
            return Read-DppJson -Path $path
        }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)

    throw "等待切換結果逾時：$RequestId"
}

function Write-DppResult {
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][bool]$Success,
        [Parameter(Mandatory)][string]$Profile,
        [string]$Message,
        [object[]]$Steps = @()
    )

    $path = Join-Path (Get-DppRuntimePath) "results\$RequestId.json"
    Write-DppJsonAtomic -Path $path -Value ([ordered]@{
        requestId = $RequestId
        success = $Success
        profile = $Profile
        message = $Message
        steps = @($Steps)
        completedAt = (Get-Date).ToString('o')
        computer = $env:COMPUTERNAME
    })
}

function Get-DppSuccessMessage {
    param(
        [Parameter(Mandatory)][ValidateSet('PC', 'mix', 'NB')][string]$Profile,
        [Parameter(Mandatory)][bool]$PromptPhysicalSwitch
    )

    if (-not $PromptPhysicalSwitch) {
        return "已套用 profile-$Profile。"
    }

    switch ($Profile) {
        'PC' { '軟體已就緒：請將 LG 切至 HDMI2，並將鍵盤滑鼠切到 PC。' }
        'mix' { '軟體已就緒：請將 LG 切至 HDMI2，並將鍵盤滑鼠切到 PC。' }
        'NB' { '軟體已就緒：請將 LG 切至 HDMI1，並將鍵盤滑鼠切到 NB。' }
    }
}

Export-ModuleMember -Function *
