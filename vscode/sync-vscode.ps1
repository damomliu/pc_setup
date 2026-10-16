<#
.SYNOPSIS
    在 repo 的 vscode/ 與 %APPDATA%\Code\User 之間同步 VS Code 設定。

.DESCRIPTION
    預設：repo -> VS Code（settings.json、keybindings.json、mcp.json）。VS Code 執行中也可以跑，會自動重載。
    -Pull：VS Code -> repo，在 VS Code UI 改過設定後用來收回 repo。
    -Check：只比對 repo 與 VS Code 的設定檔是否一致，不複製；有差異時 exit code 為 1。
    -Extensions：依 extensions.json 補裝各 profile 缺少的 extension。
    -Prune：搭配 -Extensions，另外移除 extensions.json 沒列的 extension。
#>
param(
    [switch]$Pull,
    [switch]$Check,
    [switch]$Extensions,
    [switch]$Prune
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$user = Join-Path $env:APPDATA 'Code\User'
$code = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
$files = 'settings.json', 'keybindings.json', 'mcp.json'

if ($Check) {
    $diff = 0
    foreach ($f in $files) {
        $a = Join-Path $repo $f
        $b = Join-Path $user $f
        if (-not (Test-Path $b)) { $state = 'missing'; $diff++ }
        elseif ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash) { $state = 'differ'; $diff++ }
        else { $state = 'same' }
        Write-Host ("{0,-8} {1}" -f $state, $f)
    }
    exit [int]($diff -gt 0)
}

foreach ($f in $files) {
    if ($Pull) { $from = Join-Path $user $f; $to = Join-Path $repo $f }
    else { $from = Join-Path $repo $f; $to = Join-Path $user $f }
    Copy-Item $from $to -Force
    Write-Host "$from -> $to"
}

if ($Extensions) {
    $wanted = Get-Content (Join-Path $repo 'extensions.json') -Raw | ConvertFrom-Json
    foreach ($p in $wanted.PSObject.Properties) {
        $profileArgs = if ($p.Name -eq 'Default') { @() } else { @('--profile', $p.Name) }
        $installed = & $code @profileArgs --list-extensions | ForEach-Object { $_.ToLower() }
        $list = $p.Value | ForEach-Object { $_.ToLower() }
        foreach ($id in $list | Where-Object { $_ -notin $installed }) {
            Write-Host "[$($p.Name)] install $id"
            & $code @profileArgs --install-extension $id | Out-Null
        }
        if ($Prune) {
            foreach ($id in $installed | Where-Object { $_ -notin $list }) {
                Write-Host "[$($p.Name)] uninstall $id"
                & $code @profileArgs --uninstall-extension $id | Out-Null
            }
        }
    }
}
