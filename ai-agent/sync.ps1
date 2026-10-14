<#
.SYNOPSIS
    一次同步 Claude Code 與 Codex 設定（依序執行 sync-claude.ps1、sync-codex.ps1）。

.DESCRIPTION
    參數與兩支腳本相同，原樣轉交：
      預設：repo -> Windows 與 WSL。第一支失敗（例如目標內容不同又沒加 -Force）即中止，不跑第二支。
      -PullWin / -PullWsl：Windows 或 WSL -> repo。收回前先比對來源的 ~/.claude/CLAUDE.md 與 ~/.codex/AGENTS.md，
        內容不同即中止，不收回任何檔案（兩者皆來自 repo 的 AGENTS.md，只能擇一）。
      -Check：只比對，不寫入。
      -Force：覆蓋內容不同的目標。
    需要 PowerShell 7。
#>
param(
    [switch]$PullWin,
    [switch]$PullWsl,
    [switch]$Check,
    [switch]$Force,
    [string]$Distro = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'
if ($PullWin -and $PullWsl) { throw '-PullWin 與 -PullWsl 不能同時使用' }

if ($PullWin -or $PullWsl) {
    $srcRoot = if ($PullWsl) {
        $wslHome = (wsl -d $Distro -- printenv HOME | Out-String).Trim()
        if (-not $wslHome) { throw "讀不到 WSL ($Distro) 的 HOME" }
        "\\wsl.localhost\$Distro" + ($wslHome -replace '/', '\')
    } else { $HOME }
    $claudeMd = Join-Path $srcRoot '.claude\CLAUDE.md'
    $codexMd = Join-Path $srcRoot '.codex\AGENTS.md'
    $same = [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($claudeMd), [byte[]][System.IO.File]::ReadAllBytes($codexMd))
    if (-not $same) {
        Write-Error "已中止，未收回任何檔案。CLAUDE.md 與 AGENTS.md 內容不同：`n  $claudeMd`n  $codexMd"
    }
}

Write-Host '== Claude =='
& "$PSScriptRoot\sync-claude.ps1" @PSBoundParameters
Write-Host '== Codex =='
& "$PSScriptRoot\sync-codex.ps1" @PSBoundParameters
