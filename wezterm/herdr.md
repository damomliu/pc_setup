# Herdr 設定

## 配置狀態

- Repo 副本：[herdr-config.toml](config/herdr-config.toml)。
- Windows 實際載入：`%APPDATA%\herdr\config.toml`。
- WSL Ubuntu-24.04 實際載入：`/home/damon/.config/herdr/config.toml`，套用相同的 theme 與 `[keys]` 快速鍵。
- `config/herdr-config.toml` 是 theme 與快速鍵片段，需合併至上述實際設定；只修改 repo 副本不會生效。保留原本的 `onboarding`、`[ui.toast]` 等設定，不要整份覆蓋。
- 修改後執行 `herdr server reload-config`，確認回傳 `status: applied` 且 `diagnostics` 為空。
- Windows 與 WSL 的 Herdr 設定各自獨立，需分別合併並在各自環境執行 reload。
- 以已安裝的 Herdr 0.9.3 為準；下次啟動 Herdr 時載入。已開啟的 client 可用 `Ctrl+B, Shift+R` reload config。

## 快速鍵

主要 pane／tab 操作交給 Herdr，WezTerm 保留外層管理功能。

- `Ctrl+B` — Herdr prefix

**Pane操作**

- `Alt+方向鍵` — 切換至該方向的 pane
- `Alt+Shift+方向鍵` — 調整 pane 大小
- `Ctrl+Alt+Shift+方向鍵` — 與該方向的 pane 交換位置；保留 `Prefix, Shift+H/J/K/L` 對應左／下／上／右
- `Alt+Z` — 切換 pane zoom
- `Prefix, \` — 左右分割 pane

**Workspace/Tab操作**

- `Ctrl+Alt+←` / `Ctrl+Alt+→` — 切換上一個／下一個 tab
- `Ctrl+Alt+↑` / `Ctrl+Alt+↓` — 切換上一個／下一個 workspace
- `Prefix, 1`～`Prefix, 9` — 依編號切換 tab（herdr 預設，不需設定）
- `Prefix, I` — 顯示目前 tab ID
- `Prefix, M` — 移動目前 pane 至其他 tab，預設「新增 tab」

### Pane 移動 popup 安裝

Windows 使用 [herdr-move-pane.ps1](src/herdr-move-pane.ps1)，複製至 `%APPDATA%\herdr\herdr-move-pane.ps1`；repo 的 `[[keys.command]]` 可直接合併。

WSL 使用 [herdr-move-pane.py](src/herdr-move-pane.py)，複製至 `~/.config/herdr/herdr-move-pane.py`，將該 command 改為以下設定（需要 Python 3）：

```toml
[[keys.command]]
key = "prefix+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py"'
description = "move pane to tab"
width = "23%"
height = "18%"
```

helper 使用 popup 注入的 `HERDR_ACTIVE_PANE_ID`、`HERDR_ACTIVE_WORKSPACE_ID`、`HERDR_ACTIVE_TAB_ID` 固定來源，並透過 `HERDR_BIN_PATH` 呼叫 CLI，沿用 socket 環境。合併時以 `prefix+m` 識別並更新這一筆 command，保留其他 command、`onboarding` 與 UI 設定，再分別執行 reload。

Herdr 0.9.3 不允許移動 zoom 中 tab 的 pane（`zoomed_tab`）；請先用 `Alt+Z` 取消 zoom。helper 會將這類 `changed: false` 結果當成失敗顯示，不會悄悄視為成功。

### pane 版面 popup 安裝

Windows 使用 [herdr-list-ids.ps1](src/herdr-list-ids.ps1)，複製至 `%APPDATA%\herdr\herdr-list-ids.ps1`；repo 的 `[[keys.command]]`（`prefix+i`）可直接合併。

Windows herdr server 若由 sshd 啟動（例如 WSL 端以 `herdr machine add` 連到此機器），會跑在 Session 0，`Set-Clipboard` 寫入的是 Session 0 的剪貼簿，使用者桌面上貼不出來。因此 helper 在 Session 0 時改把 pane ID 寫入 `%APPDATA%\herdr\clipboard.txt`，再由 scheduled task `herdr-clipboard`（以互動 session 執行）寫入剪貼簿。此 task 需在 Windows 上註冊一次（一般使用者權限即可）：

```powershell
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless powershell.exe -NoProfile -NonInteractive -Command "Get-Content -Raw -LiteralPath (Join-Path $env:APPDATA ''herdr\clipboard.txt'') | Set-Clipboard"'
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName herdr-clipboard -Action $action -Principal $principal -Settings $settings -Force
```

`conhost --headless` 可避免執行時視窗閃現；`LogonType Interactive` 確保 task 在使用者桌面 session 執行。

WSL 使用 [herdr-list-ids.py](src/herdr-list-ids.py)，複製至 `~/.config/herdr/herdr-list-ids.py`（需要 Python 3），並將 `prefix+i` 的 command 改為 `python3 "$HOME/.config/herdr/herdr-list-ids.py"`。

**note** `Ctrl+Space` 保留給中文輸入法，不可用作 prefix

## Plugins

- Auto Title (`kryptamine/herdr-auto-title`)
  - repo 副本：[herdr-auto-title.env](config/herdr-auto-title.env)，複製至 Windows `%USERPROFILE%\.config\herdr-auto-title\config.env`、WSL `~/.config/herdr-auto-title/config.env`
- File Viewer (`smarzban/herdr-file-viewer`)
  - 快速鍵：`Ctrl+B, F` 以 split 開啟、`Ctrl+B, Shift+F` 以 tab 開啟
  - repo 副本：[herdr-file-viewer.toml](config/herdr-file-viewer.toml)，複製至 `herdr plugin config-dir herdr-file-viewer` 下的 `config.toml`
  - `glow` (Markdown renderer)
  - `delta` (Diff renderer)
  - `bat` (Syntax renderer)
  - 遠端檔案（sshfs）：File Viewer 以 focused pane 的 cwd 為 tree root，將遠端 host 掛載成本機路徑後即可瀏覽
    - 安裝：Windows `WinFsp` + `SSHFS-Win`; WSL `sshfs`
    - helper：Windows: [sshfs-mount.ps1](src/sshfs-mount.ps1) -> `%APPDATA%\herdr\sshfs-mount.ps1`；WSL: [sshfs-mount.sh](src/sshfs-mount.sh) -> `~/.local/bin/sshfs-mount`
    - Windows 安裝後需以系統管理員設定 `RunAs`，否則 WinFsp.Launcher 以 SYSTEM 執行 sshfs，`net use` 會報 error 67：`New-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\WinFsp\Services\sshfs.k' -Name RunAs -Value '.' -PropertyType String -Force`（重裝／升級 SSHFS-Win 後要重設）
    - host 使用 `~/.ssh/config` 的 alias（如 `nb`、`pc`）；有 `RemoteCommand` 的 alias（如 `nb-wsl`）無法用於 sshfs
    - Windows：`sshfs-mount.ps1 nb [RemotePath] [-Drive X]` → `cd X:\` → `Ctrl+B, F`；`-List` 列出掛載、`-Unmount X:`（或 host 名）卸載
    - WSL：`sshfs-mount nb [remotePath]` → `cd ~/mnt/nb` → `Ctrl+B, F`；`sshfs-mount -l` 列出、`sshfs-mount -u nb` 卸載
    - 注意：SSHFS-Win 使用內建 Cygwin ssh（非 `C:\Program Files\OpenSSH`），但讀取 `%USERPROFILE%\.ssh\config`，Windows 專用的 option 可能不相容
    - 注意：遠端大型 git repo 會讓 tree／git status 變慢

不安裝 Quota（`pinkpixel-dev/quota/herdr-plugin`）：sidebar token（如 `5h 100% · Wk 77%`）看不出是剩餘量，Claude Code status line 已顯示 `5h … left · weekly … left`。WSL 保留 `quota-cli`，需要時執行 `quota-cli usage` 查看各 provider 剩餘額度。

## 其他

- theme: `one-dark` 採用接近 Darcula／PyCharm 氛圍的深灰配色。

## 暫時保留與未定事項

- WezTerm 的 `Alt+1`～`Alt+9`、`Alt+[`／`Alt+]` 與 Ubuntu prefix `Ctrl+U` 暫時保留，留給 WezTerm。
