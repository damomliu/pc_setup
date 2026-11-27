# Herdr 設定

## 配置狀態

- Repo 副本: [herdr-config.toml](config/herdr-config.toml)
- Windows 實際載入: `%APPDATA%\herdr\config.toml`
- WSL Ubuntu-24.04 實際載入: `/home/damon/.config/herdr/config.toml`, 套用相同的 theme 與 `[keys]` 快速鍵
- `config/herdr-config.toml` 是 theme 與快速鍵片段, 需合併至上述實際設定; 只修改 repo 副本不會生效.保留原本的 `onboarding`, `[ui.toast]` 等設定, 不要整份覆蓋
- 修改後執行 `herdr server reload-config`, 確認回傳 `status: applied` 且 `diagnostics` 為空
- Windows 與 WSL 的 Herdr 設定各自獨立, 需分別合併並在各自環境執行 reload
- 以已安裝的 Herdr 0.9.3 為準; 下次啟動 Herdr 時載入.已開啟的 client 可用 `Ctrl+B, Shift+R` reload config

## Popup 標題

自訂 popup 第一行以粗體亮青色顯示標題 (ANSI `1;96`), 標題結尾重設樣式, 空一行後顯示原有內容. 清畫面、確認、錯誤與無資料畫面均沿用此格式.

| 快速鍵 | 標題 |
|---|---|
| Prefix, M | 移動 pane 至 tab |
| Prefix, Shift+M | 移動 pane 至 workspace |
| Prefix, I | Pane 總覽 |
| Prefix, U | Agent 用量 |
| Prefix, Y / Prefix, Shift+Y | 開啟 Yazi |
| Prefix, Shift+S | 卸載 SSHFS |
| Prefix, T | Git Graph |

## 快速鍵

主要 pane/tab 操作交給 Herdr, WezTerm 保留外層管理功能

