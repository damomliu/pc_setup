<#
Set-RgbMode.ps1
用法:
  Set-RgbMode.ps1          互動選單；切換成功後清畫面，Enter 才離開
  Set-RgbMode.ps1 off      直接關燈後結束
  Set-RgbMode.ps1 on       直接切到日常靜態暖白後結束
  Set-RgbMode.ps1 dim      直接切到低亮度琥珀後結束
  Set-RgbMode.ps1 idle     直接切到青色呼吸後結束
  Set-RgbMode.ps1 cycle    直接切到循環後結束
  Set-RgbMode.ps1 wave     直接切到彩虹波浪後結束
  -DebugLog $false         關閉 debug log（預設開啟，寫到 %LOCALAPPDATA%\pc-setup\rgb-debug.log）
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('off', 'on', 'dim', 'idle', 'cycle', 'wave')]
    [string]$Name,

    [bool]$DebugLog = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$catalog = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'modes.psd1')
$openRgb = Join-Path $env:LOCALAPPDATA 'OpenRGB\OpenRGB Windows 64-bit\OpenRGB.exe'
$stateFile = Join-Path $env:LOCALAPPDATA 'pc-setup\rgb-mode.txt'
$debugFile = Join-Path $env:LOCALAPPDATA 'pc-setup\rgb-debug.log'
$serverPort = 6742
$protocolVersion = 4

function Write-RgbDebug {
    param([Parameter(Mandatory)][string]$Message)
    if (-not $DebugLog) {
        return
    }
    $folder = Split-Path -Parent $debugFile
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Add-Content -LiteralPath $debugFile -Value $line -Encoding utf8
}

function Clear-RgbWindow {
    try {
        Clear-Host
    }
    catch {
        Write-RgbDebug "清畫面失敗：$($_.Exception.Message)"
    }
}

function Read-ExactBytes {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][int]$Count
    )
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($read -le 0) {
            throw 'OpenRGB 連線中斷'
        }
        $offset += $read
    }
    return $buffer
}

function Send-OrgbPacket {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][uint32]$Device,
        [Parameter(Mandatory)][uint32]$PacketId,
        [byte[]]$Payload = [byte[]]@()
    )
    $header = New-Object byte[] 16
    [Text.Encoding]::ASCII.GetBytes('ORGB').CopyTo($header, 0)
    [BitConverter]::GetBytes($Device).CopyTo($header, 4)
    [BitConverter]::GetBytes($PacketId).CopyTo($header, 8)
    [BitConverter]::GetBytes([uint32]$Payload.Length).CopyTo($header, 12)
    $Stream.Write($header, 0, 16)
    if ($Payload.Length -gt 0) {
        $Stream.Write($Payload, 0, $Payload.Length)
    }
}

function Read-OrgbPacket {
    param([Parameter(Mandatory)]$Stream)
    $header = Read-ExactBytes -Stream $Stream -Count 16
    $magic = [Text.Encoding]::ASCII.GetString($header, 0, 4)
    if ($magic -ne 'ORGB') {
        throw "OpenRGB 回應格式不對：$magic"
    }
    $size = [BitConverter]::ToUInt32($header, 12)
    $data = if ($size -gt 0) { Read-ExactBytes -Stream $Stream -Count $size } else { [byte[]]@() }
    return [pscustomobject]@{
        Id = [BitConverter]::ToUInt32($header, 8)
        Data = $data
    }
}

function Read-OrgbString {
    param(
        [byte[]]$Data,
        [ref]$Index
    )
    $length = [BitConverter]::ToUInt16($Data, $Index.Value)
    $Index.Value += 2
    $text = [Text.Encoding]::UTF8.GetString($Data, $Index.Value, $length)
    $Index.Value += $length
    $nul = $text.IndexOf([char]0)
    if ($nul -ge 0) {
        return $text.Substring(0, $nul)
    }
    return $text
}

