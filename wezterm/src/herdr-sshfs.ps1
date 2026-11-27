param(
    [ValidateSet('open', 'unmount')][string]$Mode = 'open',
    [string]$DefaultPath = '',
    [ValidateSet('split', 'tab')][string]$Target = 'split'
)
# Herdr popup: open 在右側 split(-Target tab 則為新 tab)開 Yazi(focused pane 正在 ssh 時先以 sshfs.kr 掛載該 host 的 /, 否則開本機 cwd); unmount 選擇既有掛載後卸載.
# 部署至 %APPDATA%\herdr\herdr-sshfs.ps1, 與 sshfs-mount.ps1 同目錄; 需要 WinFsp + SSHFS-Win 與 yazi.
# 注意: 必須存成 UTF-8 with BOM, 否則 Windows PowerShell 5.1 會以 cp950 解析而壞掉.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$binary = $env:HERDR_BIN_PATH
$pane = $env:HERDR_ACTIVE_PANE_ID
$sshfsMount = Join-Path $PSScriptRoot 'sshfs-mount.ps1'
# 每台 host 上次開啟的遠端絕對路徑
$stateFile = Join-Path $env:LOCALAPPDATA 'herdr\herdr-sshfs.json'
$sshValueOptions = 'BbcDEeFIiJLlmOoPpQRSWw'
$popupTitle = $(if ($Mode -eq 'unmount') { '卸載 SSHFS' } else { '開啟 Yazi' })
$esc = [char]27
$savedControlC = [Console]::TreatControlCAsInput

