# Popup 顯示目前 tab 與 pane 的 ID, 用方向鍵選取並複製。
# 若 server 跑在 Session 0（經 sshd 啟動，例如 remote 連線），無法寫入桌面剪貼簿，改由 scheduled task herdr-clipboard 寫入。
# 注意：必須存成 UTF-8 with BOM，否則 Windows PowerShell 5.1 會以 cp950 解析而壞掉。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$binary = $env:HERDR_BIN_PATH
$pane = $env:HERDR_ACTIVE_PANE_ID
$popupTitle = 'Pane 總覽'
$esc = [char]27
$yellowBold = $esc + '[1;93m'
$reset = $esc + '[0m'
$copied = '(已複製)'
$copyFailed = '(複製失敗)'
$directions = @{ UpArrow = 'up'; DownArrow = 'down'; LeftArrow = 'left'; RightArrow = 'right' }
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
function Get-Width {
    param([string]$Element)
    $code = [char]::ConvertToUtf32($Element, 0)
    if (($code -ge 0x1100 -and $code -le 0x115f) -or ($code -ge 0x2e80 -and $code -le 0xa4cf) -or ($code -ge 0xac00 -and $code -le 0xd7a3) -or ($code -ge 0xf900 -and $code -le 0xfaff) -or ($code -ge 0xfe10 -and $code -le 0xfe6f) -or ($code -ge 0xff01 -and $code -le 0xff60) -or ($code -ge 0xffe0 -and $code -le 0xffe6) -or $code -ge 0x1f000) { return 2 }
    return 1
}
function Fit-Line {
    param([string]$Text, [int]$Width)
    $Text = [regex]::Replace($Text, '[\x00-\x1f\x7f-\x9f]', ' ')
    $builder = New-Object Text.StringBuilder
    $used = 0
    $elements = [Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($elements.MoveNext()) {
        $element = $elements.GetTextElement()
        $size = Get-Width $element
        if ($used + $size -gt $Width) { break }
        $null = $builder.Append($element)
        $used += $size
    }
    return $builder.ToString()
}
function Get-Layout {
    return (Invoke-Herdr @('pane', 'layout', '--pane', $pane)).layout
}
# 讓互動 session 的 task 依序寫入 ID, 並確認結果。
function Copy-Id {
    param([string]$Text)
    try {
        if ([Diagnostics.Process]::GetCurrentProcess().SessionId -ne 0) {
            Set-Clipboard -Value $Text
        } else {
            $scheduler = New-Object -ComObject 'Schedule.Service'
            $scheduler.Connect()
            $task = $scheduler.GetFolder('\').GetTask('herdr-clipboard')
            $timer = [Diagnostics.Stopwatch]::StartNew()
            Wait-ClipboardTask $task $timer
            [IO.File]::WriteAllText((Join-Path $env:APPDATA 'herdr\clipboard.txt'), $Text)
            $instance = $task.Run($null)
            if (!$instance) { throw 'herdr-clipboard did not start' }
            Wait-ClipboardTask $task $timer
            if ($task.LastTaskResult -ne 0) { throw 'herdr-clipboard failed' }
        }
        return $copied
    } catch {
        return $copyFailed
    }
}
function Wait-ClipboardTask {
    param($Task, [Diagnostics.Stopwatch]$Timer)
    while ($Task.State -in 2, 4 -or $Task.GetInstances(0).Count -gt 0) {
        if ($Timer.ElapsedMilliseconds -ge 5000) { throw 'herdr-clipboard timed out' }
        Start-Sleep -Milliseconds 50
    }
}
function Format-Note {
    param([string]$Note)
    if ($Note -eq $copied) { return $yellowBold + $Note + $reset }
    return $Note
}
function Render-Layout {
    param($Layout, [int]$Width, [int]$Height, [string]$Selected, [string]$Note = '', [string]$Message = '')
    $cols = [Math]::Max(1, $Width - 1)
    $rows = [Math]::Max(1, $Height - 6)
    $area = $Layout.area
    $areaW = [Math]::Max(1.0, [double]$area.width)
    $areaH = [Math]::Max(1.0, [double]$area.height)
    # 每格存一個字串；寬字元（中文）佔兩格，第二格為空字串
    $chars = New-Object 'string[][]' $rows
    for ($y = 0; $y -lt $rows; $y++) {
        $chars[$y] = [string[]]@(1..$cols | ForEach-Object { ' ' })
    }
    $statusInFooter = $false
    $tabLabel = 'Tab: ' + $Layout.tab_id
    $tabLine = Fit-Line $tabLabel $cols
    if ($Selected -eq $Layout.tab_id) {
        if ((Fit-Line ($tabLabel + $Note) $cols) -eq ($tabLabel + $Note)) {
            $tabLine += Format-Note $Note
        } else {
            $statusInFooter = $true
        }
    }
    foreach ($entry in $Layout.panes) {
        $rect = $entry.rect
        # 以相同公式縮放左右邊界，相鄰 pane 的邊界才會對齊
        $x0 = [int][Math]::Floor(($rect.x - $area.x) * $cols / $areaW + 0.5)
        $x1 = [int][Math]::Floor(($rect.x - $area.x + $rect.width) * $cols / $areaW + 0.5)
        $y0 = [int][Math]::Floor(($rect.y - $area.y) * $rows / $areaH + 0.5)
        $y1 = [int][Math]::Floor(($rect.y - $area.y + $rect.height) * $rows / $areaH + 0.5)
        $x0 = [Math]::Max(0, [Math]::Min($cols - 1, $x0)); $x1 = [Math]::Max(1, [Math]::Min($cols, $x1))
        $y0 = [Math]::Max(0, [Math]::Min($rows - 1, $y0)); $y1 = [Math]::Max(1, [Math]::Min($rows, $y1))
        if ($x1 -le $x0) { $x1 = $x0 + 1 }
        if ($y1 -le $y0) { $y1 = $y0 + 1 }
        $boxW = $x1 - $x0
        $boxH = $y1 - $y0
        if ($boxW -ge 3 -and $boxH -ge 3) {
            # 有內部空間：畫外框，ID 置於內部中央
            for ($x = $x0; $x -lt $x1; $x++) { $chars[$y0][$x] = '─'; $chars[$y1 - 1][$x] = '─' }
            for ($y = $y0; $y -lt $y1; $y++) { $chars[$y][$x0] = '│'; $chars[$y][$x1 - 1] = '│' }
            $chars[$y0][$x0] = '┌'; $chars[$y0][$x1 - 1] = '┐'
            $chars[$y1 - 1][$x0] = '└'; $chars[$y1 - 1][$x1 - 1] = '┘'
            $avail = $boxW - 2
            $labelRow = $y0 + [int][Math]::Floor($boxH / 2)
            $labelX = $x0 + 1
        } else {
            # 放不下外框：只顯示 ID
            $avail = $boxW
            $labelRow = $y0 + [int][Math]::Floor(($boxH - 1) / 2)
            $labelX = $x0
        }
        $paneId = [string]$entry.pane_id
        $text = Fit-Line $paneId $avail
        $suffix = ''
        if ($paneId -eq $Selected -and $Note) {
            if ((Fit-Line ($paneId + $Note) $avail) -eq ($paneId + $Note)) {
                $suffix = $Note
            } else {
                $statusInFooter = $true
            }
        }
        $cells = New-Object 'Collections.Generic.List[string]'
        foreach ($ch in ($text + $suffix).ToCharArray()) {
            $size = Get-Width ([string]$ch)
            $cells.Add([string]$ch)
            if ($size -eq 2) { $cells.Add('') }
        }
        if ($suffix -eq $copied) {
            $cells[$text.Length] = $yellowBold + $cells[$text.Length]
            $cells[$cells.Count - 1] += $reset
        }
        $start = $labelX + [int][Math]::Floor(($avail - $cells.Count) / 2)
        for ($i = 0; $i -lt $cells.Count; $i++) { $chars[$labelRow][$start + $i] = $cells[$i] }
    }
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add($tabLine)
    $lines.Add('')
    for ($y = 0; $y -lt $rows; $y++) {
        $lines.Add((-join $chars[$y]))
    }
    $footer = Fit-Line '方向鍵選取並複製 / 其他鍵關閉' $cols
    if ($Message) {
        $footer = Fit-Line $Message $cols
    } elseif ($statusInFooter) {
        $footer = Fit-Line $Selected $cols
        if ((Fit-Line ($Selected + $Note) $cols) -eq ($Selected + $Note)) {
            $footer += Format-Note $Note
        }
    }
    $lines.Add('')
    $lines.Add($footer)
    return $lines
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane) { throw 'Missing Herdr popup context.' }
    $layout = Get-Layout
    $tab = $layout.tab_id
    $selected = $lastPane = $pane
    $note = Copy-Id $pane
    $message = ''
    while ($true) {
        $width = [Console]::WindowWidth
        $height = [Console]::WindowHeight
        $lines = Render-Layout $layout $width $height $selected $note $message
        [Console]::Write((Get-PopupHeader) + (($lines | Select-Object -First ([Math]::Max(0, $height - 2))) -join "`r`n"))
        while (![Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            if ([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height) { break }
        }
        if (![Console]::KeyAvailable) { continue }
        $key = [Console]::ReadKey($true)
        $direction = $directions[[string]$key.Key]
        if (!$direction) { return }
        $target = $selected
        $message = ''
        if ($selected -eq $tab) {
            if ($direction -eq 'down') { $target = $lastPane }
        } else {
            try {
                $neighbor = (Invoke-Herdr @('pane', 'neighbor', '--pane', $selected, '--direction', $direction)).neighbor
                if ($neighbor.layout.tab_id -ne $tab) { throw 'The selected pane moved to another tab.' }
            } catch {
                $message = '無法讀取相鄰 pane'
                continue
            }
            $layout = $neighbor.layout
            if ($neighbor.neighbor_pane_id) {
                $target = $neighbor.neighbor_pane_id
            } elseif ($direction -eq 'up') {
                $target = $tab
            }
        }
        if ($target -ne $selected) {
            if ($target -ne $tab) { $lastPane = $target }
            $selected = $target
            $note = Copy-Id $selected
        }
    }
} catch {
    [Console]::Write((Get-PopupHeader))
    [Console]::WriteLine((Fit-Line ("讀取失敗： $_") ([Math]::Max(1, [Console]::WindowWidth - 1))))
    [Console]::Write('按任意鍵關閉。')
    $null = [Console]::ReadKey($true)
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
