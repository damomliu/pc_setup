# Popup 顯示目前 tab 的 ID，並依版面畫出所有 pane 的 ID；目前 pane 以高亮底色顯示，並自動複製其 ID。
# 注意：必須存成 UTF-8 with BOM，否則 Windows PowerShell 5.1 會以 cp950 解析而壞掉。
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$binary = $env:HERDR_BIN_PATH
$pane = $env:HERDR_ACTIVE_PANE_ID
$esc = [char]27
# 目前 pane 的底色：one-dark 選取列風格，淺灰底 #3e4451 + 白色粗體字，要換色只改這裡
$highlight = $esc + '[1;38;2;255;255;255;48;2;62;68;81m'
$savedControlC = [Console]::TreatControlCAsInput
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
# 回傳整個畫面的行：標題、空行、(Width-1) x (Height-4) 的版面、空行、footer。
# 版面僅含 ASCII（+ - |），每格寬度固定為 1；目前 pane 的整個矩形（含外框）包上藍底白字。
function Render-Layout {
    param($Layout, [int]$Width, [int]$Height, [string]$Active, [string]$Note = '')
    $cols = [Math]::Max(1, $Width - 1)
    $rows = [Math]::Max(1, $Height - 4)
    $area = $Layout.area
    $areaW = [Math]::Max(1.0, [double]$area.width)
    $areaH = [Math]::Max(1.0, [double]$area.height)
    # 每格存一個字串；寬字元（中文）佔兩格，第二格為空字串
    $chars = New-Object 'string[][]' $rows
    $flags = New-Object 'bool[][]' $rows
    for ($y = 0; $y -lt $rows; $y++) {
        $chars[$y] = [string[]]@(1..$cols | ForEach-Object { ' ' })
        $flags[$y] = New-Object 'bool[]' $cols
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
        $isActive = ($entry.pane_id -eq $Active)
        for ($y = $y0; $y -lt $y1; $y++) {
            for ($x = $x0; $x -lt $x1; $x++) { $flags[$y][$x] = $isActive }
        }
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
        $text = [string]$entry.pane_id
        if ($isActive -and $Note) { $text += ' ' + $Note }
        $cells = New-Object 'Collections.Generic.List[string]'
        foreach ($ch in $text.ToCharArray()) {
            $size = Get-Width ([string]$ch)
            if ($cells.Count + $size -gt $avail) { break }
            $cells.Add([string]$ch)
            if ($size -eq 2) { $cells.Add('') }
        }
        $start = $labelX + [int][Math]::Floor(($avail - $cells.Count) / 2)
        for ($i = 0; $i -lt $cells.Count; $i++) { $chars[$labelRow][$start + $i] = $cells[$i] }
    }
    $reset = $esc + '[0m'
    $lines = New-Object 'Collections.Generic.List[string]'
    $lines.Add(('Tab: ' + $Layout.tab_id + $reset))
    $lines.Add($reset)
    for ($y = 0; $y -lt $rows; $y++) {
        $builder = New-Object Text.StringBuilder
        $inRun = $false
        for ($x = 0; $x -lt $cols; $x++) {
            if ($flags[$y][$x] -ne $inRun) {
                if ($flags[$y][$x]) { $null = $builder.Append($highlight) } else { $null = $builder.Append($reset) }
                $inRun = $flags[$y][$x]
            }
            $null = $builder.Append($chars[$y][$x])
        }
        $null = $builder.Append($reset)
        $lines.Add($builder.ToString())
    }
    $lines.Add($reset)
    $lines.Add((Fit-Line '按任意鍵關閉...' $cols) + $reset)
    return $lines
}
try {
    [Console]::TreatControlCAsInput = $true
    [Console]::Write($esc + '[?1049h' + $esc + '[?25l')
    if (!$binary -or !$pane) { throw 'Missing Herdr popup context.' }
    $layout = Get-Layout
    try {
        Set-Clipboard -Value $pane
        $note = '(已複製)'
    } catch {
        $note = '(複製失敗)'
    }
    while ($true) {
        $width = [Console]::WindowWidth
        $height = [Console]::WindowHeight
        $lines = Render-Layout $layout $width $height $pane $note
        [Console]::Write($esc + '[H' + $esc + '[2J' + (($lines | Select-Object -First ([Math]::Max(1, $height))) -join "`r`n"))
        while (![Console]::KeyAvailable) {
            Start-Sleep -Milliseconds 50
            if ([Console]::WindowWidth -ne $width -or [Console]::WindowHeight -ne $height) { break }
        }
        if ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true); return }
    }
} catch {
    [Console]::Write($esc + '[H' + $esc + '[2J')
    [Console]::WriteLine((Fit-Line ("讀取失敗： $_") ([Math]::Max(1, [Console]::WindowWidth - 1))))
    [Console]::Write('按任意鍵關閉。')
    $null = [Console]::ReadKey($true)
    exit 1
} finally {
    [Console]::Write($esc + '[0m' + $esc + '[?25h' + $esc + '[?1049l')
    [Console]::TreatControlCAsInput = $savedControlC
}
