# VS Code 設定

2026-10-04 從 Cursor 轉回 VS Code，設定以 Cursor 為主。舊的 VS Code 設定備份在 `backup/vscode-20261004/`（不進版本庫）。

## Repo 複本

| repo | 實際載入 | 說明 |
|---|---|---|
| `vscode/settings.json` | `%APPDATA%\Code\User\settings.json` | 所有 profile 共用 |
| `vscode/keybindings.json` | `%APPDATA%\Code\User\keybindings.json` | Windows 用；所有 profile 共用。按鍵說明見 `vscode-keybindings.md` |
| `vscode/keybindings.macos.json` | `~/Library/Application Support/Code/User/keybindings.json` | macOS 用；所有 profile 共用 |
| `vscode/mcp.json` | `%APPDATA%\Code\User\mcp.json` | 由 `~\.cursor\mcp.json` 轉換 |
| `vscode/extensions.json` | — | 各 profile 的 extension 清單 |


## 同步腳本

```bash
python3 vscode/sync_vscode.py                       # repo -> VS Code (settings/keybindings/mcp)
python3 vscode/sync_vscode.py --pull                # VS Code -> repo（在 UI 改過設定後）
python3 vscode/sync_vscode.py --check               # 只比對設定檔與 extension 是否一致（有差異 exit 1；JSON 依語意比對，忽略 key 順序／註解／格式）
python3 vscode/sync_vscode.py --check-verbose       # 同 --check，另列出 diff 與缺少／多出的 extension
python3 vscode/sync_vscode.py --extensions          # 依 extensions.json 補裝
python3 vscode/sync_vscode.py --extensions --prune   # 另外移除清單外的 extension
```

支援 Windows 與 macOS；其他平台會在寫入前拒絕。一般同步與 `--pull` 不需要 CLI；`--check`（包含 extension 比對）、`--check-verbose` 與 `--extensions` 需要 VS Code CLI。Windows 使用 `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd`；macOS 依序搜尋 `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`、`~/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`，最後搜尋 PATH 中的 `code`。找不到 CLI 時回報錯誤。

同步會先確認所有來源存在，再建立目的目錄並複製。

## Settings Sync

- 帳號：GitHub。Windows 與 MBP 都會用 VS Code。
- keybindings 依平台分開同步（`settingsSync.keybindingsPerPlatform` 預設 `true`）。repo 的 `keybindings.json` 維護 Windows 設定，`keybindings.macos.json` 維護 MBP 的 macOS 設定。
- settings 跨平台共用。只跟機器有關的設定放進 `settingsSync.ignoredSettings`：`window.zoomLevel`、`terminal.integrated.gpuAcceleration`。

## Profiles

照 Cursor 的 profile 重建。所有 profile 都共用 Default 的 settings、keybindings、snippets、tasks，只有 extensions 不同。新視窗預設用 Default（`window.newWindowProfile`）。

| profile | 用途 / workspace |
|---|---|
| Default | 新視窗預設；文件編輯、資料檢視與設定維護（原 Doc 已移除） |
| Python | 由原 Default 複製，Python 開發 |
| .NET | RyokoTower 與 worktree |
| Flutter | idt-siteeye |

## Status Bar

所有 Profile 統一隱藏以下 Status Bar 項目（不會停用功能或 extension）：

- Problems：`status.problems`
- Git Graph：`mhutchie.git-graph`
- Claude Code for VS Code：`Anthropic.claude-code`

這份清單儲存在各 Profile 的 `globalStorage/state.vscdb`，不屬於共用的 `settings.json`。使用以下腳本套用到 Default 與所有已登錄的 Profiles，保留其他已隱藏的項目：

```powershell
pwsh vscode/hide-statusbar-items.ps1
```

需要 `sqlite3` 在 PATH 中。建議先關閉 VS Code 再執行；若執行時 VS Code 已開啟，請重新開啟以載入，期間不要再修改 Status Bar 隱藏清單，以免記憶體中的舊狀態覆寫變更。腳本會將修改前的值備份到 `backup/vscode-statusbar-時間戳/`，並讀回確認。新建 Profile 後需再執行一次；一般 `sync_vscode.py` 不會同步這份內部狀態。
