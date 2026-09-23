[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

$powershellFiles = @(
    Get-ChildItem $PSScriptRoot -Filter '*.ps1' -File
    Get-ChildItem $PSScriptRoot -Filter '*.psm1' -File
)
foreach ($file in $powershellFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )
    Assert-True ($errors.Count -eq 0) "$($file.Name) 有 PowerShell 語法錯誤。"
}

$config = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'config.psd1')
Assert-True ($config.PC.IP -eq '192.168.16.85') 'PC IP 不符合設計。'
Assert-True ($config.NB.IP -eq '192.168.16.54') 'NB IP 不符合設計。'
Assert-True ($config.PC.IP -ne $config.NB.IP) 'PC 與 NB 不可使用相同 IP。'
Assert-True ($config.PC.IP.StartsWith($config.NetworkPrefix)) 'PC IP 不在受支援網段。'
Assert-True ($config.NB.IP.StartsWith($config.NetworkPrefix)) 'NB IP 不在受支援網段。'

Assert-True ($config.PowerToys.SettingsExecutable -match 'PowerToys\.Settings\.exe$') '缺少 PowerToys Settings bridge 設定。'
Assert-True ($config.PowerToys.DscModule -match 'Microsoft\.PowerToys\.Configure\.psm1$') '缺少 PowerToys DSC module 設定。'

$hotkeys = Get-Content (Join-Path $PSScriptRoot 'hotkeys.ahk') -Raw
foreach ($binding in @('^!F9', '^!F10', '^!F12', '+^!F9', '+^!F10', '+^!F12')) {
    Assert-True ($hotkeys.Contains("$binding::")) "缺少 AutoHotkey 綁定：$binding"
}

Import-Module (Join-Path $PSScriptRoot 'DualPcProfiles.psm1') -Force
Assert-True ((Get-DppSuccessMessage -Profile PC -PromptPhysicalSwitch $false) -match '已套用') '一般成功通知錯誤。'
Assert-True ((Get-DppSuccessMessage -Profile NB -PromptPhysicalSwitch $true) -match 'HDMI1') 'NB 人工提示錯誤。'
Assert-True ((Get-DppSuccessMessage -Profile mix -PromptPhysicalSwitch $true) -match 'HDMI2') 'mix 人工提示錯誤。'

$rejected = Invoke-DppProcess -FilePath (Get-Command pwsh.exe).Source -ArgumentList @(
    '-NoLogo'
    '-NoProfile'
    '-File'
    (Join-Path $PSScriptRoot 'dual-pc.ps1')
    '-Command'
    'Remote'
    '-Role'
    'PC'
    '-OriginalCommand'
    'submit PC 0 00000000-0000-0000-0000-000000000000 & whoami'
) -TimeoutSeconds 10 -AllowFailure
Assert-True ($rejected.ExitCode -ne 0) 'SSH 受限入口接受了額外命令。'

$installedLayout = Join-Path ([IO.Path]::GetTempPath()) "dpp-layout-$([guid]::NewGuid().ToString('N'))"
try {
    New-Item $installedLayout -ItemType Directory -Force | Out-Null
    foreach ($name in @('config.psd1', 'DualPcProfiles.psm1', 'dual-pc.ps1')) {
        Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $installedLayout $name)
    }
    "@{ Role = 'PC' }" | Set-Content (Join-Path $installedLayout 'machine.psd1') -Encoding utf8NoBOM
    $installedInvocation = Invoke-DppProcess -FilePath (Get-Command pwsh.exe).Source -ArgumentList @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        (Join-Path $installedLayout 'dual-pc.ps1')
        '-Command'
        'Remote'
        '-OriginalCommand'
        'noop'
    ) -TimeoutSeconds 10 -AllowFailure
    $installedOutput = "$($installedInvocation.StdOut)`n$($installedInvocation.StdErr)"
    Assert-True ($installedOutput -notmatch "parameter 'Role'") '安裝後未指定 -Role 時仍觸發參數驗證錯誤。'
} finally {
    Remove-Item $installedLayout -Recurse -Force -ErrorAction SilentlyContinue
}

$testJson = Join-Path ([IO.Path]::GetTempPath()) "dpp-$([guid]::NewGuid().ToString('N')).json"
try {
    Write-DppJsonAtomic -Path $testJson -Value @{ value = 'ok' }
    $roundTrip = Read-DppJson -Path $testJson
    Assert-True ($roundTrip.value -eq 'ok') 'JSON 原子寫入或讀取失敗。'
} finally {
    Remove-Item $testJson -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "通過 $($powershellFiles.Count) 個 PowerShell 檔案及設定測試。" -ForegroundColor Green
