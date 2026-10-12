# VS Code 設定

2026-10-04 從 Cursor 轉回 VS Code，設定以 Cursor 為主。舊的 VS Code 設定備份在 `backup/vscode-20261004/`（不進版本庫）。

## 檔案

| repo | 實際載入 | 說明 |
|---|---|---|
| `vscode/settings.json` | `%APPDATA%\Code\User\settings.json` | 所有 profile 共用 |
| `vscode/keybindings.json` | `%APPDATA%\Code\User\keybindings.json` | Windows 用；所有 profile 共用。按鍵說明見 `vscode-keybindings.md` |
| `vscode/mcp.json` | `%APPDATA%\Code\User\mcp.json` | 由 `~\.cursor\mcp.json` 轉換 |
| `vscode/extensions.json` | — | 各 profile 的 extension 清單 |
| `vscode/sync-vscode.ps1` | — | 同步腳本 |

```powershell
pwsh vscode/sync-vscode.ps1                     # repo -> VS Code
pwsh vscode/sync-vscode.ps1 -Pull               # VS Code -> repo（在 UI 改過設定後）
pwsh vscode/sync-vscode.ps1 -Extensions         # 依 extensions.json 補裝
pwsh vscode/sync-vscode.ps1 -Extensions -Prune  # 另外移除清單外的 extension
```

## Settings Sync

- 帳號：GitHub。Windows 與 MBP 都會用 VS Code。
- keybindings 依平台分開同步（`settingsSync.keybindingsPerPlatform` 預設 `true`）。這份 `keybindings.json` 只會同步到 windows 那份，MBP 的 mac 那份另外維護。
- settings 跨平台共用。只跟機器有關的設定放進 `settingsSync.ignoredSettings`：`window.zoomLevel`、`terminal.integrated.gpuAcceleration`。

## Profiles

照 Cursor 的 profile 重建。所有 profile 都共用 Default 的 settings、keybindings、snippets、tasks，只有 extensions 不同。新視窗預設用 Default（`window.newWindowProfile`）。

| profile | 用途 / workspace |
|---|---|
| Default | 新視窗預設；文件編輯、資料檢視與設定維護（原 Doc 已移除） |
| Python | 由原 Default 複製，Python 開發 |
| .NET | RyokoTower 與 worktree |
| Flutter | idt-siteeye |

### 快速鍵

見 [vscode-keybindings.md](vscode-keybindings.md)。
