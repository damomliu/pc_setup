# PowerShell Profile

本機有兩種 PowerShell，各自讀自己的 profile，內容以 `profile.ps1`（repo 副本）為準，兩邊保持 byte identical。

| | PowerShell 7 | Windows PowerShell 5.1 |
|---|---|---|
| 執行檔 | `pwsh` | `powershell.exe` |
| Profile 路徑 | `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` | `~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` |

## 內容

- UTF-8
    - 最前面設定 UTF-8（`$utf8`、`[Console]::InputEncoding/OutputEncoding`、`$OutputEncoding`）
    - Cursor / Claude 以管線讀 stdout，預設 OEM 字碼頁 950（Big5），第一次輸出就會鎖死編碼，所以這段必須在最前面，且此前不能輸出任何文字。
- `Set-PSReadLineOption -EditMode Vi -ViModeIndicator Cursor`（須在自訂 KeyHandler 之前，否則會被重設）
- `Ctrl+D`：空行送出 EOF 結束，有字元則刪除游標處字元
- `Import-Module ZLocation`
- flutter：把 `C:\src\flutter\bin` 加入 PATH
- `claude` function：包住 claude，存在 `~\.claude\settings.cli.json` 時加上 `--settings` 載入它
    - 全域 `~\.claude\settings.json` 的 `remoteControlAtStartup` 設為 `false`，VS Code extension 開的 session 不會自動啟用 Remote Control
    - `settings.cli.json` 內容為 `{ "remoteControlAtStartup": true }`，從 terminal 開的 CLI 仍會自動啟用
    - WSL 有獨立的 `~/.claude`，同樣做法：WSL 的 `settings.json` 設 `false`、建立 `settings.cli.json`，`~/.bashrc` 加同名 `claude` function（`command claude --settings ...`）

## Alias

| Alias | 指令 |
|---|---|
| `f` | flutter |
| `cl` | claude |
| `cx` | codex |

## 部署

用 `sync-profile.ps1` 同步：

```powershell
.\power_shell\sync-profile.ps1          # repo -> 兩個 profile
.\power_shell\sync-profile.ps1 -Pull    # PowerShell 7 profile -> repo
.\power_shell\sync-profile.ps1 -Check   # 只比對 SHA256
```

修改時先改 `profile.ps1`，再跑預設同步。現有視窗要重開或執行 `. $PROFILE` 才會生效。

## 其他

- Windows Terminal settings
- Vim：`Set-PSReadLineOption -EditMode Vi`（見上方內容）
