# Herdr popup: 在目前 workspace 新增 tab, 以 focused pane 所在的 git repo 開 git-graph-tui (ggt); 正常離開 ggt 時關閉 tab.
# 部署至 %APPDATA%\herdr\herdr-git-graph.ps1; 需要 ggt (git-graph-tui) 與 Git for Windows.
# 官方 herdr plugin (allient/git-graph-tui/integrations/herdr) 只支援 Linux/macOS, 因此 Windows 改用此 helper.
# 注意: 必須存成 UTF-8 with BOM, 否則 Windows PowerShell 5.1 會以 cp950 解析而壞掉.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$binary = $env:HERDR_BIN_PATH
$pane = $env:HERDR_ACTIVE_PANE_ID
$esc = [char]27
$savedControlC = [Console]::TreatControlCAsInput

function Invoke-Herdr {
    param([string[]]$Arguments)
    $output = & $binary @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    $data = ($output -join "`n") | ConvertFrom-Json
    if ($data.error) { throw ($data.error | ConvertTo-Json -Compress) }
    return $data.result
}
# herdr server 可能早於安裝啟動, PATH 不一定是最新的, 因此解析成絕對路徑
function Resolve-Tool {
    param([string]$Name, [string[]]$Fallbacks, [string]$Hint)
    $found = (Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ($found) { return $found }
    foreach ($path in $Fallbacks) { if (Test-Path -LiteralPath $path) { return $path } }
    throw "找不到 $Name, $Hint"
}
function Open-GitGraph {
    $git = Resolve-Tool 'git.exe' @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe')) '請先安裝 Git for Windows'
    $ggt = Resolve-Tool 'ggt.exe' @((Join-Path $env:USERPROFILE '.cargo\bin\ggt.exe')) '請先安裝 git-graph-tui (見 herdr.md)'
    $cwd = ((Invoke-Herdr @('pane', 'list')).panes | Where-Object { $_.pane_id -eq $pane } | Select-Object -First 1).cwd
    if (!$cwd) { throw '無法取得目前 pane 的目錄' }
    # PS 5.1 在 Stop 下會把 native stderr 轉成例外, 暫時放寬以顯示自訂訊息
    $ErrorActionPreference = 'Continue'
    $root = & $git -C $cwd rev-parse --show-toplevel 2>$null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0 -or !$root) { throw "不在 git repo 內: $cwd" }
    $root = ($root | Select-Object -First 1).Replace('/', '\')
    $arguments = @('tab', 'create', '--cwd', $root, '--label', 'Git Graph', '--focus')
    if ($env:HERDR_ACTIVE_WORKSPACE_ID) { $arguments += @('--workspace', $env:HERDR_ACTIVE_WORKSPACE_ID) }
    $newPane = (Invoke-Herdr $arguments).root_pane.pane_id
    $quote = { param($text) "'" + $text.Replace("'", "''") + "'" }
    # $ok 預設 false 並以 try/catch 包住: 找不到或無法啟動 ggt 時 $LASTEXITCODE 可能殘留 0, 不能只看它
    # 正常離開 (q) 才關閉 tab; 失敗時保留訊息等待按鍵
    $command = '$env:PATH = ' + (& $quote ((Split-Path $git) + ';')) + ' + $env:PATH; $ok = $false; try { & ' + (& $quote $ggt) + '; $ok = ($? -and $LASTEXITCODE -eq 0) } catch { Write-Host $_ -ForegroundColor Red }; if ($ok) { exit }; Write-Host (''ggt failed (exit '' + $LASTEXITCODE + ''). Press any key to close.''); [void][Console]::ReadKey($true); exit'
    $output = & $binary pane run $newPane $command 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane) { throw 'Missing Herdr popup context.' }
    Open-GitGraph
} catch {
    [Console]::Write($esc + '[H' + $esc + '[2J' + $esc + '[1;96mGit Graph' + $esc + '[0m' + "`r`n`r`n")
    [Console]::WriteLine("失敗： $_")
    [Console]::Write('按 Esc 或 Enter 關閉。')
    do { $key = [Console]::ReadKey($true) } while ($key.Key -ne 'Escape' -and $key.Key -ne 'Enter')
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
