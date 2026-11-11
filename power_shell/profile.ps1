
# Cursor / Claude 以管線讀 stdout，卻預設用 OEM 字碼頁 950（Big5）。
# 第一次輸出就會把編碼鎖死，所以必須放在最前面，且此前不能寫出任何文字。
$utf8 = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

# 命令列編輯用 Vi（須在自訂 KeyHandler 之前，否則會被重設）
Set-PSReadLineOption -EditMode Vi -ViModeIndicator Cursor

# Ctrl+D：與 bash 類似，空行送出 EOF 結束；有字元則刪除游標處字元
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit

Import-Module ZLocation

# flutter：f 當 flutter
$flutterBin = 'C:\src\flutter\bin'
if (Test-Path $flutterBin) {
    $paths = $env:PATH -split ';'
    if ($paths -notcontains $flutterBin) {
        $env:PATH = "$flutterBin;$env:PATH"
    }
}
Set-Alias -Name f -Value flutter

# claude：cl 當 claude
Set-Alias -Name cl -Value claude

# codex：cx 當 codex
Set-Alias -Name cx -Value codex

# 只回報本次互動 session 的使用狀態，不傳送指令內容或讀取 history 檔。
if ($env:WEZTERM_PANE -and -not (Test-Path Variable:global:WezTermSessionUsed)) {
    # 手動載入舊 session 的 profile 時無法證明從未執行指令，採保留。
    $global:WezTermSessionUsed = -not (
        $MyInvocation.HistoryId -eq 1 -and
        $MyInvocation.Line -eq ". '$PSCommandPath'" -and
        @(Get-History).Count -eq 0
    )
    $global:WezTermOriginalReadLine = (Get-Command PSConsoleHostReadLine -CommandType Function).ScriptBlock
    function global:Send-WezTermSessionState {
        $state = if ($global:WezTermSessionUsed) { 'used' } else { 'fresh' }
        $value = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${state}:$PID"))
        [Console]::Write("$([char]27)]1337;SetUserVar=PC_SETUP_PS_SESSION=$value$([char]7)")
    }
    # 在 history 去重前處理完成的輸入；不替換 AddToHistoryHandler。
    function global:PSConsoleHostReadLine {
        $line = & $global:WezTermOriginalReadLine
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $global:WezTermSessionUsed = $true
            Send-WezTermSessionState
        }
        return $line
    }
    Send-WezTermSessionState
}