function Get-PopupHeader {
    return $esc + '[H' + $esc + '[2J' + $esc + '[1;96m' + (Fit-Line $popupTitle ([Math]::Max(1, [Console]::WindowWidth - 1))) + $esc + '[0m' + "`r`n`r`n"
}
function Invoke-Herdr {
    param([string[]]$Arguments)
    $output = & $binary @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    $data = ($output -join "`n") | ConvertFrom-Json
    if ($data.error) { throw ($data.error | ConvertTo-Json -Compress) }
    return $data.result
}
function Fit-Line {
    param([string]$Text, [int]$Width)
    $Text = [regex]::Replace($Text, '[\x00-\x1f\x7f-\x9f]', ' ')
    $builder = New-Object Text.StringBuilder
    $used = 0
    $elements = [Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($elements.MoveNext()) {
        $element = $elements.GetTextElement()
        $code = [char]::ConvertToUtf32($element, 0)
        $size = 1
        if (($code -ge 0x1100 -and $code -le 0x115f) -or ($code -ge 0x2e80 -and $code -le 0xa4cf) -or ($code -ge 0xac00 -and $code -le 0xd7a3) -or ($code -ge 0xf900 -and $code -le 0xfaff) -or ($code -ge 0xfe10 -and $code -le 0xfe6f) -or ($code -ge 0xff01 -and $code -le 0xff60) -or ($code -ge 0xffe0 -and $code -le 0xffe6) -or $code -ge 0x1f000) { $size = 2 }
        if ($used + $size -gt $Width) { break }
        $null = $builder.Append($element)
        $used += $size
    }
    return $builder.ToString()
}
function Get-Width { return [Math]::Max(1, [Console]::WindowWidth - 1) }
function Clear-Popup { [Console]::Write((Get-PopupHeader)) }
function Select-Item {
    param([string[]]$Labels, [string]$Title)
    $selected = 0; $digits = ''; $message = ''
    while ($true) {
        $width = Get-Width
        $height = [Math]::Max(1, [Console]::WindowHeight)
        $rows = [Math]::Max(1, $height - 5)
        $start = [Math]::Max(0, [Math]::Min($selected - $rows + 1, $Labels.Count - $rows))
        $lines = New-Object 'Collections.Generic.List[string]'
        $lines.Add((Fit-Line ($(if ($Title -ne $popupTitle) { $Title + ' ' }) + '↑↓ / 數字 / Enter / Esc Q') $width))
        for ($index = $start; $index -lt [Math]::Min($Labels.Count, $start + $rows); $index++) {
            $line = Fit-Line ('{0}. {1}' -f ($index + 1), $Labels[$index]) $width
            if ($index -eq $selected) { $line = $esc + '[7m' + $line + $esc + '[0m' }
            $lines.Add($line)
        }
        $footer = 'Enter 確認；Esc / Q 取消'
        if ($digits) { $footer = '編號：' + $digits }
        if ($message) { $footer = $message }
        $lines.Add((Fit-Line $footer $width))
        if ($height -lt 5) { $lines.RemoveAt(0) }
        [Console]::Write((Get-PopupHeader) + (($lines | Select-Object -First ([Math]::Max(0, $height - 2))) -join "`r`n"))
        while (![Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            if ((Get-Width) -ne $width -or [Math]::Max(1, [Console]::WindowHeight) -ne $height) { break }
        }
        if (![Console]::KeyAvailable) { continue }
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Escape' -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q' -or ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) { return $null }
        if ($key.Key -eq 'UpArrow' -or $key.Key -eq 'DownArrow') {
            $digits = ''; $message = ''
            $step = 1
            if ($key.Key -eq 'UpArrow') { $step = -1 }
            $selected = [Math]::Max(0, [Math]::Min($Labels.Count - 1, $selected + $step))
        } elseif ($key.Key -eq 'Backspace') {
            if ($digits.Length) { $digits = $digits.Substring(0, $digits.Length - 1) }
            $message = ''
        } elseif ($key.KeyChar -ge '0' -and $key.KeyChar -le '9') {
            if ($digits.Length -lt 100) { $digits += $key.KeyChar }
            $message = ''
        } elseif ($key.Key -eq 'Enter') {
            $number = 0
            if ($digits -and (!([int]::TryParse($digits, [ref]$number)) -or $number -lt 1 -or $number -gt $Labels.Count)) {
                $message = '無效選項，請修改編號或使用方向鍵。'
                continue
            }
            return ($selected + 1)
        }
        $number = 0
        if ($digits -and [int]::TryParse($digits, [ref]$number) -and $number -ge 1 -and $number -le $Labels.Count) { $selected = $number - 1 }
    }
}
# 顯示訊息, Enter 回傳 $true, Esc 回傳 $false
function Confirm-Popup {
    param([string]$Message)
    Clear-Popup
    [Console]::Write((Fit-Line $Message (Get-Width)) + "`r`nEnter 繼續；Esc 取消。")
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { return $true }
        if ($key.Key -eq 'Escape' -or ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) { return $false }
    }
}
# 讀一行輸入(支援 Backspace); Esc 取消回傳 $null
function Read-Line {
    param([string]$Prompt)
    [Console]::Write($esc + '[?25h' + $Prompt)
    $value = ''
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { [Console]::Write($esc + "[?25l`r`n"); return $value }
        if ($key.Key -eq 'Escape' -or ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) { return $null }
        if ($key.Key -eq 'Backspace') {
            if ($value.Length) { $value = $value.Substring(0, $value.Length - 1); [Console]::Write("`b `b") }
        } elseif ($key.KeyChar -and ![char]::IsControl($key.KeyChar)) {
            $value += $key.KeyChar
            [Console]::Write($key.KeyChar)
        }
    }
}
# 將 Windows command line 拆成 argv(處理雙引號)
function Split-CommandLine {
    param([string]$CommandLine)
    return @([regex]::Matches($CommandLine, '"((?:[^"\\]|\\.)*)"|(\S+)') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
}
# 找 focused pane 的 shell 底下的 ssh.exe, 回傳 host(第一個非 option 參數); Windows 的 foreground process 只看得到 shell
function Get-SshHost {
    try { $info = (Invoke-Herdr @('pane', 'process-info', '--pane', $pane)).process_info } catch { return '' }
    $argvs = @($info.foreground_processes | Where-Object { [IO.Path]::GetFileName([string]$_.name) -eq 'ssh.exe' } | ForEach-Object { , @($_.argv) })
    if (!$argvs.Count -and $info.shell_pid) {
        $argvs = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($info.shell_pid) AND Name='ssh.exe'" | ForEach-Object { , (Split-CommandLine $_.CommandLine) })
    }
    foreach ($argv in $argvs) {
        for ($index = 1; $index -lt $argv.Count; $index++) {
            $arg = [string]$argv[$index]
            if ($arg -eq '--') { if ($index + 1 -lt $argv.Count) { return $argv[$index + 1] } else { return '' } }
            if ($arg.StartsWith('-') -and $arg.Length -gt 1) {
                for ($position = 1; $position -lt $arg.Length; $position++) {
                    if ($sshValueOptions.Contains([string]$arg[$position])) {
                        if ($position -eq $arg.Length - 1) { $index++ }
                        break
                    }
                }
                continue
            }
            return ($arg -replace '^ssh://', '')
        }
    }
    return ''
}
function Quote-Sh { param([string]$Text) return "'" + $Text.Replace("'", "'\''") + "'" }
# 以 ssh 將遠端路徑(空字串為 home, 可用 ~/ 開頭或相對 home)解析成絕對路徑; 不存在回傳 $null
function Resolve-Remote {
    param([string]$HostName, [string]$Path)
    if (!$Path -or $Path -eq '~') { $command = 'cd && pwd -P' }
    elseif ($Path.StartsWith('~/')) { $command = 'cd ~/' + (Quote-Sh $Path.Substring(2)) + ' && pwd -P' }
    else { $command = 'cd -- ' + (Quote-Sh $Path) + ' && pwd -P' }
    $output = @(ssh -o BatchMode=yes -o ConnectTimeout=5 $HostName $command 2>$null)
    if ($LASTEXITCODE -ne 0 -or !$output.Count) { return $null }
    $last = ([string]$output[-1]).Trim()
    if ($last.StartsWith('/')) { return $last }
    return $null
}
# 回傳 @{ Drive = 'Z:'; Remote = '\\sshfs.kr\nb' } 清單, 只含 sshfs 的 mapping
function Get-SshfsMappings {
    $result = @()
    foreach ($line in (net use 2>$null)) {
        if ($line -match '([A-Za-z]:)\s+(\\\\sshfs\S*)') {
            $result += [pscustomobject]@{ Drive = $Matches[1].ToUpper(); Remote = $Matches[2] }
        }
    }
    return $result
}
function Get-HostMapping {
    param([string]$HostName)
    return Get-SshfsMappings | Where-Object { $_.Remote -match ('^\\\\sshfs(\.[a-z]+)?\\' + [regex]::Escape($HostName) + '(\\|$)') } | Select-Object -First 1
}
function Invoke-SshfsMount {
    param([string[]]$Arguments)
    $output = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sshfsMount @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw (($output | ForEach-Object { "$_" }) -join ' ') }
}
function Get-State {
    try { return (Get-Content -Raw -Encoding UTF8 $stateFile | ConvertFrom-Json) } catch { return [pscustomobject]@{} }
}
function Save-LastPath {
    param([string]$HostName, [string]$Path)
    $state = Get-State
    $state | Add-Member -NotePropertyName $HostName -NotePropertyValue $Path -Force
    $null = New-Item -ItemType Directory -Force (Split-Path $stateFile)
    [IO.File]::WriteAllText($stateFile, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}
# 遠端絕對路徑 /a/b -> Z:\a\b
function Get-DrivePath {
    param([string]$Drive, [string]$Path)
    return $Drive + '\' + $Path.Trim('/').Replace('/', '\')
}
# 在右側 split 或新 tab 執行 Yazi, 正常退出後關閉該 pane
function Open-Yazi {
    param([string]$Root)
    # herdr server 可能早於 yazi 安裝啟動, 新 pane 的 PATH 不一定有 yazi, 因此用絕對路徑
    $yazi = (Get-Command yazi -ErrorAction SilentlyContinue).Source
    if (!$yazi) { $yazi = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\yazi.exe' }
    if (!(Test-Path $yazi)) { throw '找不到 yazi, 請先安裝: winget install --id sxyazi.yazi -e' }
    # 不用 --cwd Root: 與 WSL 相同, 先在 home 開 pane 再 cd, 避免以 sshfs 路徑為 cwd 開 pane 的延遲
    if ($Target -eq 'tab') {
        $arguments = @('tab', 'create', '--cwd', $HOME, '--focus')
        if ($env:HERDR_ACTIVE_WORKSPACE_ID) { $arguments += @('--workspace', $env:HERDR_ACTIVE_WORKSPACE_ID) }
        $newPane = (Invoke-Herdr $arguments).root_pane.pane_id
    } else {
        $newPane = (Invoke-Herdr @('pane', 'split', '--pane', $pane, '--direction', 'right', '--cwd', $HOME, '--focus')).pane.pane_id
    }
    $quote = { param($text) "'" + $text.Replace("'", "''") + "'" }
    # Windows 的 pane cwd 來自 prompt 送出的 OSC 9;9; yazi 在同一行啟動, prompt 不會重畫, 因此先自行送出, 讓卸載能偵測到這個 pane
    $command = 'Set-Location -LiteralPath ' + (& $quote $Root) + '; if ($?) { [Console]::Write([char]27 + '']9;9;'' + $PWD.ProviderPath + [char]27 + ''\''); & ' + (& $quote $yazi) + '; if ($? -and $LASTEXITCODE -eq 0) { exit } }'
    # Yazi 在 Windows 需要 file.exe 判斷 MIME; herdr server 的環境可能沒有 YAZI_FILE_ONE, 改用 Git for Windows 內附的 file.exe
    $file = Join-Path $env:ProgramFiles 'Git\usr\bin\file.exe'
    if (!$env:YAZI_FILE_ONE -and (Test-Path $file)) { $command = '$env:YAZI_FILE_ONE = ' + (& $quote $file) + '; ' + $command }
    $output = & $binary pane run $newPane $command 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
}
function Open-Browser {
    $hostName = Get-SshHost
    if (!$hostName) {
        $cwd = ((Invoke-Herdr @('pane', 'list')).panes | Where-Object { $_.pane_id -eq $pane } | Select-Object -First 1).cwd
        if (!$cwd) { $cwd = $HOME }
        Open-Yazi $cwd
        return
    }
    Clear-Popup
    [Console]::Write("host: $hostName`r`n")
    $unc = '\\sshfs.kr\' + $hostName
    $existing = Get-HostMapping $hostName
    if ($existing -and $existing.Remote -ne $unc) {
        if (!(Confirm-Popup "$($existing.Drive) 為舊式掛載 ($($existing.Remote)); Enter 卸載並改掛 $unc")) { return }
        Clear-Popup
        [Console]::Write("host: $hostName`r`n卸載舊式掛載 ...`r`n")
        Invoke-SshfsMount @('-Unmount', $existing.Drive)
        $existing = $null
    }
    if ($existing) {
        # 已掛載: 不詢問, 開上次的路徑, 否則 -DefaultPath, 都不存在則開遠端 /
        foreach ($path in @((Get-State).$hostName, $DefaultPath)) {
            if ($path -and $path.StartsWith('/') -and (Test-Path -LiteralPath (Get-DrivePath $existing.Drive $path) -PathType Container)) {
                Open-Yazi (Get-DrivePath $existing.Drive $path)
                return
            }
        }
        Open-Yazi ($existing.Drive + '\')
        return
    }
    $default = ''
    if ($DefaultPath) {
        [Console]::Write("檢查遠端 $DefaultPath ...`r`n")
        $default = Resolve-Remote $hostName $DefaultPath
        if (!$default) { $default = '' }
    }
    while ($true) {
        $label = if ($default) { $default } else { '遠端 home' }
        $path = Read-Line "RemotePath [$label]: "
        if ($null -eq $path) { return }
        $path = $path.Trim()
        if (!$path) { $path = $default }
        $resolved = Resolve-Remote $hostName $path
        if ($resolved) { break }
        $shown = if ($path) { $path } else { '遠端 home' }
        [Console]::Write("遠端不存在或無法連線: $shown`r`n")
    }
    [Console]::Write("掛載中 ...`r`n")
    Invoke-SshfsMount @($hostName)
    $mapping = Get-HostMapping $hostName
    if (!$mapping) { throw "掛載後找不到 $unc 的磁碟機代號" }
    Save-LastPath $hostName $resolved
    Open-Yazi (Get-DrivePath $mapping.Drive $resolved)
}
function Invoke-Unmount {
    $items = @(Get-SshfsMappings)
    if (!$items.Count) {
        Clear-Popup
        [Console]::Write("沒有 sshfs 掛載`r`n按 Esc 或 Enter 關閉。")
        do { $key = [Console]::ReadKey($true) } while ($key.Key -ne 'Escape' -and $key.Key -ne 'Enter')
        return
    }
    $labels = @($items | ForEach-Object { '{0}  {1}' -f $_.Drive, $_.Remote })
    $choice = Select-Item $labels '卸載 SSHFS'
    if ($null -eq $choice) { return }
    $drive = $items[$choice - 1].Drive
    $busy = @()
    try { $busy = @((Invoke-Herdr @('pane', 'list')).panes | Where-Object { $_.cwd -and $_.cwd.ToUpper().StartsWith($drive) } | ForEach-Object { $_.pane_id }) } catch {}
    if ($busy.Count -and !(Confirm-Popup "有 $($busy.Count) 個 pane 的 cwd 在 $drive 內: $($busy -join ', '); 仍要卸載?")) { return }
    Invoke-SshfsMount @('-Unmount', $drive)
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane) { throw 'Missing Herdr popup context.' }
    if ($Mode -eq 'unmount') { Invoke-Unmount } else { Open-Browser }
} catch {
    Clear-Popup
    [Console]::WriteLine((Fit-Line ("失敗： $_") (Get-Width)))
    [Console]::Write('按 Esc 或 Enter 關閉。')
    do { $key = [Console]::ReadKey($true) } while ($key.Key -ne 'Escape' -and $key.Key -ne 'Enter')
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