function Get-OrgbModes {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][uint32]$Device
    )
    Send-OrgbPacket -Stream $Stream -Device $Device -PacketId 1 -Payload ([BitConverter]::GetBytes([uint32]$protocolVersion))
    $packet = Read-OrgbPacket -Stream $Stream
    while ($packet.Id -eq 100) {
        $packet = Read-OrgbPacket -Stream $Stream
    }
    if ($packet.Id -ne 1) {
        throw "OpenRGB 沒有回傳裝置資料（封包 $($packet.Id)）"
    }

    $index = 4
    [void][BitConverter]::ToInt32($packet.Data, $index)
    $index += 4
    $deviceName = Read-OrgbString -Data $packet.Data -Index ([ref]$index)
    foreach ($unused in 1..5) {
        [void](Read-OrgbString -Data $packet.Data -Index ([ref]$index))
    }
    $modeCount = [BitConverter]::ToUInt16($packet.Data, $index)
    $index += 2
    $active = [BitConverter]::ToInt32($packet.Data, $index)
    $index += 4

    $modes = @()
    for ($modeIndex = 0; $modeIndex -lt $modeCount; $modeIndex++) {
        $modeName = Read-OrgbString -Data $packet.Data -Index ([ref]$index)
        $value = [BitConverter]::ToInt32($packet.Data, $index)
        $index += 4
        $flags = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $speedMin = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $speedMax = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $brightnessMin = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $brightnessMax = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $colorsMin = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $colorsMax = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $speed = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $brightness = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $direction = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $colorMode = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $colorCount = [BitConverter]::ToUInt16($packet.Data, $index)
        $index += 2
        $colors = @()
        for ($colorIndex = 0; $colorIndex -lt $colorCount; $colorIndex++) {
            $colors += ,$packet.Data[$index..($index + 2)]
            $index += 4
        }
        $modes += [pscustomobject]@{
            Id = $modeIndex
            Name = $modeName
            Value = $value
            Flags = $flags
            SpeedMin = $speedMin
            SpeedMax = $speedMax
            BrightnessMin = $brightnessMin
            BrightnessMax = $brightnessMax
            ColorsMin = $colorsMin
            ColorsMax = $colorsMax
            Speed = $speed
            Brightness = $brightness
            Direction = $direction
            ColorMode = $colorMode
            Colors = $colors
        }
    }

    $zoneCount = [BitConverter]::ToUInt16($packet.Data, $index)
    $index += 2
    $zones = @()
    for ($zoneIndex = 0; $zoneIndex -lt $zoneCount; $zoneIndex++) {
        $zoneName = Read-OrgbString -Data $packet.Data -Index ([ref]$index)
        $index += 4
        $index += 4
        $index += 4
        $ledCount = [BitConverter]::ToUInt32($packet.Data, $index)
        $index += 4
        $matrixLength = [BitConverter]::ToUInt16($packet.Data, $index)
        $index += 2
        if ($matrixLength -gt 0) {
            $index += 8 + (4 * $matrixLength)
        }
        $segmentCount = [BitConverter]::ToUInt16($packet.Data, $index)
        $index += 2
        for ($segmentIndex = 0; $segmentIndex -lt $segmentCount; $segmentIndex++) {
            [void](Read-OrgbString -Data $packet.Data -Index ([ref]$index))
            $index += 12
        }
        $zones += [pscustomobject]@{
            Index = $zoneIndex
            Name = $zoneName
            Count = $ledCount
        }
    }

    return [pscustomobject]@{
        Name = $deviceName
        Active = $active
        Modes = $modes
        Zones = $zones
    }
}

function Send-RgbResize {
    param(
        [Parameter(Mandatory)]$Stream,
        [Parameter(Mandatory)][uint32]$Device,
        [Parameter(Mandatory)][int]$Zone,
        [Parameter(Mandatory)][int]$Size
    )
    $payload = New-Object byte[] 8
    [BitConverter]::GetBytes([int32]$Zone).CopyTo($payload, 0)
    [BitConverter]::GetBytes([int32]$Size).CopyTo($payload, 4)
    Send-OrgbPacket -Stream $Stream -Device $Device -PacketId 1000 -Payload $payload
}

