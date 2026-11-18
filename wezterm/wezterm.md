# WezTerm 設定

實際載入的設定是 `~/.wezterm.lua`；`config/wezterm.lua` 為 repo 副本。

## 快速鍵設定

已套用至 `.lua` 並同步至 `~/.wezterm.lua`。Prefix 使用 `Ctrl+G`；已解除 `Alt+Z`、`Alt+方向鍵`、`Alt+Shift+方向鍵` 的一般模式綁定，讓按鍵傳入 Herdr。

已用 `DisableDefaultAssignment` 解除 `Ctrl+Alt+Shift+方向鍵` 的預設 `AdjustPaneSize`，讓 Herdr 接收並交換該方向的 pane 位置。

主要 pane／tab 操作交給 Herdr，WezTerm 保留外層管理功能。Herdr 的配置共識見 [herdr.md](herdr.md)。`Ctrl+Space` 保留給中文輸入法，不作為 prefix。

這些 Alt 快速鍵還需要將 `config/herdr-config.toml` 的 `[keys]` 合併至 `%APPDATA%\herdr\config.toml`，再執行 `herdr server reload-config`；只解除 WezTerm 綁定不會自動建立 Herdr 綁定。

- `Alt+]` / `Alt+[`：維持 zoom，切換下一個／上一個 pane
- `Alt+1`～`Alt+9`：維持 zoom，切換至指定 pane

上述快捷鍵尚未決定是否移交或改綁。

- `Ctrl+PageUp` / `Ctrl+PageDown`：上一個／下一個 tab

Prefix 為 `Ctrl+G`（按下後有 2 秒可接下一鍵，期間右上角顯示 `LEADER`）；以下既有 prefix 操作維持不變：

