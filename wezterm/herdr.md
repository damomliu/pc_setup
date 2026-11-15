# Herdr 設定

## 配置狀態

- Repo 副本: [herdr-config.toml](config/herdr-config.toml)
- Windows 實際載入: `%APPDATA%\herdr\config.toml`
- WSL Ubuntu-24.04 實際載入: `/home/damon/.config/herdr/config.toml`, 套用相同的 theme 與 `[keys]` 快速鍵
- `config/herdr-config.toml` 是 theme 與快速鍵片段, 需合併至上述實際設定; 只修改 repo 副本不會生效.保留原本的 `onboarding`, `[ui.toast]` 等設定, 不要整份覆蓋
- 修改後執行 `herdr server reload-config`, 確認回傳 `status: applied` 且 `diagnostics` 為空
- Windows 與 WSL 的 Herdr 設定各自獨立, 需分別合併並在各自環境執行 reload
- 以已安裝的 Herdr 0.9.3 為準; 下次啟動 Herdr 時載入.已開啟的 client 可用 `Ctrl+B, Shift+R` reload config

## 快速鍵

主要 pane/tab 操作交給 Herdr, WezTerm 保留外層管理功能

- `Ctrl+B` -- Herdr prefix

**Pane操作**

- `Alt+方向鍵` -- 切換至該方向的 pane
- `Alt+Shift+方向鍵` -- 調整 pane 大小
- `Ctrl+Alt+Shift+方向鍵` -- 與該方向的 pane 交換位置; 保留 `Prefix, Shift+H/J/K/L` 對應左/下/上/右
- `Alt+Z` -- 切換 pane zoom
- `Prefix, \` -- 左右分割 pane

**Workspace/Tab操作**

- `Ctrl+Alt+ <- ` / `Ctrl+Alt+ -> ` -- 切換上一個/下一個 tab
- `Ctrl+Alt+^` / `Ctrl+Alt+v` -- 切換上一個/下一個 workspace
- `Prefix, 1`~`Prefix, 9` -- 依編號切換 tab(herdr 預設, 不需設定)
- `Prefix, C` -- 直接新增 tab, 不詢問名稱(`[ui] prompt_new_tab_name = false`, tab 名稱交給 Auto Title)
- `Prefix, I` -- 顯示目前 tab ID
- `Prefix, M` -- 移動目前 pane 至其他 tab, 預設"新增 tab"
- `Prefix, Shift+M` -- 移動目前 pane 至其他 workspace, 預設"新增 workspace"; 選擇既有 workspace 後可新增 tab 或選擇既有 tab, 後者以右側 split 加入. 完成後切換至移動的 pane
- `Prefix, U` -- popup 顯示 Claude/Codex usage (5h/Wk 剩餘與重置時間), 任一鍵關閉; 需要 [quota-cli](#quota-cli)
### Pane 移動 popup 安裝

Windows 使用 [herdr-move-pane.ps1](src/herdr-move-pane.ps1), 複製至 `%APPDATA%\herdr\herdr-move-pane.ps1`; repo 的 `[[keys.command]]` 可直接合併

WSL 使用 [herdr-move-pane.py](src/herdr-move-pane.py), 複製至 `~/.config/herdr/herdr-move-pane.py`, 將該 command 改為以下設定(需要 Python 3): 

```toml
[[keys.command]]
key = "prefix+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py"'
description = "move pane to tab"
width = "23%"
height = "18%"
```

helper 使用 popup 注入的 `HERDR_ACTIVE_PANE_ID`, `HERDR_ACTIVE_WORKSPACE_ID`, `HERDR_ACTIVE_TAB_ID` 固定來源, 並透過 `HERDR_BIN_PATH` 呼叫 CLI, 沿用 socket 環境.合併時以 `prefix+m` 識別並更新這一筆 command, 保留其他 command, `onboarding` 與 UI 設定, 再分別執行 reload

同一組 helper 也提供 workspace 模式. Windows 合併 repo 的 `prefix+shift+m` command (加上 `-Mode workspace`); WSL 新增以下 command:

```toml
[[keys.command]]
key = "prefix+shift+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py" workspace'
description = "move pane to workspace"
width = "23%"
height = "18%"
```

兩層選單均可用方向鍵或數字選擇, Enter 確認; Esc / Q / Ctrl+C 取消整個操作. 執行前重新確認來源與目的地仍有效; 若已變動則顯示錯誤, 關閉後重新開啟選單. 合併設定時以快捷鍵識別 command, 保留其他設定.

Herdr 0.9.3 不允許移動 zoom 中 tab 的 pane(`zoomed_tab`); 請先用 `Alt+Z` 取消 zoom.helper 會將這類 `changed: false` 結果當成失敗顯示, 不會悄悄視為成功

### pane 版面 popup 安裝

Windows 使用 [herdr-list-ids.ps1](src/herdr-list-ids.ps1), 複製至 `%APPDATA%\herdr\herdr-list-ids.ps1`; repo 的 `[[keys.command]]`(`prefix+i`)可直接合併

Windows herdr server 若由 sshd 啟動(例如 WSL 端以 `herdr machine add` 連到此機器), 會跑在 Session 0, `Set-Clipboard` 寫入的是 Session 0 的剪貼簿, 使用者桌面上貼不出來.因此 helper 在 Session 0 時改把 pane ID 寫入 `%APPDATA%\herdr\clipboard.txt`, 再由 scheduled task `herdr-clipboard`(以互動 session 執行)寫入剪貼簿.此 task 需在 Windows 上註冊一次(一般使用者權限即可): 

```powershell
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless powershell.exe -NoProfile -NonInteractive -Command "Get-Content -Raw -LiteralPath (Join-Path $env:APPDATA ''herdr\clipboard.txt'') | Set-Clipboard"'
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName herdr-clipboard -Action $action -Principal $principal -Settings $settings -Force
```

`conhost --headless` 可避免執行時視窗閃現; `LogonType Interactive` 確保 task 在使用者桌面 session 執行

WSL 使用 [herdr-list-ids.py](src/herdr-list-ids.py), 複製至 `~/.config/herdr/herdr-list-ids.py`(需要 Python 3), 並將 `prefix+i` 的 command 改為 `python3 "$HOME/.config/herdr/herdr-list-ids.py"`

**note** `Ctrl+Space` 保留給中文輸入法, 不可用作 prefix

### macOS

- 終端機：iTerm2 的 `Herdr` dynamic profile（直接啟動 `~/.local/bin/herdr`）；repo 副本 [iterm2-herdr.json](config/iterm2-herdr.json)，複製到 `~/Library/Application Support/iTerm2/DynamicProfiles/herdr.json` 後 iTerm2 會自動載入。設為預設 profile：`defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "84493b13-8660-41ce-a367-047c1a98b8b9"`（之後重開 iTerm2）。快速鍵映射只存在這個 profile 裡；用其他 profile（例如 `long`）開 Herdr 時，`Opt+Shift`、`Opt+Z`、`Cmd+B` 都不會有作用。
- Herdr 設定：repo 副本 [herdr-config.macos.toml](config/herdr-config.macos.toml)，合併到 `~/.config/herdr/config.toml`（保留 `onboarding`、`[ui.toast]`），再執行 `herdr server reload-config`。
- helper：把 [herdr-move-pane.py](src/herdr-move-pane.py)、[herdr-list-ids.py](src/herdr-list-ids.py) 複製到 `~/.config/herdr/`，用 `/usr/bin/python3` 執行；`Prefix, I` 用 `pbcopy` 複製 pane ID。
- 快速鍵跟 Windows 相同，`Alt` 換成 `Option`：`Opt+方向鍵`、`Opt+Shift+方向鍵`、`Opt+Z`。
- Windows 的 `Ctrl+Alt` 系列在 Mac 改用 `Cmd+Opt`：`Cmd+Opt+←/→` 切換 tab、`Cmd+Opt+↑/↓` 切換 workspace、`Cmd+Opt+Shift+方向鍵` 交換 pane。Herdr config 仍寫 `ctrl+alt+…`，由 iTerm2 profile 把 `Cmd+Opt` 送成對應的 escape sequence。`Ctrl+Opt+方向鍵` 留給 BetterTouchTool 的全域快速鍵。
- BetterTouchTool 的 iTerm2 專屬規則 `Cmd+Opt+←/→`（送 `Ctrl+Shift+Tab`／`Ctrl+Tab` 切 iTerm2 tab）需要停用，否則會攔截 Herdr 的切換 tab。
- Prefix：`Ctrl+B` 與 `Cmd+B` 都可以用。`Cmd+B` 是 iTerm2 profile 送出的 `0x02`，Herdr config 仍是 `ctrl+b`。
- iTerm2 profile 的 Option 維持 Normal（不設成 Esc+），Option 組合改由 Keyboard Map 逐一送出 escape sequence（`Opt+方向鍵` → `ESC[1;3x`、`Opt+Shift` → `1;4`、`Cmd+Opt` → `1;7`、`Cmd+Opt+Shift` → `1;8`、`Opt+Z` → `ESC z`）；要新增 Option 快速鍵時，必須在 profile 補上對應的映射。
- 避開 `Ctrl+方向鍵`：這是 macOS Spaces／Mission Control 的快速鍵。
- File Viewer renderer：`brew install glow bat`；`git-delta` 在 macOS 14 的 Homebrew 需從原始碼編譯（z3 編譯失敗），改下載 [GitHub release](https://github.com/dandavison/delta/releases) 的 `delta-<ver>-aarch64-apple-darwin.tar.gz`，將 `delta` 複製到 `~/.local/bin/`。
- iTerm2 直接執行 profile 的 Command 時不經過 shell，herdr server 的 PATH 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，File Viewer 會回報三個 renderer 都 not found。因此 profile 的 Command 為 `/bin/zsh -lic 'exec /Users/yuenlungliu/.local/bin/herdr'`，由 login + interactive zsh 讀入 `~/.zprofile`（Homebrew）與 `~/.zshrc`（`~/.local/bin`）。
- 修改 Command 後需重啟 herdr server 才會用新的 PATH：在非 herdr 的終端機執行 `herdr server stop`（會關閉所有 pane 與 agent），再開新的 `Herdr` profile 視窗；以 `ps eww -p $(pgrep -f "herdr server") | tr ' ' '\n' | grep ^PATH=` 確認含 `/opt/homebrew/bin`。
- File Viewer 沿用共用的 [herdr-file-viewer.toml](config/herdr-file-viewer.toml)，不需要以絕對路徑指定 renderer；複製到 `~/.config/herdr/plugins/config/herdr-file-viewer/config.toml`。若 File Viewer 又回報 renderer not found，先檢查 server 的 PATH。

## Plugins

- Auto Title (`kryptamine/herdr-auto-title`)
  - repo 副本: [herdr-auto-title.env](config/herdr-auto-title.env), 複製至 Windows `%USERPROFILE%\.config\herdr-auto-title\config.env`, WSL `~/.config/herdr-auto-title/config.env`
- File Viewer (`smarzban/herdr-file-viewer`)
  - 快速鍵: `Ctrl+B, F` 以 split 開啟, `Ctrl+B, Shift+F` 以 tab 開啟
  - repo 副本: [herdr-file-viewer.toml](config/herdr-file-viewer.toml), 複製至 `herdr plugin config-dir herdr-file-viewer` 下的 `config.toml`
  - 編輯器: config.toml 的 `editor = "vi"`, 在 File Viewer 按 `e` 開啟(Win/WSL 皆需 `vi` 在 PATH)
  - `glow` (Markdown renderer)
  - `delta` (Diff renderer)
  - `bat` (Syntax renderer)
  - 遠端檔案(sshfs): File Viewer 以 focused pane 的 cwd 為 tree root, 將遠端 host 掛載成本機路徑後即可瀏覽
    - 安裝: Windows `WinFsp` + `SSHFS-Win`; WSL `sshfs`
    - helper: Windows: [sshfs-mount.ps1](src/sshfs-mount.ps1) -> `%APPDATA%\herdr\sshfs-mount.ps1`; WSL: [sshfs-mount.sh](src/sshfs-mount.sh) -> `~/.local/bin/sshfs-mount`
    - Windows 安裝後需以系統管理員設定 `RunAs`, 否則 WinFsp.Launcher 以 SYSTEM 執行 sshfs, `net use` 會報 error 67: `New-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\WinFsp\Services\sshfs.k' -Name RunAs -Value '.' -PropertyType String -Force`(重裝/升級 SSHFS-Win 後要重設)
    - host 使用 `~/.ssh/config` 的 alias(如 `nb`, `pc`); 有 `RemoteCommand` 的 alias(如 `nb-wsl`)無法用於 sshfs
    - Windows: `sshfs-mount.ps1 nb [RemotePath] [-Drive X]`  ->  `cd X:\`  ->  `Ctrl+B, F`; `-List` 列出掛載, `-Unmount X:`(或 host 名)卸載
    - WSL: `sshfs-mount nb [remotePath]`  ->  `cd ~/mnt/nb`  ->  `Ctrl+B, F`; `sshfs-mount -l` 列出, `sshfs-mount -u nb` 卸載
    - 注意: SSHFS-Win 使用內建 Cygwin ssh(非 `C:\Program Files\OpenSSH`), 但讀取 `%USERPROFILE%\.ssh\config`, Windows 專用的 option 可能不相容
    - 注意: 遠端大型 git repo 會讓 tree/git status 變慢

## 其他

- theme: `one-dark` 採用接近 Darcula/PyCharm 氛圍的深灰配色

### quota-cli

- 不安裝完整Quota (`pinkpixel-dev/quota/herdr-plugin`), 僅保留 `quota-cli`, 由 `Prefix, U` popup 執行 `quota-cli usage` 並只顯示 claude/codex 兩行 (repo 的 `prefix+u` command 可直接合併至 Windows config; WSL 改用註解中的 bash command)

## 暫時保留與未定事項

- WezTerm 的 `Alt+1`~`Alt+9`, `Alt+[`/`Alt+]` 與 Ubuntu prefix `Ctrl+U` 暫時保留, 留給 WezTerm
