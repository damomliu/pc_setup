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

照 Cursor 的 profile 重建。三個 profile 都共用 Default 的 settings、keybindings、snippets、tasks，只有 extensions 不同。新視窗預設用 Doc（`window.newWindowProfile`）。

| profile | 用途 / workspace |
|---|---|
| Default | pc_setup、`.cursor`、aiont（WSL、stsp-05/07） |
| .NET | RyokoTower 與 worktree |
| Doc | 新視窗、schedule、ubuntu_setup、WSL `.ssh`、aiont（ctky-a） |
| Flutter | idt-siteeye |

Cursor 把 remote-ssh / remote-wsl / remote-containers 設成套用到所有 profile；VS Code 這邊改成在每個 profile 都裝。remote-ssh 會連帶裝 pack 成員 remote-explorer、remote-ssh-edit，前者留著，後者移除。

`gabemahoney.pycharm-dark-theme-for-python` 只在 OpenVSX 上架，VS Code Marketplace 裝不到，所以沒搬。

## 與 Cursor 的對應

| Cursor | VS Code |
|---|---|
| `anysphere.cursorpyright` | `ms-python.vscode-pylance`（`python.languageServer: Pylance`） |
| `anysphere.remote-*` | `ms-vscode-remote.remote-*` |
| `anysphere.csharp`、`muhammad-sammy.csharp` | `ms-dotnettools.csharp` |
| `kylinideteam.gitlens` | `eamodio.gitlens` |
| Cursor Tab（`cursor.cpp.*`） | Copilot（`github.copilot.enable`、`nextEditSuggestions`） |
| 回答完成提示音 | `accessibility.signals.chatResponseReceived` |
| `update.mode: silentlyApplyOnQuit` | `default` |

### 快速鍵

見 [vscode-keybindings.md](vscode-keybindings.md)。

## 不搬的 Cursor 設定

`~\.cursor\cli-config.json`、Cursor 內建 skills、User Rules、`state.vscdb` 裡的對話紀錄。
