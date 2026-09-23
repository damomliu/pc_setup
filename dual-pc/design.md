# 雙螢幕、雙電腦切換設計

## 目標與原則

- 優先確保狀態可靠，其次才是減少操作。
- profile 是宣告式目標狀態；每次執行都重新套用，不以記憶狀態跳過軟體設定。
- PC 是唯一 coordinator。PC、NB 都能使用相同熱鍵，但 NB 只將要求送至 PC。
- PC 無法使用時降級為手動操作，不實作 coordinator 選舉或自動接管。
- LG34 無法由軟體切換輸入源，HDMI 與實體鍵鼠仍由使用者手動切換。

## 設備與網路

- LG34：HDMI1 接 NB，HDMI2 接 PC。
- NB：`192.168.16.54`
- PC：`192.168.16.85`
- SSH 控制與 Spacedesk 影像皆走 `192.168.16.*` 內網。
- 建議由路由器建立 DHCP reservation，不直接在 Windows 網卡設定靜態 IP。
- 離開此內網時不自動改走 Tailscale 或網際網路，profile 系統應回報不在受支援網路。
- 兩台電腦各建立限定 peer 內網 IP 的 TCP 22 SSH 規則，避免 Windows 網路類型不同導致內網 SSH 無法連線；既有的一般 SSH 規則不由本方案修改。
- Spacedesk Driver 常駐於 PC。安裝器記錄並停用 Spacedesk 原本的廣泛允許規則，Windows Firewall 僅允許 NB 的可信位址連入 TCP 28252；卸載時還原原規則。

IP 的唯一設定來源為 `dual-pc/config.psd1`。IP 改變時只修改該檔案的 `PC.IP` 或 `NB.IP`，再重新執行部署腳本；不要直接修改排程工作或已部署副本。

## Profile

### profile-PC（Ctrl+Alt+F9）

- LG 使用 HDMI2。
- LG 是 PC 主螢幕。
- NB 的 Spacedesk Viewer 自動連線至 PC 並全螢幕。
- NB 作為 PC 的延伸螢幕，不使用鏡像。
- 完整停用兩台電腦的 Mouse Without Borders 模組。
- 從 NB 或 unknown 狀態進入時，提示將 LG 與實體鍵鼠切到 PC。

### profile-mix（Ctrl+Alt+F10）

- LG 使用 HDMI2，作為 PC 主螢幕。
- 終止 NB 的 Spacedesk Viewer。
- NB 僅使用內建螢幕，並以內建螢幕為主螢幕。
- 啟用兩台電腦的 Mouse Without Borders 模組。
- PC 與 mix 互切時不提示切換 LG。
- 從 NB 或 unknown 狀態進入時，提示將 LG 切至 HDMI2，並將實體鍵鼠切到 PC。

### profile-NB（Ctrl+Alt+F12）

- LG 使用 HDMI1。
- 終止 NB 的 Spacedesk Viewer。
- NB 使用延伸桌面，LG 是主螢幕，NB 內建螢幕是延伸螢幕。
- 完整停用兩台電腦的 Mouse Without Borders 模組。
- 鎖定 PC，但不強制變更 PC 的顯示拓撲。
- 提示將 LG 切至 HDMI1，並將實體鍵鼠切到 NB。
- 返回 PC 或 mix 時，主要從 NB 發出熱鍵；完成後再切換 LG、鍵鼠並視需要解鎖 PC。

## 強制重新套用

- `Shift + profile 熱鍵` 強制重新套用所有軟體狀態，並一律提示正確的 HDMI 與鍵鼠位置。
- PC 可記錄最後一次成功下達的 profile，但此紀錄不代表 LG 的實際輸入源，也不可用來省略軟體設定。
- 開機、登入、喚醒、網路重連或部分失敗後，狀態一律視為 unknown。
- unknown 狀態第一次切換必須提示 HDMI 與鍵鼠位置，但不要求使用者再按確認。

## 協調與執行模型

- PowerShell 7 負責安裝、協調、切換、診斷與記錄。
- AutoHotkey v2 只註冊熱鍵並呼叫 PowerShell，不保存流程邏輯。
- Windows SSH 命令不直接操作 GUI。兩台電腦各建立三個「僅在指定使用者登入時執行」的互動式排程工作。
- SSH 只提交 profile 要求並啟動排程工作；Viewer、PowerToys 與顯示模式由登入桌面的排程工作操作。
- 排程工作使用固定登入帳號及一般權限，避免重新啟動 PowerToys 時意外提升其權限。只有安裝、ACL 與防火牆設定需要系統管理員權限。
- 已部署的腳本目錄只允許 Administrators 修改，一般執行帳號僅需讀取與執行。
- 安裝時可要求一次系統管理員權限；日常切換不得出現 UAC。
- 只支援指定帳號的本機 console session。偵測到 RDP 或多重互動 session 時拒絕切換。

每個要求必須帶唯一 request ID。遠端工作將最終結果寫入結果檔，發起端輪詢結果；成功啟動排程工作不等於 profile 已成功套用。