function Wait-RgbDetection {
    param([Parameter(Mandatory)][datetime]$StartedAt)
    $deadline = (Get-Date).AddSeconds(20)
    $logFolder = Join-Path $env:APPDATA 'OpenRGB\logs'
    do {
        $candidate = Get-ChildItem -LiteralPath $logFolder -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate -and $candidate.LastWriteTime -ge $StartedAt.AddSeconds(-1)) {
            $text = Get-Content -LiteralPath $candidate.FullName -Raw -ErrorAction SilentlyContinue
            if ($text -and $text.Contains('Detection completed')) {
                return $candidate.FullName
            }
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw 'OpenRGB 燈控初始化逾時'
}

function Get-PackedString {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Text)
    $packed = New-Object System.Collections.Generic.List[byte]
    $packed.AddRange([BitConverter]::GetBytes([uint16]($bytes.Length + 1)))
    $packed.AddRange($bytes)
    $packed.Add(0)
    return ,$packed.ToArray()
}

function Get-ModePayload {
    param(
        [Parameter(Mandatory)]$Mode,
        [Parameter(Mandatory)][uint32]$Brightness,
        [Parameter(Mandatory)][uint32]$Speed,
        [Parameter(Mandatory)][uint32]$ColorMode,
        [byte[]]$ColorBytes
    )
    if ($null -eq $ColorBytes) {
        $ColorBytes = [byte[]]@()
    }
    $body = New-Object System.Collections.Generic.List[byte]
    $body.AddRange([BitConverter]::GetBytes([int32]$Mode.Id))
    $body.AddRange((Get-PackedString -Text $Mode.Name))
    $body.AddRange([BitConverter]::GetBytes([int32]$Mode.Value))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.Flags))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.SpeedMin))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.SpeedMax))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.BrightnessMin))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.BrightnessMax))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.ColorsMin))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.ColorsMax))
    $body.AddRange([BitConverter]::GetBytes($Speed))
    $body.AddRange([BitConverter]::GetBytes($Brightness))
    $body.AddRange([BitConverter]::GetBytes([uint32]$Mode.Direction))
    $body.AddRange([BitConverter]::GetBytes($ColorMode))
    $colorCount = [int]($ColorBytes.Length / 3)
    $body.AddRange([BitConverter]::GetBytes([uint16]$colorCount))
    for ($colorIndex = 0; $colorIndex -lt $ColorBytes.Length; $colorIndex += 3) {
        $body.AddRange([byte[]]@(
            $ColorBytes[$colorIndex],
            $ColorBytes[$colorIndex + 1],
            $ColorBytes[$colorIndex + 2],
            0
        ))
    }
    $payload = New-Object System.Collections.Generic.List[byte]
    $payload.AddRange([BitConverter]::GetBytes([uint32]($body.Count + 4)))
    $payload.AddRange($body)
    return ,$payload.ToArray()
}

function Connect-Orgb {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect('127.0.0.1', $serverPort)
    $stream = $client.GetStream()
    $stream.ReadTimeout = 8000
    $stream.WriteTimeout = 8000
    $nameBytes = [Text.Encoding]::ASCII.GetBytes("pc-setup`0")
    Send-OrgbPacket -Stream $stream -Device 0 -PacketId 50 -Payload $nameBytes
    Send-OrgbPacket -Stream $stream -Device 0 -PacketId 40 -Payload ([BitConverter]::GetBytes([uint32]$protocolVersion))
    $hello = Read-OrgbPacket -Stream $stream
    if ($hello.Id -ne 40) {
        throw "OpenRGB 沒有完成連線（封包 $($hello.Id)）"
    }
    return [pscustomobject]@{
        Client = $client
        Stream = $stream
    }
}

function Get-Board {
    param([Parameter(Mandatory)]$Stream)
    $count = 0
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        Send-OrgbPacket -Stream $Stream -Device 0 -PacketId 0
        $packet = Read-OrgbPacket -Stream $Stream
        while ($packet.Id -eq 100) {
            $packet = Read-OrgbPacket -Stream $Stream
        }
        if ($packet.Id -eq 0 -and $packet.Data.Length -ge 4) {
            $count = [BitConverter]::ToUInt32($packet.Data, 0)
            if ($count -gt 0) {
                break
            }
        }
        Start-Sleep -Milliseconds 400
    }
    if ($count -lt 1) {
        throw 'OpenRGB 沒有找到燈光裝置'
    }

    for ($device = 0; $device -lt $count; $device++) {
        $info = Get-OrgbModes -Stream $Stream -Device ([uint32]$device)
        if ($info.Name -eq $catalog.Device) {
            $info | Add-Member -NotePropertyName Index -NotePropertyValue $device
            return $info
        }
    }
    throw "OpenRGB 沒有找到 $($catalog.Device)"
}

