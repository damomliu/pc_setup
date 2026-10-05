<#
.SYNOPSIS
    在 repo 的 power_shell/profile.ps1 與兩種 PowerShell 的 profile 之間同步。

.DESCRIPTION
    預設：repo -> PowerShell 7 與 Windows PowerShell 5.1 兩個 profile。
    -Pull：PowerShell 7 profile -> repo，直接改過 profile 後用來收回 repo（5.1 不會被收回，需再跑一次預設同步）。
    -Check：只比對 SHA256，不複製。
#>
param(
    [switch]$Pull,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$repoFile = Join-Path $PSScriptRoot 'profile.ps1'
$docs = [Environment]::GetFolderPath('MyDocuments')
$ps7 = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
$ps5 = Join-Path $docs 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'

if ($Check) {
    Get-FileHash $repoFile, $ps7, $ps5 | Select-Object Hash, Path | Format-Table -AutoSize
    return
}

if ($Pull) {
    Copy-Item $ps7 $repoFile -Force
    Write-Host "$ps7 -> $repoFile"
    return
}

foreach ($to in $ps7, $ps5) {
    New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
    Copy-Item $repoFile $to -Force
    Write-Host "$repoFile -> $to"
}