所有要求都由 PC coordinator 取得同一個全域 mutex。切換期間收到的新要求直接拒絕並顯示「正在切換」，不排隊也不覆蓋。

排程工作的 `MultipleInstances=Queue` 只用來避免 worker 正在退出時遺失新的喚醒訊號；profile 要求本身仍由 busy marker 與全域 mutex 拒絕並行，不形成操作佇列。登入 trigger 只負責接續登入前已持久化的要求。

## 建議切換順序

1. 確認目前是受支援的 console session 與內網。
2. 確認 NB 可連線及必要元件就緒。
3. 套用 NB 的 Viewer、顯示模式與 Mouse Without Borders 狀態。
4. 驗證必要的 NB 步驟。
5. 套用 PC 的顯示、Mouse Without Borders 與鎖定狀態。
6. 寫入結果與紀錄。
7. 在即將操作的電腦顯示成功通知或人工切換指示。

關閉 Mouse Without Borders 必須安排在遠端命令已安全提交之後，避免流程尚未完成便失去控制。

## Spacedesk

- Viewer 預先啟用「自動連線」與「連線後全螢幕」。
- PC profile 啟動 Viewer，最多等待 15 秒。
- mix 與 NB profile 終止 Viewer，避免自動重連。
- 不使用依賴螢幕座標的 UI 自動化。
- PC profile 的可驗證成功條件：
  - Viewer 程序存在。
  - PC 偵測到 Spacedesk 虛擬顯示器。
  - Viewer 在等待期間未提前退出。
- 全螢幕由 Viewer 預設設定保證，不列為可機器驗證的必要條件。

## Mouse Without Borders

- mix profile 完整啟用模組。
- PC 與 NB profile 完整停用模組，包括越界切換、共享剪貼簿及其他切換途徑。
- 使用目前 PowerToys 安裝包隨附且簽署的 DSC module 所採用之 `PowerToys.Settings.exe` 設定橋接，不依賴 WinGet Configuration、Microsoft Store 或座標式 UI 操作。

## 失敗、逾時與通知

- 一般遠端子步驟逾時 10 秒並自動重試一次；SSH 連線逾時 5 秒，包含顯示與 PowerToys 操作的完整遠端工作最多等待 60 秒。
- 完整 profile 要求最多等待 120 秒。
- Spacedesk 連線最多等待 15 秒。
- 必要步驟失敗即停止，不繼續提示使用者切換 LG。
- 不自動 rollback；應列出已完成與失敗步驟，並將狀態標為 unknown。
- 修正問題後可使用強制熱鍵重新套用。
- 不需要人工操作時顯示「已套用 profile-X」。
- 需要人工操作時顯示「軟體已就緒」，並列出 LG HDMI 與鍵鼠的目標位置，不宣稱整體切換已完成。
- PC／mix 的最終通知顯示於 PC；NB 的最終通知顯示於 NB。
- 命令失敗時，發起熱鍵的電腦也必須顯示錯誤。

## 記錄與安全

- 兩台電腦各保存本機結構化 log，記錄 request ID、profile、步驟、耗時、結果與錯誤。
- log 保留最近 30 天。
- 不記錄 SSH 私鑰、Mouse Without Borders 安全金鑰或其他祕密。
- profile 控制使用獨立 SSH 金鑰、peer 來源 IP 限制與受限命令，只允許提交三個既定 profile、執行必要的 peer 本機步驟及重設 unknown 狀態。
- 日常 SSH 金鑰與設定不受影響。
- SSH 私鑰與 Mouse Without Borders 安全金鑰不得加入 Git 或部署包。

## 安裝、診斷與卸載

- 提供可重複執行的安裝腳本，建立排程工作、AutoHotkey 熱鍵、SSH 受限命令、記錄目錄、權限與必要檢查。
- `pc_setup` 專案是腳本與設定的唯一來源；部署至兩台電腦的固定受保護位置，不依賴即時同步資料夾。
- 提供 `diagnose` 模式，只檢查 SSH、排程工作、PowerToys、Spacedesk、Viewer 設定、顯示器與防火牆，不改變狀態。
- 軟體更新後先執行 `diagnose`。必要設定或程序名稱不相容時應明確失敗，不盲目切換。
- 提供卸載腳本，只移除本方案建立的熱鍵、排程工作、SSH 受限金鑰、規則與紀錄。
- 卸載不得移除 PowerToys、Spacedesk、AutoHotkey 或日常 SSH 設定。

## 不納入第一版

- 不自動切換 LG 輸入源。
- 不管理應用程式視窗位置。
- 不支援 PC coordinator 自動接管或主從選舉。
- 不在內網不可用時自動改走其他網路。
- 不在睡眠或喚醒後自動切換 profile。

## 驗收範圍

- 六種跨 profile 轉換。
- 三種重複套用。
- 開機後 unknown 分別切至三種 profile。
- NB 離線、Viewer 失敗及切換中重按熱鍵。
- 睡眠或喚醒後重新套用。
- 強制重新套用。
- 安裝腳本重複執行。
- 卸載後確認既有應用程式與日常 SSH 設定未受影響。
