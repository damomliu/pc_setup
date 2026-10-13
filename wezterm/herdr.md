# Herdr 設定

## 配置狀態

- Repo 副本：[herdr-config.toml](herdr-config.toml)。
- Windows 實際載入：`%APPDATA%\herdr\config.toml`。
- WSL Ubuntu-24.04 實際載入：`/home/damon/.config/herdr/config.toml`，套用相同的 theme 與 `[keys]` 快速鍵。
- `herdr-config.toml` 是 theme 與快速鍵片段，需合併至上述實際設定；只修改 repo 副本不會生效。保留原本的 `onboarding`、`[ui.toast]` 等設定，不要整份覆蓋。
- 修改後執行 `herdr server reload-config`，確認回傳 `status: applied` 且 `diagnostics` 為空。
- Windows 與 WSL 的 Herdr 設定各自獨立，需分別合併並在各自環境執行 reload。
- 以已安裝的 Herdr 0.9.3 為準；下次啟動 Herdr 時載入。已開啟的 client 可用 `Ctrl+B, Shift+R` reload config。

## 快速鍵

主要 pane／tab 操作交給 Herdr，WezTerm 保留外層管理功能。

- `Ctrl+B` — Herdr prefix

**Pane操作**

- `Alt+方向鍵` — 切換至該方向的 pane
- `Alt+Shift+方向鍵` — 調整 pane 大小
- `Alt+Z` — 切換 pane zoom
- `Prefix, \` — 左右分割 pane

**Workspace/Tab操作**

- `Ctrl+Alt+←` / `Ctrl+Alt+→` — 切換上一個／下一個 tab
- `Ctrl+Alt+↑` / `Ctrl+Alt+↓` — 切換上一個／下一個 workspace
- `Ctrl+B, M` — popup 選擇目前 pane 的目的 tab：預設反白第一項「新增 tab」，其餘顯示同 workspace 的其他 tab（編號與名稱）。`↑` / `↓` 移動反白，首尾停止，Enter 確認；單按 Esc 或 Q 立即取消。
- 可輸入多位選項編號，有效編號立即反白，Enter 確認；Backspace 刪除一位，方向鍵清空數字。無效編號按 Enter 只提示錯誤，不會執行先前反白項目。清單過長會捲動，長名稱依 popup 寬度截斷，resize 後重新排版。
- 移至既有 tab 時在右側 split；成功後 focus 跟隨原 pane，保留原本執行中的程序。執行前會再次驗證來源與目的地；失敗顯示錯誤，按 Esc 或 Enter 關閉，不會改用新增 tab。helper 結束時還原 terminal mode、顏色及 cursor。

### Pane 移動 popup 安裝

Windows 使用 [herdr-move-pane.ps1](herdr-move-pane.ps1)，複製至 `%APPDATA%\herdr\herdr-move-pane.ps1`；repo 的 `[[keys.command]]` 可直接合併。

WSL 使用 [herdr-move-pane.py](herdr-move-pane.py)，複製至 `~/.config/herdr/herdr-move-pane.py`，將該 command 改為以下設定（需要 Python 3）：

```toml
[[keys.command]]
key = "prefix+m"
type = "popup"
command = 'python3 "$HOME/.config/herdr/herdr-move-pane.py"'
description = "move pane to tab"
width = "70%"
height = "70%"
```

helper 使用 popup 注入的 `HERDR_ACTIVE_PANE_ID`、`HERDR_ACTIVE_WORKSPACE_ID`、`HERDR_ACTIVE_TAB_ID` 固定來源，並透過 `HERDR_BIN_PATH` 呼叫 CLI，沿用 socket 環境。合併時以 `prefix+m` 識別並更新這一筆 command，保留其他 command、`onboarding` 與 UI 設定，再分別執行 reload。

Herdr 0.9.3 不允許移動 zoom 中 tab 的 pane（`zoomed_tab`）；請先用 `Alt+Z` 取消 zoom。helper 會將這類 `changed: false` 結果當成失敗顯示，不會悄悄視為成功。

**note** `Ctrl+Space` 保留給中文輸入法，不可用作 prefix

## 其他

- theme: `one-dark` 採用接近 Darcula／PyCharm 氛圍的深灰配色。

## 暫時保留與未定事項

- WezTerm 的 `Alt+1`～`Alt+9`、`Alt+[`／`Alt+]` 與 Ubuntu prefix `Ctrl+U` 暫時保留，留給 WezTerm。