- `Ctrl+B` -- Herdr prefix
- `Ctrl+G, Ctrl+G` -- 在 WSL Herdr 開啟 Go To, 優先顯示 WSL Local 與已加入的 WIN machine 的 Blocked panes; 兩邊皆無 Blocked 才顯示 Done. 查詢失敗則提示並保留 Blocked. 查詢方式與使用前提見 [WezTerm 快速鍵設定](wezterm.md#快速鍵設定).
- `Ctrl+G, Ctrl+B` -- 直接開啟 Go To 並篩選 Blocked, 由 [WezTerm 快速鍵設定](wezterm.md#快速鍵設定) 轉譯為 `Ctrl+B, g, b`, 不執行狀態查詢.
- `Ctrl+G, Ctrl+D` -- 開啟 Go To 並篩選 Done, 由 [WezTerm 快速鍵設定](wezterm.md#快速鍵設定) 轉譯為 `Ctrl+B, g, d`. Herdr 的 `Prefix, B` 維持切換 sidebar, `Prefix, G` 維持開啟 Go To.

**Pane操作**

- `Alt+方向鍵` -- 切換至該方向的 pane
- `Alt+Shift+方向鍵` -- 調整 pane 大小
- `Ctrl+Alt+Shift+方向鍵` -- 與該方向的 pane 交換位置; 保留 `Prefix, Shift+H/J/K/L` 對應左/下/上/右
- `Alt+Z` -- 切換 pane zoom
- `Ctrl+B` 放開後 `;` (`Prefix, ;`) -- 回到前次聚焦的 pane, 可跨 tab/workspace
- `Prefix, \` -- 左右分割 pane

**Workspace/Tab操作**

- `Ctrl+Alt+ <- ` / `Ctrl+Alt+ -> ` -- 切換上一個/下一個 tab
- `Ctrl+Alt+^` / `Ctrl+Alt+v` -- 切換上一個/下一個 workspace
- `Prefix, 1`~`Prefix, 9` -- 依編號切換 tab(herdr 預設, 不需設定)
- `Prefix, C` -- 直接新增 tab, 不詢問名稱(`[ui] prompt_new_tab_name = false`, tab 名稱交給 Auto Title)
- `Prefix, I` -- 顯示目前 tab ID
- `Prefix, M` -- 依目前 workspace 的 tab 順序選擇目的地, 將 pane 移至該 tab 右側並聚焦. 初始反白停在 `(current)` 下一列, 若目前是最後一個 tab 就停在 `N. 新增 tab`. 確認 `(current)` 會留在選單. 按 N 可直接新增 tab 並移入 pane.
- `Prefix, Shift+M` -- 選擇 workspace, 將目前 pane 移至該 workspace 的 active tab 右側並聚焦該 pane. 選單依 workspace 順序顯示, linked worktree 列在同 repo 的主 workspace 下方並加上 `>`. 初始反白停在 `(current)`, 確認該列會留在選單.
- `Prefix, U` -- popup 以彩色進度條顯示 Claude/Codex usage (5h/Wk), `U` 切換剩餘/已使用, `T` 切換相對/重置時間, `R` 重新查詢, `Space`/`Esc`/`Enter` 關閉; 需要 [quota-cli](#quota-cli)
- `Prefix, Y` -- 右側 split 開 Yazi, 瀏覽目前 pane 的本機或 SSH 遠端目錄; 見 [Yazi / SSHFS](#yazi--sshfs)
- `Prefix, Shift+Y` -- 同 `Prefix, Y`, 但在目前 workspace 新增 tab 開 Yazi
- `Prefix, Shift+S` -- 列出 sshfs 掛載點, 選擇後卸載
- `Prefix, T` -- 在新 tab 以 git-graph-tui 顯示目前 repo 的 commit graph; 見 [Git Graph](#git-graph). `Prefix, Shift+G` 為 Herdr 預設的 new worktree, 不可占用
- `Prefix, S` 維持 Herdr 預設的 Settings
### Pane 移動 popup 安裝

Windows 使用 [herdr-move-pane.ps1](src/herdr-move-pane.ps1), 複製至 `%APPDATA%\herdr\herdr-move-pane.ps1`; repo 的 `[[keys.command]]` 可直接合併

WSL 使用 [herdr-move-pane.py](src/herdr-move-pane.py), 複製至 `~/.config/herdr/herdr-move-pane.py`, 將該 command 改為以下設定(需要 Python 3): 

```toml
[[keys.command]]
key = "prefix+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py"'
description = "move pane to tab"
width = 58
height = 16
```

helper 使用 popup 注入的 `HERDR_ACTIVE_PANE_ID`, `HERDR_ACTIVE_WORKSPACE_ID`, `HERDR_ACTIVE_TAB_ID` 固定來源, 並透過 `HERDR_BIN_PATH` 呼叫 CLI, 沿用 socket 環境.合併時以 `prefix+m` 識別並更新這一筆 command, 保留其他 command, `onboarding` 與 UI 設定, 再分別執行 reload

Tab popup 為 58 欄、16 行 (含外框), 由 Herdr 依終端大小限制. `N. 新增 tab` 固定在清單下方, 有隱藏的 tab 時提示列顯示 `(more)`. 方向鍵選擇、Enter 確認, 數字能唯一判定時直接確認. Esc / Q / Ctrl+C 取消.

同一組 helper 也提供 workspace 模式. Windows 合併 repo 的 `prefix+shift+m` command (加上 `-Mode workspace`); WSL 新增以下 command:

```toml
[[keys.command]]
key = "prefix+shift+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py" workspace'
description = "move pane to workspace"
width = 54
height = 16
```

Workspace popup 為 54 欄、16 行 (含外框), 由 Herdr 依終端大小限制. 有隱藏選項時, 狀態列顯示 `(more)`. 方向鍵選擇、Enter 確認. 數字只對應一個選項時立即確認, 例如有第 10 列時, 輸入 1 後可按 Enter 選第 1 列, 或繼續輸入 0. Esc / Q / Ctrl+C 可取消. 確認後重新檢查來源位置並查詢目的 workspace 的 active tab. 若來源或目的地已失效, 關閉錯誤提示後可重新開啟選單. 合併設定時以快捷鍵識別 command, 保留其他設定.

Herdr 0.9.3 不允許移動 zoom 中 tab 的 pane(`zoomed_tab`); 請先用 `Alt+Z` 取消 zoom.helper 會將這類 `changed: false` 結果當成失敗顯示, 不會悄悄視為成功

### pane 版面 popup 安裝

`Ctrl+B, I` 開啟 Pane 總覽並複製目前的 pane ID. 方向鍵選取相鄰 pane, 並立即複製選取的 ID. 上方沒有 pane 時, ↑ 選取目前的 tab ID. 在 tab ID 上按 ↓ 回到上一個 pane, 其餘方向鍵維持選取. 其他鍵關閉總覽. 粗體黃字 `(已複製)` 標示複製成功的 ID.

Windows 使用 [herdr-list-ids.ps1](src/herdr-list-ids.ps1), 複製至 `%APPDATA%\herdr\herdr-list-ids.ps1`; repo 的 `[[keys.command]]`(`prefix+i`)可直接合併

Windows herdr server 若由 sshd 啟動(例如 WSL 端以 `herdr machine add` 連到此機器), 會跑在 Session 0. Helper 把選取的 pane 或 tab ID 寫入 `%APPDATA%\herdr\clipboard.txt`, 再由 scheduled task `herdr-clipboard` 在互動 session 寫入桌面剪貼簿. Helper 會等待 task 完成. 請在 Windows 上註冊一次此 task (一般使用者權限即可).

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
- Herdr 設定合併到 `~/.config/herdr/config.toml`。以 `key` 更新同名的 `[[keys.command]]`，保留 `onboarding`、`[ui.toast]` 與其他本機設定。執行 `herdr config check` 通過後再執行 `herdr server reload-config`。[macOS 設定](config/herdr-config.macos.toml)
- 將兩支 helper 複製到 `~/.config/herdr/`，由 `/usr/bin/python3` 執行。`Prefix, M` 可移到既有 tab，按 `N` 可移到新 tab。`Prefix, Shift+M` 可移到另一個 workspace 的作用中 tab。`Prefix, I` 開啟 Pane 總覽，用方向鍵選取後會以 `pbcopy` 複製 pane 或 tab ID。[移動 pane](src/herdr-move-pane.py) · [Pane 總覽](src/herdr-list-ids.py)
- 快速鍵跟 Windows 相同，`Alt` 換成 `Option`：`Opt+方向鍵`、`Opt+Shift+方向鍵`、`Opt+Z`。
- Windows 的 `Ctrl+Alt` 系列在 Mac 改用 `Cmd+Opt`：`Cmd+Opt+←/→` 切換 tab、`Cmd+Opt+↑/↓` 切換 workspace、`Cmd+Opt+Shift+方向鍵` 交換 pane。Herdr config 仍寫 `ctrl+alt+…`，由 iTerm2 profile 把 `Cmd+Opt` 送成對應的 escape sequence。`Ctrl+Opt+方向鍵` 留給 BetterTouchTool 的全域快速鍵。
- BetterTouchTool 的 iTerm2 專屬規則 `Cmd+Opt+←/→`（送 `Ctrl+Shift+Tab`／`Ctrl+Tab` 切 iTerm2 tab）需要停用，否則會攔截 Herdr 的切換 tab。
- Prefix：`Ctrl+B` 與 `Cmd+B` 都可以用。`Cmd+B` 是 iTerm2 profile 送出的 `0x02`，Herdr config 仍是 `ctrl+b`。
- iTerm2 profile 的 Option 維持 Normal（不設成 Esc+），Option 組合改由 Keyboard Map 逐一送出 escape sequence（`Opt+方向鍵` → `ESC[1;3x`、`Opt+Shift` → `1;4`、`Cmd+Opt` → `1;7`、`Cmd+Opt+Shift` → `1;8`、`Opt+Z` → `ESC z`）；要新增 Option 快速鍵時，必須在 profile 補上對應的映射。
- 避開 `Ctrl+方向鍵`：這是 macOS Spaces／Mission Control 的快速鍵。
- File Viewer renderer：`brew install glow bat`；`git-delta` 在 macOS 14 的 Homebrew 需從原始碼編譯（z3 編譯失敗），改下載 [GitHub release](https://github.com/dandavison/delta/releases) 的 `delta-<ver>-aarch64-apple-darwin.tar.gz`，將 `delta` 複製到 `~/.local/bin/`。
- iTerm2 直接執行 profile 的 Command 時不經過 shell，herdr server 的 PATH 只有 `/usr/bin:/bin:/usr/sbin:/sbin`，File Viewer 會回報三個 renderer 都 not found。因此 profile 的 Command 為 `/bin/zsh -lic 'exec /Users/yuenlungliu/.local/bin/herdr'`，由 login + interactive zsh 讀入 `~/.zprofile`（Homebrew）與 `~/.zshrc`（`~/.local/bin`）。
- 修改 Command 後需重啟 herdr server 才會用新的 PATH：在非 herdr 的終端機執行 `herdr server stop`（會關閉所有 pane 與 agent），再開新的 `Herdr` profile 視窗；以 `ps eww -p $(pgrep -f "herdr server") | tr ' ' '\n' | grep ^PATH=` 確認含 `/opt/homebrew/bin`。
- File Viewer 使用共用設定，將 `editor = "vi"` 合併到 `~/.config/herdr/plugins/config/herdr-file-viewer/config.toml`，按 `e` 可用 `vi` 開啟檔案。若 File Viewer 回報 renderer not found，先檢查 server 的 PATH。[File Viewer 設定](config/herdr-file-viewer.toml)
- `Prefix, U` 開啟 Claude／Codex 用量 popup。將 [herdr-usage.py](src/herdr-usage.py) 複製到 `~/.config/herdr/`，合併 macOS 設定中的 `prefix+u`，並在本機安裝 `quota-cli`。[安裝方式](#quota-cli)

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

### Git Graph

`Prefix, T` 以 [git-graph-tui](https://github.com/allient/git-graph-tui) (`ggt`, VS Code Git Graph 風格) 在新 tab 開啟 focused pane 所在 repo 的 commit graph, 並 focus 該 tab, 按 `q` 離開並關閉 tab. 右鍵開啟 ggt 的 context menu (checkout/merge/rebase/cherry-pick 等); ggt 在 herdr 內會自動把右鍵交給自己, 若仍跳出 herdr 選單, 可改按 `m`. Toolbar 以 `icons = "nerd"` 顯示 Nerd Font 圖示 (WezTerm 字型已是 Nerd Font, 不需另裝; `auto` 在 WSL/herdr 內不一定偵測得到); 若顯示成空白方框, 表示終端機字型不是 Nerd Font, 改為 `icons = "unicode"`.

- WSL 使用 [herdr-git-graph.py](src/herdr-git-graph.py) popup, 以 focused pane 的 repo root 開官方 plugin `allient/git-graph-tui/integrations/herdr` 的 `graph` pane, 再 `tab focus`. 不直接綁 plugin action `git-graph-tui.open`, 因為從 TUI 觸發時新 tab 會留在背景. 不在 repo 時顯示錯誤.
- 官方 plugin 只支援 Linux/macOS (sh scripts), Windows 改用 [herdr-git-graph.ps1](src/herdr-git-graph.ps1) popup: 不在 repo 時顯示錯誤; ggt 啟動失敗或非零結束時保留訊息, 按任意鍵才關閉 tab.

| 項目 | Windows | WSL |
|---|---|---|
| ggt | [release](https://github.com/allient/git-graph-tui/releases) `git-graph-tui-x86_64-pc-windows-msvc.zip` (驗 sha256), `ggt.exe` -> `%USERPROFILE%\.cargo\bin` | `git-graph-tui-x86_64-unknown-linux-gnu.tar.xz` (驗 sha256), `ggt` -> `~/.cargo/bin` (plugin 固定會找此路徑) |
| 開啟方式 | [herdr-git-graph.ps1](src/herdr-git-graph.ps1) -> `%APPDATA%\herdr\herdr-git-graph.ps1` (UTF-8 with BOM) | `herdr plugin install allient/git-graph-tui/integrations/herdr --yes`, 並將 [herdr-git-graph.py](src/herdr-git-graph.py) -> `~/.config/herdr/herdr-git-graph.py` (LF) |
| `prefix+t` | 合併 repo config 的 popup command | 同 popup, command 改為 `python3 "$HOME/.config/herdr/herdr-git-graph.py"` |
| ggt 設定 | [git-graph-tui.toml](config/git-graph-tui.toml) -> `%USERPROFILE%\.config\git-graph-tui\config.toml` | 同一份 -> `~/.config/git-graph-tui/config.toml` |

### Yazi / SSHFS

`Prefix, Y` 在右側 split 開 Yazi, `Prefix, Shift+Y` 改為新 tab (`-Target tab` / `--tab`). 一般 pane 開本機 cwd, SSH pane 掛載遠端 host 後開啟目錄. 在 Yazi 按 `q` 正常退出會關閉專用 pane, 若該 pane 是 tab 裡唯一的 pane, 也會關閉 tab. 啟動失敗時可在 pane 查看錯誤. `Prefix, Shift+S` 選擇掛載點並卸載, 若有 pane 正在使用會先提示.

- 遠端首次開啟會詢問 RemotePath; 已掛載時沿用該 host 上次路徑. `-DefaultPath` / `--default-path` 可指定預設路徑.
- host 使用 `~/.ssh/config` 的 alias, 不支援含 `RemoteCommand` 的 alias.
- 遠端一律掛載 `/`, 換目錄不必重掛; 遇到舊式掛載會先確認再改掛.
- 遠端大型 repo 使用 File Viewer 會很慢, 改用 Yazi 預設設定, 避免安裝會執行 git status 的外掛.
- `e` 在同一 pane 用 `EDITOR` 編輯選取檔案或游標所在檔案. Windows 與 WSL 在 `EDITOR` 為空時都用 `vim`.
- `o` 直接用 Glow 閱讀 `.md` 或 `.markdown`. 多選時讀第一個選取項目. Windows 使用 Git for Windows 隨附的 `less.exe` 翻頁, WSL 使用 Glow TUI. 在 renderer 按 `q` 回到 Yazi.
- `Enter` 仍照 [yazi.toml](config/yazi.toml) 的 opener 開啟檔案. 文字檔在 Windows 用 `vim`, 在 WSL 用 `$EDITOR` (未設定時用 `vi`). `O` 開啟 Open with, Windows 可選 `code`, `Esc` 取消選單.

**安裝**

| 項目 | Windows | WSL |
|---|---|---|
| Yazi | `winget install --id sxyazi.yazi -e` | 從 [GitHub release](https://github.com/sxyazi/yazi/releases) 下載 `yazi-x86_64-unknown-linux-gnu.zip`, 將 `yazi`, `ya` 放到 `~/.local/bin` |
| Glow 2.1.0+ | `winget install --id charmbracelet.glow -e` | 從 [Glow releases](https://github.com/charmbracelet/glow/releases) 下載對應架構的 Linux binary, 將 `glow` 放到 `~/.local/bin` |
| SSHFS | `winget install --id WinFsp.WinFsp -e` 與 `winget install --id SSHFS-Win.SSHFS-Win -e` | 安裝 `sshfs` |
| 掛載 helper | [sshfs-mount.ps1](src/sshfs-mount.ps1) -> `%APPDATA%\herdr\sshfs-mount.ps1` | [sshfs-mount.sh](src/sshfs-mount.sh) -> `~/.local/bin/sshfs-mount` |
| Yazi 設定 | [yazi.toml](config/yazi.toml) -> `%APPDATA%\yazi\config\yazi.toml` | 選用, -> `~/.config/yazi/yazi.toml` |
| Yazi 快捷鍵 | [keymap.toml](config/keymap.toml) -> `%APPDATA%\yazi\config\keymap.toml` | -> `~/.config/yazi/keymap.toml` |
| Yazi Markdown renderer | [render-markdown.yazi](config/yazi-plugins/render-markdown.yazi/) -> `%APPDATA%\yazi\config\plugins\render-markdown.yazi` | -> `~/.config/yazi/plugins/render-markdown.yazi` |
| Popup helper | [herdr-sshfs.ps1](src/herdr-sshfs.ps1) -> `%APPDATA%\herdr\herdr-sshfs.ps1` (UTF-8 with BOM) | [herdr-sshfs.py](src/herdr-sshfs.py) -> `~/.config/herdr/herdr-sshfs.py` (LF) |

若已自訂 `yazi.toml` 或 `keymap.toml`, 請合併對應的 opener、規則與鍵位. 設定 `YAZI_CONFIG_HOME` 時, `yazi.toml`、`keymap.toml` 與 `plugins/` 都放在該目錄. WSL 有設定 `XDG_CONFIG_HOME` 時, 預設目錄是 `$XDG_CONFIG_HOME/yazi`. 從啟動 Yazi 的 shell 執行 `glow --version` 確認 `PATH` 上能使用既有的 Glow, 然後重開 Yazi. Windows 的 Herdr server 若仍繼承舊的 `PATH`, 在方便時重開 Herdr.

合併 repo config 的 `prefix+y`, `prefix+shift+y` 與 `prefix+shift+s` command; 預設為 Windows, WSL 依註解替換.

Windows 安裝或升級 SSHFS-Win 後, 需以系統管理員設定 `RunAs`, 否則可能出現 error 67:

```powershell
foreach ($n in 'sshfs.k','sshfs.kr') { New-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\WinFsp\Services\$n" -Name RunAs -Value '.' -PropertyType String -Force }
```

Windows 使用 `\\sshfs.kr\<host>` 以 key 認證掛載遠端 `/`. SSHFS-Win 使用內建 Cygwin ssh, 讀取 `%USERPROFILE%\.ssh\config`, 部分 Windows 專用 option 可能不相容. Yazi 所需的 `file.exe` 由 helper 自動使用 Git for Windows 版本, 也可用 `YAZI_FILE_ONE` 指定.

**手動掛載 / 卸載**

- Windows: `sshfs-mount.ps1 nb [-Drive X]` 掛載 `nb:/` (未指定磁碟機時從 `Z:` 往前找); `-List` 列出, `-Unmount X:` 或 `-Unmount nb` 卸載.
- WSL: `sshfs-mount nb` 掛載 `nb:/` 至 `~/mnt/nb`; `sshfs-mount -l` 列出, `sshfs-mount -u nb` 卸載.

## 錄影

以 WezTerm 命令面板的 `錄製 Herdr tab` 以 asciinema 錄製 WSL Herdr, `播放 Herdr 錄影` 以本機 HTML 播放頁重看 (可逐 frame 前後跳, 中途變速). 用法, 已知限制與安裝見 [recordings.md](recordings.md).

## 其他

- theme: `one-dark` 採用接近 Darcula/PyCharm 氛圍的深灰配色

### quota-cli

- `Prefix, U` 由 [herdr-usage.py](src/herdr-usage.py) 執行 `quota-cli usage --json`, 以四條彩色進度條顯示 Claude/Codex 的 5h 與 Wk 額度. 三個平台共用同一支 Python 3 script (Windows 也用 Python, 不另寫 ps1), 並以 [test_herdr_usage.py](src/test_herdr_usage.py) 測試.

| 平台 | 部署位置 | `prefix+u` command |
|---|---|---|
| Windows | `%APPDATA%\herdr\herdr-usage.py` (需要 `python` 在 PATH) | `python "%APPDATA%\herdr\herdr-usage.py"` |
| WSL | `~/.config/herdr/herdr-usage.py` (LF) | `python3 "$HOME/.config/herdr/herdr-usage.py"` |
| macOS | `~/.config/herdr/herdr-usage.py` | `/usr/bin/python3 "$HOME/.config/herdr/herdr-usage.py"` |

- 版面: popup 寬度足夠時 Claude 在左, Codex 在右; 內容寬度不足時改為上下排列. popup 固定 12 行高 (含外框), 上下排列時剛好填滿. Bar 寬度隨 popup 欄寬伸縮 (10~40 格), 以 1/8 格精細度顯示.
- 配色取自 `one-dark`: 依剩餘比例 >= 50% 綠 `#98C379`, 20~49% 黃 `#E5C07B`, < 20% 紅 `#E06C75`, 百分比數字同色; 已使用模式仍依剩餘比例上色. 品牌字樣以粗體加底色顯示: Claude 白字橘底 `#D97757`, Codex 深字藍底 `#61AFEF`. 未填滿格、方案名稱與時間為暗灰 `#5C6370`. 使用 truecolor ANSI.
- 按鍵: `U` 切換剩餘/已使用, `T` 切換相對時間 (`4h42m`, `5d 0h`) 與重置時間 (`今天 18:44`, `明天 04:20`, `週一 09:30`, 7 天以上為 `12/02 09:30`), `R` 重新查詢, `Space`/`Esc`/`Enter` 關閉, 其他鍵忽略. 切換狀態存於 Windows `%LOCALAPPDATA%\herdr\usage-view.json`, WSL/macOS `~/.cache/herdr/usage-view.json`, 下次開啟沿用.
- 標題列左側為粗體亮青色「Agent 用量」, 右側顯示目前模式與「更新 HH:MM」, 查詢期間顯示「查詢中…」. 單一 agent 無資料時該 agent 顯示灰色 `N/A`; quota-cli 完全失敗時顯示 `quota-cli failed`.
- 不安裝完整Quota (`pinkpixel-dev/quota/herdr-plugin`), 僅保留 `quota-cli`; 可用環境變數 `QUOTA_CLI` 指定執行檔路徑.

- macOS 用 `brew install rust` 安裝工具鏈，再執行 `cargo install quota-cli --version 0.4.0 --locked --root "$HOME/.cargo"`。popup 直接執行 `~/.cargo/bin/quota-cli`，沿用本機 Claude Code 與 Codex 的登入狀態。若 macOS 詢問是否允許存取 Claude Code 的 Keychain 項目，依系統提示選擇。[quota-cli 文件](https://github.com/pinkpixel-dev/quota/tree/main/quota-cli)

## 暫時保留與未定事項

- WezTerm 的 `Alt+1`~`Alt+9`, `Alt+[`/`Alt+]` 與 Ubuntu prefix `Ctrl+U` 暫時保留, 留給 WezTerm
