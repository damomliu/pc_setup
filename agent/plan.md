# Plan：4 Agents 指引分流與設定同步

狀態：Paul（Claude Opus／medium）於第 2／2 輪 review 達成共識（CONSENSUS: YES），Jason（Claude Sonnet／medium）已完成實作。244 項隔離測試斷言與真實 4 Agents 唯讀檢查均通過。本次未建立 issue、套用 triage 或覆寫真實使用者設定。

## Problem Statement

4 Agents 加入 pstack 後，Claude Code 與 Codex 的 global 指引已因載入方式與角色 model 設定而分歧。現行同步仍把同一份指引部署給兩種工具，且在 Pull 前要求兩種工具的指引完全相同，無法保存各自的設定。

日常在各環境調整 model、effort 時，這些本機選擇不應造成同步衝突，也不應在其他設定更新時被覆蓋。現行 Check 只有檔案狀態，無法直接看出受管設定的差異。

使用者需要在 repo 分別維護 Claude／Codex 的完整指引，同時讓設定比對忽略 key 排序，並提供可直接檢視差異的唯讀檢查模式。

## Solution

同工具的 Windows／WSL 共用一份完整指引；Claude／Codex 各自維護，可重複共同規則，不抽共用指引模板。

| Repo 來源 | Windows／WSL 部署目標 | 管理方式 |
| --- | --- | --- |
| `agent/config/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude 完整指引 |
| `agent/config/claude-pstack-models.md` | `~/.claude/pstack-models.md` | Claude pstack 設定，供指引引用與 hook 讀取 |
| `agent/config/AGENTS.md` | `~/.codex/AGENTS.md` | Codex 完整指引，直接包含全部 pstack 設定 |
| `agent/config/AGENTS.md` 的 pstack 區塊 | `~/.codex/pstack-models.md` | sync 產生的本機配套檔；不是另一份 repo 來源 |
| `agent/config/claude-settings.json` | `~/.claude/settings.json` | WSL 先合併既有 `claude-settings.wsl.json`；保留各目標的忽略欄位 |
| `agent/config/codex-config.toml` | `~/.codex/config.toml` | 沿用受管 key 合併方式，排除忽略欄位 |

Claude 指引使用 `@~/.claude/pstack-models.md`，移除 Windows／WSL 各自的絕對引用路徑。

初版採目前 Windows 的指引與 pstack 設定。同工具在 Windows／WSL 的一般規則目前一致；WSL Codex 部分角色 model 不同，依已確認決策收斂到 Windows 版本。

忽略欄位僅限下列設定檔的頂層 key：

| 工具 | 忽略欄位 | 仍受管的相關設定 |
| --- | --- | --- |
| Claude | `model`、`effortLevel` | `modelSettings.*.effortLevel` |
| Codex | `model`、`model_reasoning_effort` | 指引內的 pstack 角色、`default effort`、`session hook` |

忽略代表比對排除、推送保留目標原值、目標缺值時不補入、Pull 保留 repo 原值。套用範圍不延伸到其他檔案或巢狀同名 key。

## User Stories

1. 身為 4 Agents 維護者，我希望 Claude／Codex 各有完整指引來源，以便分別維護不同工具的規則。
2. 身為 4 Agents 維護者，我希望同工具的 Win／WSL 使用相同來源，以便減少跨環境的規則漂移。
3. 身為指引維護者，我希望可在兩份指引重複共同規則，以便直接閱讀與編輯完整內容。
4. 身為既有使用者，我希望初版保留目前 Windows 的規則與 pstack 選擇，以便遷移時不遺失已設定內容。
5. 身為 Claude 使用者，我希望 pstack 引用不包含特定 Windows 或 Linux 使用者路徑，以便同一份指引能部署到兩個環境。
6. 身為 Claude 使用者，我希望角色 model、default effort 與 hook 開關一併同步，以便重建完整 pstack 設定。
7. 身為 Codex 使用者，我希望直接在 AGENTS 指引管理全部 pstack 設定，以便只有一份人工維護來源。
8. 身為 Codex 使用者，我希望 sync 自動產生 hook 所需配套檔，以便不必手動維持重複設定。
9. 身為 Codex 使用者，我希望檢查模式能指出衍生配套檔的差異，以便確認實機是否符合指引來源。
10. 身為本機使用者，我希望各環境能自行選擇一般 model 與 effort，以便依當下工作調整。
11. 身為本機使用者，我希望只改忽略欄位時檢查仍顯示相同，以便減少無關衝突。
12. 身為本機使用者，我希望其他設定需要強制更新時仍保留忽略欄位，以便本機選擇不被順帶覆蓋。
13. 身為新環境使用者，我希望缺少忽略欄位時使用工具預設值，以便不被 repo 的歷史 model 選擇綁定。
14. 身為 repo 維護者，我希望 Pull 不收回忽略欄位，以便不把某一環境的選擇寫進 repo。
15. 身為 Claude 使用者，我希望 modelSettings 內的 effort 設定仍由 repo 管理，以便統一每個 model 的指定設定。
16. 身為設定維護者，我希望調整 object key 或 TOML section／key 排列不造成差異，以便排版變更不干擾同步。
17. 身為設定維護者，我希望 array 順序與實際設定值的變更仍被辨識，以便不漏掉有意義的差異。
18. 身為檢查者，我希望單獨使用 CheckVerbose 就能唯讀檢查，以便不需記住額外的 Check 參數。
19. 身為檢查者，我希望看到每個目標的設定路徑與本機／預期值，以便直接判斷應修改來源還是回收本機設定。
20. 身為檢查者，我希望看到指引的逐行差異，以便理解規則實際變動。
21. 身為檢查者，我希望敏感值被遮蔽、忽略欄位不出現在差異中，以便安心檢視輸出。
22. 身為操作人員，我希望檢查與寫入參數衝突時在任何寫入前失敗，以便避免誤操作。
23. 身為操作人員，我希望能從任一環境分別 Pull 兩種工具的指引，以便保留各工具的合法差異。
24. 身為 WSL-Claude 使用者，我希望沿用既有 overlay 與 Pull 限制，以便保留環境專屬設定的歸屬。
25. 身為同步腳本使用者，我希望總入口與個別同步器提供相同行為，以便可依需求一次或分別操作。
26. 身為 repo 維護者，我希望有隔離環境的行為驗證，以便測試同步而不改動真實使用者設定。

## Implementation Decisions

### 指引來源與遷移

- 修改總入口、Claude 同步器、Codex 同步器與部署文件；同步器的參數介面保持一致。
- 移除 Pull 前要求 Claude／Codex 指引內容完全相同的限制，兩種工具各自回收自己的來源。
- Claude 新增獨立完整指引與 pstack 來源；Codex 以完整指引作為唯一人工維護的 pstack 來源。
- 初版以 Windows 實機為準；Codex 角色與 default effort 取自 Windows 指引，既有 hook 開關由 Windows 配套檔補入指引。
- 不改 repo root 的 project 指引；完整 global 指引範本與 project 規則維持各自用途。
- 保留既有工作區修改，不順帶重寫使用者已修改的設定內容。

### Codex pstack 衍生檔

- 在完整指引內建立邊界明確的 pstack 區塊，包含角色 mapping、default effort 與 session hook。
- 推送時從該區塊產生本機配套檔，角色與 hook 設定均來自同一來源。產物保留 hook 可識別的設定行格式。
- 將產物納入同步計畫與 Check／CheckVerbose；檢查模式只計算預期內容，不建立或更新產物。
- Pull 以來源環境的完整指引為準，不以衍生配套檔反向覆寫指引。
- Codex Pull 寫入 repo 前，使用與推送相同的 parser 驗證來源指引的 pstack 區塊；缺少區塊或解析失敗時，該同步器不得寫入任何 repo 檔案。
- 不維護 repo 的第二份 Codex pstack 設定，也不沿用先前討論的雙份人工來源一致性檢查。
- pstack 區塊無法解析時，在該同步器寫入任何檔案前中止；不產生不完整配套檔。
- 未來其他工具若直接修改衍生檔，檢查會顯示差異；維護者應將要保留的設定寫回指引來源。

### 忽略欄位的雙向行為

- 使用明確的工具／設定範圍定義忽略清單，不能遞迴忽略所有同名 key。
- 推送先建立受管設定的預期結果，再保留每個目標各自的忽略欄位。即使使用 Force 更新其他欄位，也必須保留本機值。
- 本機缺少某個忽略欄位時，推送後仍不包含該欄位；首次建立設定檔時同樣不從 repo 補入。
- Pull 只回收受管部分；repo 已有的忽略欄位原值保留，repo 原本沒有的忽略欄位仍不新增。
- Claude 的巢狀 modelSettings effort 設定正常比對、推送與回收；一般設定的忽略規則不套用到 pstack。
- Claude 的 WSL overlay 維持 object 遞迴合併、permissions 陣列聯集與其他值覆寫的規則；合併結果仍須保留 WSL 目標自己的忽略欄位。
- WSL-Claude Pull 維持先檢查 settings 是否符合合併結果、符合才略過 settings 並回收其他檔案的行為；此檢查也排除忽略欄位。
- Codex 維持只管理 repo 已列出 key、保留本機其他 key 的方式；忽略欄位從受管範圍排除。
- 只有忽略欄位不同時視為 same，不因這些差異重寫檔案。

### 比對與差異輸出

- JSON 遞迴忽略 object key 排列與排版；array 保持順序，設定值與型別的差異仍須辨識。
- TOML 沿用依 section／key 查找受管值的方式，忽略其排列順序；維持既有格式支援範圍，不因本次需求導入通用 parser 或新依賴。
- 新增 CheckVerbose switch，總入口與兩個同步器都接受。單獨使用即包含 Check 行為，同時指定兩者仍為詳細唯讀檢查。
- 保留檔案狀態總覽；有差異時列出目標、受管 key 路徑與「本機 → repo 預期」值。WSL 預期值使用合併後結果。
- 指引與 pstack 文字內容顯示逐行差異，清楚區分本機與預期內容；缺少目標時明確標示 missing。
- 差異輸出排除忽略欄位並遮蔽敏感值，不能直接把整份使用者設定印出來。
- 遮蔽以設定路徑判定，大小寫不敏感：任一路徑段含 token、secret、password、auth、credential，或為 key／apiKey／api_key／api-key／accessKey／access_key／access-key／privateKey／private_key／private-key 時，其值與子樹一律顯示為 `***`；env 子樹內所有值也一律遮蔽。
- 上述遮蔽適用 JSON／TOML 設定差異與相關診斷訊息；指引、程式與 pstack 文字檔的逐行 diff 不作任意敏感文字推斷，來源檔仍須遵守不得保存 secrets 的規則。
- Check 與 CheckVerbose 均為唯讀。與任一 Pull 或 Force 混用時，在任何檔案 I/O 與 WSL 呼叫前拒絕；兩種 Pull 彼此仍互斥。
- 維持現有 differs 需要 Force 的保護，以及 Codex 僅缺受管 key 時可補入的行為。

### 實作順序

1. 建立 Claude 獨立指引與配套來源，補齊 Codex 指引內的 pstack 區塊；核對與 Windows 現況一致。
2. 調整兩個同步器的來源 mapping、Codex 產物生成與 Pull；移除總入口的跨工具一致性限制。
3. 完成忽略欄位在比對、推送、Force、首次建立與 Pull 的處理，驗證 WSL overlay 情境。
4. 加入 CheckVerbose、共用參數驗證與敏感值遮蔽，確認檢查不寫入。
5. 補齊整合驗證與部署文件，再執行實機唯讀檢查；實際覆寫本機設定另依操作授權處理。

## Testing Decisions

以同步腳本的 CLI 為主要測試 seam，驗證檔案產出、保留內容、檢查輸出與失敗時的寫入行為，不斷言私有 helper 的內部實作。

目前未找到同步器專用測試或 Pester 設定。採可由 PowerShell 7 執行、不需新增依賴的隔離整合測試；既有其他模組的測試只能作 repo 測試存在的參考，不沿用其不同工具鏈。

測試使用暫存 repo、Windows home 與 WSL home fixtures。總入口與兩個同步器都提供隱藏的測試專用參數 `-TestWinHome`、`-TestWslRoot`，必須成對指定；指定時跳過 WSL HOME 查詢，兩個目標只由測試路徑解析，其餘同步流程走正式程式。未指定時沿用正式環境的路徑解析。這個測試 seam 不代表新增 CODEX_HOME／CLAUDE_CONFIG_DIR 的產品功能；不得重設系統 HOME，也不得為測試覆寫真實使用者設定。

| 情境 | 可觀察的驗收結果 |
| --- | --- |
| 不同工具有不同指引 | 各部署至自己的目標；Pull 不再因跨工具內容不同而中止 |
| 同工具部署 Win／WSL | 指引內容相同，Claude 引用不含環境專屬絕對路徑 |
| Claude pstack 同步 | 兩環境收到完整角色、default effort 與 session hook |
| Codex pstack 生成 | 指引與衍生檔的角色、default effort、session hook 對應一致；不需 repo 第二份來源 |
| Codex pstack 區塊無法解析 | 同步失敗，該同步器未寫入任何目標 |
| Codex Pull 來源 pstack 區塊缺少或無法解析 | Pull 失敗，該同步器的所有 repo 檔案均不變 |
| Codex 衍生檔遭單獨修改 | CheckVerbose 顯示差異，Pull 不用產物覆蓋指引 |
| 只有忽略欄位不同 | 顯示 same，檢查與正常同步均不改寫檔案 |
| 受管欄位不同並使用 Force | 受管內容更新，Win／WSL 各自的忽略欄位逐值保留 |
| 忽略欄位部分缺少或整檔不存在 | 推送不補入缺少的忽略欄位，其餘受管內容可建立 |
| Pull 時忽略欄位不同或缺少 | repo 的忽略欄位維持原狀，受管欄位依既有回收規則處理 |
| Claude 巢狀 effort 不同 | 被辨識為差異，推送與 Pull 均正常處理 |
| WSL overlay 與本機忽略欄位同時存在 | overlay 正確合併，本機忽略欄位保留；僅忽略欄位不同不阻擋 PullWsl |
| JSON object key 遞迴換序／改排版 | 顯示 same |
| TOML section／受管 key 換序 | 顯示 same |
| array 換序或受管值／型別改變 | 顯示差異，不被排序正規化消除 |
| Codex 本機額外 key | 推送、檢查與 Pull 維持既有受管邊界 |
| 單獨 CheckVerbose | 列出總覽、設定與文字差異，來源與目標 bytes 及修改時間不變 |
| 目標缺少或內容已相同 | 分別顯示 missing／same，不因詳細模式產生檔案 |
| 忽略欄位與模擬敏感值 | 忽略欄位不列出；在 env.X、名稱含 token 的 key 與巢狀敏感路徑放入不同測試字串，均不出現在 stdout／stderr／診斷訊息；一般 keymap 等非敏感設定仍可顯示差異值 |
| Check／CheckVerbose 混用 Pull 或 Force | 在任何寫入前失敗，repo 與兩個目標均不變 |
| 兩種 Pull 同時指定 | 拒絕執行，不寫入 |
| 成對或單獨提供測試專用路徑 | 成對時完全不呼叫 WSL、不存取真實 home；單獨提供時在 I/O 前拒絕 |
| 直接呼叫同步器與使用總入口 | 相同參數得到一致行為；總入口第一個同步器失敗後不執行第二個 |

測試通過後，再對真實 4 Agents 執行唯讀 CheckVerbose，確認路徑解析與輸出可用。實機本來存在差異不代表測試失敗，需以差異是否符合來源與忽略規則判斷。

## Out of Scope

- 共用指引模板、共同規則自動合併，或跨工具指引必須一致的限制。
- 在 repo 維護獨立 Codex pstack 配套來源，或要求人工同步兩份角色設定。
- 將 Claude modelSettings 內的 effort 設定加入忽略清單。
- 將一般 model／effort 忽略機制延伸到 pstack 角色、default effort 或 session hook。
- 改寫 pstack plugin、本次重新選擇角色 model，或更改已採用的 Windows 初版設定。
- 完整 TOML 語法支援、與 key 排序無關的所有語法等價正規化，以及新增套件依賴。
- 改變既有 WSL settings 回收限制、環境專屬 overlay 的歸屬，或擴充自訂 home／config 環境變數支援。
- 為兩個同步器新增跨工具的 transaction／rollback 保證。
- 自動覆寫實機設定、修改 credentials／.env、執行 git push，或處理既有不相關工作區變更。
- 發布 issue、建立 triage label，或要求建立 repo 規劃慣例。

## Further Notes

- 本 Plan 以對話中最後確認的設計為準：Codex pstack 直接放 AGENTS 指引，本機配套檔由 sync 產生；早先「repo 另存 Codex 配套檔並比對兩份來源」的提議已被取代。
- WSL 指引已由使用者指定的 gpt-6-luna sub-agent 唯讀查核。Claude pstack 設定與 Windows 一致；Codex 部分單一角色與 panel model 不同，初版依決策採 Windows。
- 查核確認兩環境的 pstack default effort 為 session，session hook 為 off；遷移時需保留。
- 初版來源必須在實作時重新讀取並核對，不能把較早的查核摘要當作實機檔案永久不變的保證。
- 新增的指引檔位於 repo 子目錄，也會成為工具在該目錄工作的 project 指引；內容應維持可直接載入的完整規則。
- 部署文件需同步更新來源對照表、忽略欄位清單、CheckVerbose 用法、Codex 產物管理方式，以及 Pull 的新行為。
- Paul（Claude Opus／medium）第 1 輪 review 的三項 must-fix 已納入：明確的隔離測試路徑、可驗收的設定遮蔽規則、Codex Pull 寫入前的來源區塊驗證。Review 上限為兩輪。
- Paul 第 2／2 輪已確認無剩餘 must-fix，CONSENSUS: YES；不再追加 review 輪次。
- Plan 建立時只新增文件；程式與來源指引的實作由 Jason 接手，真實 4 Agents 設定以唯讀檢查驗證。

## 實作狀態

Jason（Claude Sonnet／medium）已完成實作：`CLAUDE.md`、`claude-pstack-models.md`、`AGENTS.md` pstack 區塊、`sync-common.ps1`、三支同步腳本、`test-sync.ps1`（`pwsh -NoProfile -File ai-agent/test-sync.ps1`）與 `ai-agent.md`。真實 4 Agents 的唯讀 `.\sync.ps1 -CheckVerbose` 也已完成；本次未執行真實設定覆寫。

驗證結果：`pwsh -NoProfile -File ai-agent/test-sync.ps1` 原始 exit code 0，輸出「全部通過（244 項斷言）」；真實 Windows＋WSL 唯讀 `.\sync.ps1 -CheckVerbose` 已確認 16 個目標可解析（8 same／8 differs，尚未部署），來源與目標檔未被改動。實作完成；真實設定的部署仍待使用者授權。
