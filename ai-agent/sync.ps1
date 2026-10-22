<#
.SYNOPSIS
    一次同步 Claude Code 與 Codex 設定（依序執行 sync-claude.ps1、sync-codex.ps1）。

.DESCRIPTION
    參數與兩支腳本相同，原樣轉交：
      預設：repo -> Windows 與 WSL。第一支失敗（例如目標內容不同又沒加 -Force）即中止，不跑第二支。
      -PullWin / -PullWsl：Windows 或 WSL -> repo。Claude 與 Codex 各自收回自己的指引與設定（兩者不再要求內容一致）。
      -Check：只比對，不寫入。
      -CheckVerbose：唯讀，並列出設定值與指引的差異（敏感值顯示 ***）。
      -Force：覆蓋內容不同的目標（各工具的忽略欄位仍保留本機值）。
    -Check / -CheckVerbose 與 -PullWin / -PullWsl / -Force 併用，或兩種 Pull 同時指定，會在任何 I/O 前拒絕。
    需要 PowerShell 7。
#>
param(
    [switch]$PullWin,
    [switch]$PullWsl,
    [switch]$Check,
    [switch]$CheckVerbose,
    [switch]$Force,
    [string]$Distro = 'Ubuntu-24.04',
    [Parameter(DontShow)][string]$TestWinHome,
    [Parameter(DontShow)][string]$TestWslRoot
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\sync-common.ps1"
Assert-SyncArgs $PSBoundParameters

Write-Host '== Claude =='
& "$PSScriptRoot\sync-claude.ps1" @PSBoundParameters
Write-Host '== Codex =='
& "$PSScriptRoot\sync-codex.ps1" @PSBoundParameters