function Get-SavedRgbMode {
    if (-not (Test-Path -LiteralPath $stateFile)) {
        return $null
    }
    $saved = (Get-Content -LiteralPath $stateFile -Raw).Trim()
    if ($catalog.Order -contains $saved) {
        return $saved
    }
    return $null
}

function Save-RgbMode {
    param([Parameter(Mandatory)][string]$ModeName)
    $folder = Split-Path -Parent $stateFile
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }
    Set-Content -LiteralPath $stateFile -Value $ModeName -Encoding utf8
}

function Resolve-RgbChoice {
    param([Parameter(Mandatory)][string]$Choice)
    $text = $Choice.Trim()
    if ($text -match '^\d+$') {
        $index = [int]$text
        if ($index -ge 1 -and $index -le $catalog.Order.Count) {
            return [string]$catalog.Order[$index - 1]
        }
        return $null
    }
    foreach ($modeName in $catalog.Order) {
        if ($modeName -ieq $text) {
            return $modeName
        }
    }
    return $null
}

function Show-RgbMenu {
    Write-Host ''
    Write-Host '=== RGB 模式 ===' -ForegroundColor Cyan
    $current = Get-SavedRgbMode
    if ($current) {
        Write-Host "目前：$current" -ForegroundColor Green
    }
    else {
        Write-Host '目前：尚未用這個選單設定' -ForegroundColor Yellow
    }

    if ($DebugLog) {
        Write-Host "debug：$debugFile" -ForegroundColor DarkGray
    }

    Write-Host ''
    $index = 1
    foreach ($modeName in $catalog.Order) {
        $mode = $catalog.Modes.$modeName
        Write-Host ("  {0}  {1,-6} {2}" -f $index, $modeName, $mode.Summary)
        $index++
    }
}

