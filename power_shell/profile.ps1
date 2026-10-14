
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

# claude：全域 remoteControlAtStartup 為 false（VS Code extension 不自動開 Remote Control），
# 從 terminal 開的 claude 另外載入 settings.cli.json 打開它。
function claude {
    $exe = Get-Command claude -CommandType Application | Select-Object -First 1
    $cliSettings = Join-Path $HOME '.claude\settings.cli.json'
    if (Test-Path $cliSettings) {
        & $exe --settings $cliSettings @args
    } else {
        & $exe @args
    }
}

# claude：cl 當 claude
Set-Alias -Name cl -Value claude

# codex：cx 當 codex
Set-Alias -Name cx -Value codex
