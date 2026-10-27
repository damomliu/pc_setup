# Popup menu; all IDs are captured before the first CLI request.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$binary = $env:HERDR_BIN_PATH
$pane = $env:HERDR_ACTIVE_PANE_ID
$workspace = $env:HERDR_ACTIVE_WORKSPACE_ID
$tab = $env:HERDR_ACTIVE_TAB_ID
function Invoke-Herdr {
    param([string[]]$Arguments)
    $output = & $binary @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
    $data = ($output -join "`n") | ConvertFrom-Json
    if ($data.error) { throw ($data.error | ConvertTo-Json -Compress) }
    if ($data.result.move_result -and !$data.result.move_result.changed) {
        throw ('Pane was not moved: ' + $data.result.move_result.reason)
    }
    return $data.result
}
$esc = [char]27
$savedControlC = [Console]::TreatControlCAsInput
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
function Select-Destination {
    param([string[]]$Labels)
    $selected = 0; $digits = ''; $message = ''
    while ($true) {
        $width = [Math]::Max(1, [Console]::WindowWidth - 1)
        $height = [Math]::Max(1, [Console]::WindowHeight)
        $rows = [Math]::Max(1, $height - 3)
        $start = [Math]::Max(0, [Math]::Min($selected - $rows + 1, $Labels.Count - $rows))
        $lines = New-Object 'Collections.Generic.List[string]'
        $lines.Add((Fit-Line '移動 pane 至 tab ↑↓ / 數字 / Enter / Esc Q' $width))
        for ($index = $start; $index -lt [Math]::Min($Labels.Count, $start + $rows); $index++) {
            $line = Fit-Line ('{0}. {1}' -f ($index + 1), $Labels[$index]) $width
            if ($index -eq $selected) { $line = $esc + '[7m' + $line + $esc + '[0m' }
            $lines.Add($line)
        }
        $footer = 'Enter 確認；Esc / Q 取消'
        if ($digits) { $footer = '編號：' + $digits }
        if ($message) { $footer = $message }
        $lines.Add((Fit-Line $footer $width))
        if ($height -lt 3) { $lines.RemoveAt(0) }
        [Console]::Write($esc + '[H' + $esc + '[2J' + (($lines | Select-Object -First $height) -join "`r`n"))
        while (![Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            if ([Math]::Max(1, [Console]::WindowWidth - 1) -ne $width -or [Math]::Max(1, [Console]::WindowHeight) -ne $height) { break }
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
function Get-Tabs {
    return (Invoke-Herdr @('tab', 'list', '--workspace', $workspace)).tabs
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane -or !$workspace -or !$tab) { throw 'Missing Herdr popup context.' }
    $destinations = @(Get-Tabs | Where-Object { $_.tab_id -ne $tab -and $_.workspace_id -eq $workspace } | Sort-Object number)
    $labels = @('新增 tab') + @($destinations | ForEach-Object { 'Tab {0}: {1}' -f $_.number, $_.label })
    $choice = Select-Destination $labels
    if ($null -eq $choice) { return }
    $source = (Invoke-Herdr @('pane', 'get', $pane)).pane
    if ($source.pane_id -ne $pane -or $source.workspace_id -ne $workspace -or $source.tab_id -ne $tab) {
        throw 'Source pane moved or no longer exists; reopen the menu.'
    }
    $live = @(Get-Tabs)
    if (!($live | Where-Object { $_.tab_id -eq $tab -and $_.workspace_id -eq $workspace })) { throw 'Source tab no longer exists; reopen the menu.' }
    if ($choice -eq 1) {
        $null = Invoke-Herdr @('pane', 'move', $pane, '--new-tab', '--focus')
    } else {
        $target = $destinations[$choice - 2].tab_id
        if (!($live | Where-Object { $_.tab_id -eq $target -and $_.workspace_id -eq $workspace })) { throw 'Destination tab no longer exists; reopen the menu.' }
        $null = Invoke-Herdr @('pane', 'move', $pane, '--tab', $target, '--split', 'right', '--focus')
    }
} catch {
    [Console]::Write($esc + '[H' + $esc + '[2J')
    [Console]::WriteLine((Fit-Line ("移動失敗： $_") ([Math]::Max(1, [Console]::WindowWidth - 1))))
    [Console]::Write('按 Esc 或 Enter 關閉。')
    do { $key = [Console]::ReadKey($true) } while ($key.Key -ne 'Escape' -and $key.Key -ne 'Enter')
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
