param([ValidateSet('tab', 'workspace')][string]$Mode = 'tab')
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
$popupTitle = $(if ($Mode -eq 'workspace') { '移動 pane 至 workspace' } else { '移動 pane 至 tab' })
$esc = [char]27
$savedControlC = [Console]::TreatControlCAsInput
function Get-PopupHeader {
    return $esc + '[H' + $esc + '[2J' + $esc + '[1;96m' + (Fit-Line $popupTitle ([Math]::Max(1, [Console]::WindowWidth - 1))) + $esc + '[0m' + "`r`n`r`n"
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
function Select-Destination {
    param([string[]]$Labels, [int]$Current, [switch]$NewTab)
    $selected = $Current + [int]$NewTab.IsPresent
    $digits = ''; $message = ''
    $hint = if ($NewTab) { '↑↓ 選擇 / 數字, N, Enter 確認 / Esc 或 Q 取消' } else { '↑↓ 選擇 / 數字或 Enter 確認 / Esc 或 Q 取消' }
    $lastTab = $Labels.Count - 1
    $lastChoice = $lastTab + [int]$NewTab.IsPresent
    while ($true) {
        $width = [Math]::Max(1, [Console]::WindowWidth - 1)
        $height = [Math]::Max(1, [Console]::WindowHeight)
        $rows = [Math]::Max(1, $height - 5)
        $start = [Math]::Max(0, [Math]::Min([Math]::Min($selected, $lastTab) - $rows + 1, $Labels.Count - $rows))
        $lines = New-Object 'Collections.Generic.List[string]'
        for ($index = $start; $index -lt [Math]::Min($Labels.Count, $start + $rows); $index++) {
            $line = Fit-Line ('{0}. {1}' -f ($index + 1), $Labels[$index]) $width
            if ($index -eq $selected) { $line = $esc + '[7m' + $line + $esc + '[0m' }
            $lines.Add($line)
        }
        if ($NewTab) {
            $line = Fit-Line 'N. 新增 tab' $width
            if ($height -lt 5) { $lines.Clear() }
            if ($selected -eq $Labels.Count) { $line = $esc + '[7m' + $line + $esc + '[0m' }
            $lines.Add($line)
        }
        $footer = $hint
        if ($digits) { $footer = '編號：' + $digits }
        if ($message) { $footer = $message }
        if ($start -gt 0 -or $start + $rows -lt $Labels.Count -or ($NewTab -and $height -lt 5)) { $footer = '(more) ' + $footer }
        if ($height -ge (5 + [int]$NewTab.IsPresent)) { $lines.Add('') }
        $lines.Add((Fit-Line $footer $width))
        [Console]::Write((Get-PopupHeader) + (($lines | Select-Object -First ([Math]::Max(0, $height - 2))) -join "`r`n"))
        while (![Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            if ([Math]::Max(1, [Console]::WindowWidth - 1) -ne $width -or [Math]::Max(1, [Console]::WindowHeight) -ne $height) { break }
        }
        if (![Console]::KeyAvailable) { continue }
        $key = [Console]::ReadKey($true)
        $isDigit = $key.KeyChar -ge '0' -and $key.KeyChar -le '9'
        if ($key.Key -eq 'Escape' -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q' -or ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) { return $null }
        if ($NewTab -and ($key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N')) { return ($Labels.Count + 1) }
        if ($key.Key -eq 'UpArrow' -or $key.Key -eq 'DownArrow') {
            $digits = ''; $message = ''
            $step = 1
            if ($key.Key -eq 'UpArrow') { $step = -1 }
            $selected = [Math]::Max(0, [Math]::Min($lastChoice, $selected + $step))
        } elseif ($key.Key -eq 'Backspace') {
            if ($digits.Length) { $digits = $digits.Substring(0, $digits.Length - 1) }
            $message = ''
        } elseif ($isDigit) {
            if ($digits.Length -lt 100) { $digits += $key.KeyChar }
            $message = ''
        } elseif ($key.Key -eq 'Enter') {
            $number = 0
            if ($digits -and (!([int]::TryParse($digits, [ref]$number)) -or $number -lt 1 -or $number -gt $Labels.Count)) {
                $message = '無效選項，請修改編號或使用方向鍵。'
                continue
            }
            if ($selected -ne $Current) { return ($selected + 1) }
            $digits = ''; $message = ''
        }
        $number = 0
        if ($digits -and [int]::TryParse($digits, [ref]$number) -and $number -ge 1 -and $number -le $Labels.Count) {
            $selected = $number - 1
            if ($isDigit -and $number * 10L -gt $Labels.Count) {
                if ($selected -ne $Current) { return ($selected + 1) }
                $digits = ''
            }
        }
    }
}
function Get-WorkspaceRows {
    param([object[]]$Workspaces, [string]$CurrentId)
    $ordered = @($Workspaces | Sort-Object number)
    $parents = [Collections.Generic.Dictionary[string,string]]::new()
    foreach ($item in $ordered) {
        $worktree = $item.worktree
        if ($worktree.repo_key -and !$worktree.is_linked_worktree -and !$parents.ContainsKey($worktree.repo_key)) {
            $parents.Add($worktree.repo_key, $item.workspace_id)
        }
    }
    $roots = [Collections.Generic.List[object]]::new()
    $children = @{}
    foreach ($item in $ordered) {
        $worktree = $item.worktree
        if ($worktree.is_linked_worktree -and $worktree.repo_key -and $parents.ContainsKey($worktree.repo_key)) {
            $parent = $parents[$worktree.repo_key]
            if (!$children.ContainsKey($parent)) { $children[$parent] = [Collections.Generic.List[object]]::new() }
            $children[$parent].Add($item)
        } else {
            $roots.Add($item)
        }
    }
    foreach ($root in $roots) {
        $label = if ($root.workspace_id -ceq $CurrentId) { '(current)' } else { $root.label }
        [pscustomobject]@{ Id = $root.workspace_id; Label = $label }
        foreach ($child in $children[$root.workspace_id]) {
            $label = if ($child.workspace_id -ceq $CurrentId) { '(current)' } else { '> ' + $child.label }
            [pscustomobject]@{ Id = $child.workspace_id; Label = $label }
        }
    }
}
function Get-Tabs {
    return (Invoke-Herdr @('tab', 'list', '--workspace', $workspace)).tabs
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane -or !$workspace -or !$tab) { throw 'Missing Herdr popup context.' }
    if ($Mode -eq 'workspace') {
        $rows = @(Get-WorkspaceRows (Invoke-Herdr @('workspace', 'list')).workspaces $workspace)
        $current = [Array]::IndexOf(@($rows.Id), $workspace)
        if ($current -lt 0) { throw 'Source workspace no longer exists; reopen the menu.' }
        $choice = Select-Destination -Labels $rows.Label -Current $current
        if ($null -eq $choice) { return }
        $destinationWorkspace = $rows[$choice - 1].Id
    } else {
        $destinations = @(Get-Tabs | Where-Object { $_.workspace_id -eq $workspace } | Sort-Object number)
        $current = [Array]::IndexOf(@($destinations.tab_id), $tab)
        if ($current -lt 0) { throw 'Source tab no longer exists; reopen the menu.' }
        $labels = @($destinations | ForEach-Object {
            if ($_.tab_id -ceq $tab) { '(current)' }
            else { $_.label -creplace '^[0-9]+[ \t]+·[ \t]+(?:[◉◐●✓○][ \t]+)?(?=\S)', '' }
        })
        $choice = Select-Destination -Labels $labels -Current $current -NewTab
        if ($null -eq $choice) { return }
    }
    $source = (Invoke-Herdr @('pane', 'get', $pane)).pane
    if ($source.pane_id -ne $pane -or $source.workspace_id -ne $workspace -or $source.tab_id -ne $tab) {
        throw 'Source pane moved or no longer exists; reopen the menu.'
    }
    $live = @(Get-Tabs)
    if (!($live | Where-Object { $_.tab_id -eq $tab -and $_.workspace_id -eq $workspace })) { throw 'Source tab no longer exists; reopen the menu.' }
    if ($Mode -eq 'workspace') {
        $target = (Invoke-Herdr @('workspace', 'get', $destinationWorkspace)).workspace.active_tab_id
        if (!$target -or (Invoke-Herdr @('tab', 'get', $target)).tab.workspace_id -cne $destinationWorkspace) {
            throw 'Destination active tab no longer exists; reopen the menu.'
        }
        $null = Invoke-Herdr @('pane', 'move', $pane, '--tab', $target, '--split', 'right', '--focus')
        return
    }
    if ($choice -eq ($destinations.Count + 1)) {
        $null = Invoke-Herdr @('pane', 'move', $pane, '--new-tab', '--workspace', $workspace, '--focus')
    } else {
        $target = $destinations[$choice - 1].tab_id
        if (!($live | Where-Object { $_.tab_id -eq $target -and $_.workspace_id -eq $workspace })) { throw 'Destination tab no longer exists; reopen the menu.' }
        $null = Invoke-Herdr @('pane', 'move', $pane, '--tab', $target, '--split', 'right', '--focus')
    }
} catch {
    [Console]::Write((Get-PopupHeader))
    [Console]::WriteLine((Fit-Line ("移動失敗： $_") ([Math]::Max(1, [Console]::WindowWidth - 1))))
    [Console]::Write('按 Esc 或 Enter 關閉。')
    do { $key = [Console]::ReadKey($true) } while ($key.Key -ne 'Escape' -and $key.Key -ne 'Enter')
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