- `Prefix, \`：左右分割 pane；若這一疊 pane 比視窗寬或高，會先收回再分割
- `Prefix, -`：上下分割 pane；若這一疊 pane 比視窗寬或高，會先收回再分割
- `Prefix, X`：直接關閉 pane
- `Prefix, C`：建立 tab
- `Prefix, W`：關閉目前 tab（會先確認）
- `Prefix, N` / `Prefix, P`：下一個／上一個 tab
- `Prefix, 1`～`Prefix, 9`：切換至指定 tab
- `Prefix, Shift+1`～`Prefix, Shift+9`：把目前 pane 移到 tab 1～9，成為最右側一欄；該 tab 不存在則開新 tab；移入時依欄數重排欄寬，列高沿用原比例
- `Prefix, ,`：命名 tab；清空可恢復自動標題
- `Prefix, Q`：在各 pane 上顯示編號，按數字直接切換至該 pane；若有 pane 被擠成 0 寬／高會先救回來再顯示
- `Prefix, L`：開啟啟動選單
- `Ctrl+G, Ctrl+G`: 在 WSL Herdr 開啟 Go To, 優先顯示 WSL Local 與 WIN 的 Blocked panes; 兩邊皆無 Blocked 時改顯示 Done. 分別轉譯為 `Ctrl+B, g, b` 或 `Ctrl+B, g, d`.
- `Ctrl+G, Ctrl+B`: 直接開啟 Herdr Go To 並篩選 Blocked, 轉譯為 `Ctrl+B, g, b`, 不執行狀態查詢.
- `Ctrl+G, Ctrl+D`: 開啟 Herdr Go To 並篩選 Done, 轉譯為 `Ctrl+B, g, d`.
- 上述三組快速鍵需在 2 秒內完成, 目前 pane 須執行 Herdr 且位於一般模式, 沒有 modal popup. 開啟後由使用者選擇並按 Enter 跳轉; 無符合項目時顯示空清單.
- Blocked 優先查詢由 wezterm.lua 直接執行, 不需額外 helper. 先以 `PATH` 上的 Windows `herdr.exe api snapshot` 查詢 WIN (WIN machine 即本機 Windows Herdr server, 直接查詢約 60ms, 經 WSL ssh 約 1.3 秒); 有 Blocked 即開啟 Blocked, 否則再於 Ubuntu-24.04 查詢 Local `api snapshot` (期限 3 秒). 涵蓋兩個 session 的全部 workspaces. 任一查詢失敗或格式無效時顯示提示並保留 Blocked. 使用前提為 WSL Herdr, 且 WIN profile 指向本機; Windows server 由 sshd 啟動時為 elevated, 一般權限的 WezTerm 會被拒, 需在 `%APPDATA%\herdr\config.toml` 設定 `[server] allow_unelevated_clients = true` (見 [herdr-config.toml](config/herdr-config.toml)) 並重啟 server; 若 WIN 改指向其他機器需改回 `--machine WIN` 查詢. 狀態以查詢當下為準.
- `Prefix, S`：選 pane 並與目前 pane 對調位置；對調後 focus 跟著移到目標位置
- `Prefix, ←`／`→`／`↑`／`↓`：依該方向的實際位置切換至相鄰 pane，切換後維持原本的 zoom 狀態
- `Prefix, Z`：切換目前 pane 的 zoom
- `Prefix, Shift+←`／`Shift+→`／`Shift+↑`／`Shift+↓`：往該方向調整目前 pane 的大小

Ubuntu Prefix 為 `Ctrl+U`（按下後有 2 秒可接下一鍵）：

- `Ctrl+U, C`：建立 Ubuntu tab
- `Ctrl+U, \`：建立左右分割的 Ubuntu pane
- `Ctrl+U, -`：建立上下分割的 Ubuntu pane

其他：

- `Ctrl+Shift+P`：命令面板
  - 搜 `Herdr Go To`: `開啟 Herdr Go To (Blocked 優先)` 執行上述跨 WSL Local 與 WIN 的條件篩選; `開啟 Herdr Go To Blocked` / `開啟 Herdr Go To Done` 分別直接傳送 `Ctrl+B, g, b` / `Ctrl+B, g, d`, 使用前提同上述快速鍵.
  - 搜 `Herdr`：`開啟 Herdr Tab`，在目前視窗新增 Ubuntu-24.04 tab，從 Linux home 執行 Herdr；結束後回到 Bash，不另加快速鍵。
    - Herdr 進入 TUI 後，若視窗只有兩個 tab，且原 tab 只有一個 pane、為本次 session 尚未送出非空白指令的預設 PowerShell，就直接關閉原 tab。
    - 其他 shell、缺少 session 狀態、啟動失敗或 15 秒內未就緒時，保留原 tab。需使用同步 profile 後新開的 PowerShell session；清除 history 不會恢復未使用狀態。
  - 搜 `RyokoTower`：七個模擬器，佈局相同
    - `RyokoTower Simulators (新分頁)`：在目前視窗開一個 tab
    - `RyokoTower Simulators (新視窗)`：開一個新視窗；等它最大化、格子尺寸跟上來源視窗後才切 pane，再均分欄寬與列高
  - 搜 `sync`：把目前 pane 的輸入列送到同 tab 其他 pane；若目前 pane 的指令尚未送出，也會在目前 pane 按 Enter；輸入列為空時跳出提示
  - 搜 `close`：關閉目前 tab
  - 搜 `字型`：`切換預設字型`，目前視窗的主字型在 Maple Mono NF CN 與 Sarasa Term TC Nerd Font 之間切換；只影響目前視窗，重開 WezTerm 回到 Maple
  - 搜 `equal`：平均分配欄寬（僅同列／Tab）、列高（僅同欄／Tab）、或欄寬與列高（Tab）
    - 依分割結構按份數分配：通高的一欄算 1 份，旁邊上 2 下 3 的那塊算 3 份，所以下列 3 欄與通高欄同寬；「僅同列／同欄」只數目前 pane 那一路，其他部分沿用原比例
    - 做法是把 pane 暫移到其他 tab，再按算好的格數移回，tab bar 會短暫閃過暫存 tab；已經均分就不動
    - pane 位置還在更新（互相重疊）或視窗放不下時，只跳提示不重排
  - 搜 `Pane: 切換 zoom`：切換目前 pane 的 zoom 狀態
  - 搜 `Pane: 調整大小`：往左／右／上／下調整目前 pane 的大小
- `Ctrl+Shift+U` / `Ctrl+Shift+D`：向上／向下翻頁
- `Ctrl+Shift+F`：搜尋終端內容
- `Ctrl+滑鼠左鍵`：開啟連結
- 選取文字即複製；滑鼠右鍵貼上


## 其他設定

- 預設 shell：PowerShell 7
- 啟動選單：PowerShell 7、Ubuntu 24.04（進 Linux home）、Git Bash、Command Prompt、SSH `nb`
- 配色：Catppuccin Mocha
- 字型：Maple Mono NF CN 11 pt（缺字時 fallback 到 Sarasa Term TC Nerd Font）
- 啟動時最大化；只有一個 tab 時隱藏 tab bar
- 降低非作用中 pane 的亮度與飽和度
- Tab 自動顯示編號、程序、資料夾與 pane 位置 `(目前/總數)`；zoom 時為 `(目前/總數Z)`
- 視窗標題為 `[Z] [目前 tab/tab 總數] 標題`；`[Z]` 僅 zoom 時顯示，`[目前 tab/tab 總數]` 僅多於一個 tab 時顯示
- Claude session 有名稱時，tab 與視窗標題顯示該名稱（含 `/rename`）；停在 sub-agent 時改顯示該 agent 標題；手動 tab 名稱優先
- 保留 10,000 行捲動歷史，啟用 IME 與系統提示音
- 關閉 pane 不確認；關閉 tab 或視窗需確認
