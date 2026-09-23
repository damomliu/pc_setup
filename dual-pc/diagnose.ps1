[CmdletBinding()]
param(
    [ValidateSet('PC', 'NB')]
    [string]$Role
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$entryPoint = if (Test-Path 'C:\Program Files\DualPcProfiles\dual-pc.ps1') {
    'C:\Program Files\DualPcProfiles\dual-pc.ps1'
} else {
    Join-Path $PSScriptRoot 'dual-pc.ps1'
}

$arguments = @{
    Command = 'Diagnose'
}
if ($Role) {
    $arguments.Role = $Role
}

& $entryPoint @arguments
exit $LASTEXITCODE