function Invoke-RgbMode {
    param([Parameter(Mandatory)][string]$ModeName)

    if (-not (Test-Path -LiteralPath $openRgb)) {
        throw "找不到 OpenRGB：$openRgb"
    }

    $running = Get-Process -Name OpenRGB -ErrorAction SilentlyContinue
    if ($running) {
        throw "OpenRGB 正在執行（PID $($running.Id -join ', ')）。先關掉再切換，避免搶同一個燈光裝置。"
    }

    $modeSpec = $catalog.Modes.$ModeName
    $colorNote = if ($modeSpec.Contains('Color')) { $modeSpec.Color } else { 'none' }
    Write-RgbDebug "開始 $ModeName mode=$($modeSpec.Mode) color=$colorNote brightness=$($modeSpec.Brightness)%"
    $startedAt = Get-Date
    $server = Start-Process -FilePath $openRgb -ArgumentList @(
        '--server'
        '--server-port', "$serverPort"
        '--noautoconnect'
    ) -PassThru -WindowStyle Hidden

    try {
        $listening = $false
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            if ($server.HasExited) {
                throw "OpenRGB 提前結束，代碼 $($server.ExitCode)"
            }
            $listener = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue
            if ($listener) {
                $listening = $true
                break
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $listening) {
            throw 'OpenRGB 沒有開始接受連線'
        }
        $openRgbLog = Wait-RgbDetection -StartedAt $startedAt
        Write-RgbDebug "初始化完成 $openRgbLog"

        $session = Connect-Orgb
        try {
            $board = Get-Board -Stream $session.Stream
            $before = (@($board.Zones) | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '
            Write-RgbDebug "燈區 $before"
            $headerSize = [int]$catalog.ArgbLedCount
            foreach ($zone in @($board.Zones)) {
                if ($zone.Name -like 'ARGB*' -and [int]$zone.Count -ne $headerSize) {
                    Write-RgbDebug "調整 $($zone.Name) $($zone.Count) -> $headerSize"
                    Send-RgbResize -Stream $session.Stream -Device ([uint32]$board.Index) -Zone ([int]$zone.Index) -Size $headerSize
                }
            }
            Start-Sleep -Milliseconds 300
            $board = Get-Board -Stream $session.Stream
            $hardwareMode = $board.Modes | Where-Object { $_.Name -eq $modeSpec.Mode }
            if (-not $hardwareMode) {
                throw "$($catalog.Device) 沒有 $($modeSpec.Mode) 模式"
            }
            if (($hardwareMode.Flags -band 0x10) -eq 0) {
                throw "$($modeSpec.Mode) 不能調整亮度"
            }

            $span = [int64]$hardwareMode.BrightnessMax - [int64]$hardwareMode.BrightnessMin
            $brightness = [uint32]($hardwareMode.BrightnessMin + [int64]($span * $modeSpec.Brightness / 100))
            $speed = [uint32]$hardwareMode.Speed
            if ($modeSpec.Contains('Speed') -and (($hardwareMode.Flags -band 1) -ne 0)) {
                $speedMin = [int64]$hardwareMode.SpeedMin
                $speedMax = [int64]$hardwareMode.SpeedMax
                $speed = [uint32]($speedMin + [int64](($speedMax - $speedMin) * $modeSpec.Speed / 100))
            }
            $colorMode = [uint32]$hardwareMode.ColorMode
            $colorBytes = [byte[]]@()
            if ($modeSpec.Contains('Color') -and (($hardwareMode.Flags -band 0x40) -ne 0)) {
                $hex = [string]$modeSpec.Color
                $colorMode = 2
                $colorBytes = [byte[]]@(
                    [Convert]::ToByte($hex.Substring(0, 2), 16),
                    [Convert]::ToByte($hex.Substring(2, 2), 16),
                    [Convert]::ToByte($hex.Substring(4, 2), 16)
                )
            }
            $payload = Get-ModePayload -Mode $hardwareMode -Brightness $brightness -Speed $speed -ColorMode $colorMode -ColorBytes $colorBytes
            Send-OrgbPacket -Stream $session.Stream -Device ([uint32]$board.Index) -PacketId 1101 -Payload $payload

            $applied = Get-OrgbModes -Stream $session.Stream -Device ([uint32]$board.Index)
            $active = $applied.Modes[$applied.Active]
            if ($active.Name -ne $modeSpec.Mode -or $active.Brightness -ne $brightness) {
                throw "燈光沒有套用成功（目前 $($active.Name)，亮度 $($active.Brightness)）"
            }
            $header = @($applied.Zones | Where-Object { $_.Name -like 'ARGB*' -and [int]$_.Count -ne $headerSize })
            if ($header.Count -gt 0) {
                throw "ARGB 接頭沒有設定 LED 數：$($header.Name -join ', ')"
            }
            $after = (@($applied.Zones) | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ', '
            Write-RgbDebug "讀回 mode=$($active.Name) brightness=$($active.Brightness) speed=$($active.Speed) colorMode=$($active.ColorMode) zones=$after"
            Start-Sleep -Milliseconds 500
        }
        finally {
            $session.Stream.Close()
            $session.Client.Close()
        }
    }
    catch {
        Write-RgbDebug "失敗 $ModeName：$($_.Exception.Message)"
        throw
    }
    finally {
        if ($server -and -not $server.HasExited) {
            Stop-Process -Id $server.Id -Force
        }
    }

    Save-RgbMode -ModeName $ModeName
    Write-RgbDebug "完成 $ModeName"
    Write-Host ("已套用 {0}：{1}" -f $ModeName, $modeSpec.Summary) -ForegroundColor Green
}

if ($Name) {
    Invoke-RgbMode -ModeName $Name
    return
}

while ($true) {
    Show-RgbMenu
    Write-Host ''
    $choice = Read-Host '要切換到哪個模式？(編號或名稱，直接 Enter 離開)'
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Host '離開。'
        break
    }

    $target = Resolve-RgbChoice -Choice $choice
    if (-not $target) {
        Write-RgbDebug "無法辨識：$choice"
        Write-Host '沒有這個模式。' -ForegroundColor Yellow
        continue
    }

    Write-RgbDebug "選擇 $choice -> $target"
    try {
        Invoke-RgbMode -ModeName $target
        Clear-RgbWindow
    }
    catch {
        Write-Host "切換失敗：$($_.Exception.Message)" -ForegroundColor Red
    }
}
