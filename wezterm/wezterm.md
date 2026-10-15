# WezTerm 設定

實際載入的設定是 `~/.wezterm.lua`；本資料夾的 `wezterm.lua` 為副本。

## 快速鍵設定

已套用至 `.lua` 並同步至 `~/.wezterm.lua`。Prefix 使用 `Ctrl+G`；已解除 `Alt+Z`、`Alt+方向鍵`、`Alt+Shift+方向鍵` 的一般模式綁定，讓按鍵傳入 Herdr。

已用 `DisableDefaultAssignment` 解除 `Ctrl+Alt+Shift+方向鍵` 的預設 `AdjustPaneSize`，讓 Herdr 接收並交換該方向的 pane 位置。

主要 pane／tab 操作交給 Herdr，WezTerm 保留外層管理功能。Herdr 的配置共識見 [herdr.md](herdr.md)。`Ctrl+Space` 保留給中文輸入法，不作為 prefix。

這些 Alt 快速鍵還需要將 `herdr-config.toml` 的 `[keys]` 合併至 `%APPDATA%\herdr\config.toml`，再執行 `herdr server reload-config`；只解除 WezTerm 綁定不會自動建立 Herdr 綁定。

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
- 啟動時最大化；永遠顯示 tab bar
- 降低非作用中 pane 的亮度與飽和度
- Tab 自動顯示編號、程序、資料夾與 pane 位置 `(目前/總數)`；zoom 時為 `(目前/總數Z)`
- 視窗標題為 `[Z] [目前 tab/tab 總數] 標題`；`[Z]` 僅 zoom 時顯示，`[目前 tab/tab 總數]` 僅多於一個 tab 時顯示
- Claude session 有名稱時，tab 與視窗標題顯示該名稱（含 `/rename`）；停在 sub-agent 時改顯示該 agent 標題；手動 tab 名稱優先
- 保留 10,000 行捲動歷史，啟用 IME 與系統提示音
- 關閉 pane 不確認；關閉 tab 或視窗需確認
