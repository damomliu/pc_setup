# WezTerm 設定

實際載入的設定是 `~/.wezterm.lua`；本資料夾的 `wezterm.lua` 為副本。

## 快速鍵設定

- `Alt+Z`：切換 pane zoom
- `Alt+]` / `Alt+[`：維持 zoom，切換下一個／上一個 pane
- `Alt+1`～`Alt+9`：維持 zoom，切換至指定 pane
- `Alt+方向鍵`：維持 zoom，切換至該方向的 pane
- `Alt+Shift+方向鍵`：調整 pane 大小
- `Ctrl+PageUp` / `Ctrl+PageDown`：上一個／下一個 tab

Prefix 為 `Ctrl+B`（按下後有 2 秒可接下一鍵）：

- `Prefix, \`：左右分割 pane
- `Prefix, -`：上下分割 pane
- `Prefix, X`：直接關閉 pane
- `Prefix, C`：建立 tab
- `Prefix, W`：關閉目前 tab（會先確認）
- `Prefix, N` / `Prefix, P`：下一個／上一個 tab
- `Prefix, 1`～`Prefix, 9`：切換至指定 tab
- `Prefix, Shift+1`～`Prefix, Shift+9`：把目前 pane 移到 tab 1～9；該 tab 不存在則開新 tab；移入後會均分欄寬，避免和原 pane 重疊而選不到
- `Prefix, ,`：命名 tab；清空可恢復自動標題
- `Prefix, Q`：在各 pane 上顯示編號；若有 pane 被擠成 0 寬／高會先救回來再顯示
- `Prefix, L`：開啟啟動選單
- `Prefix, S`：選 pane 並與目前 pane 對調位置；對調後 focus 跟著移到目標位置

Ubuntu Prefix 為 `Ctrl+U`（按下後有 2 秒可接下一鍵）：

- `Ctrl+U, C`：建立 Ubuntu tab
- `Ctrl+U, \`：建立左右分割的 Ubuntu pane
- `Ctrl+U, -`：建立上下分割的 Ubuntu pane

其他：

- `Ctrl+Shift+P`：命令面板
  - 搜 `RyokoTower`：七個模擬器，佈局相同
    - `RyokoTower Simulators (新分頁)`：在目前視窗開一個 tab
    - `RyokoTower Simulators (新視窗)`：開一個新視窗；等它最大化、格子尺寸跟上來源視窗後才切 pane，再均分欄寬與列高
  - 搜 `sync`：把目前 pane 的輸入列送到同 tab 其他 pane
  - 搜 `close`：關閉目前 tab
  - 搜 `equal`：平均分配欄寬（僅同列／Tab）、欄高（僅同欄／Tab）、或欄寬高（Tab）；寬依每一列（含通高 pane）、高依每一欄；移動的是相鄰 pane 真正共用的那條分割線；若該 tab 的 mux 尺寸沒跟著視窗縮放，會改依視窗實際寬高均分
- `Ctrl+Shift+U` / `Ctrl+Shift+D`：向上／向下翻頁
- `Ctrl+Shift+F`：搜尋終端內容
- `Ctrl+滑鼠左鍵`：開啟連結
- 選取文字即複製；滑鼠右鍵貼上


## 其他設定

- 預設 shell：PowerShell 7
- 啟動選單：PowerShell 7、Ubuntu 24.04（進 Linux home）、Git Bash、Command Prompt、SSH `nb`
- 配色：Catppuccin Mocha
- 字型：Sarasa Term TC Nerd Font 11 pt
- 啟動時最大化；永遠顯示 tab bar
- 降低非作用中 pane 的亮度與飽和度
- Tab 自動顯示編號、程序、資料夾與 pane 位置 `(目前/總數)`；zoom 時為 `(目前/總數Z)`
- Claude session 有名稱時，tab 與視窗標題顯示該名稱（含 `/rename`）；停在 sub-agent 時改顯示該 agent 標題；手動 tab 名稱優先
- 保留 10,000 行捲動歷史，啟用 IME 與系統提示音
- 關閉 pane 不確認；關閉 tab 或視窗需確認