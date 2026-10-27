# GPT / Claude 模型特性整理（Team Nexense 派工參考）

查詢日期：2026-10-27。

**來源可信度**

- Claude：Anthropic 官方文件（platform.claude.com、anthropic.com），已核實。
- GPT：模型 ID、基本規格、價格與 API 限制已依 OpenAI 官方文件核對。效能結論須附評測條件。
- 第 4 節為團隊派工建議；角色對等與跨家族 review 的效果仍需以團隊任務驗證。

## 1. 總表

| 家族 | API ID | 定位 | 價格 in / out（USD / MTok） | Effort 範圍（預設） | Context / Max out |
|---|---|---|---|---|---|
| Claude | `claude-fable-5-1` | 最強；長程 agent、深度研究 | $10 / $50 | low–max（high） | 1M / 128K |
| Claude | `claude-opus-5-5` | 官方預設推薦；長時間 agentic coding | $4 / $20 | low–max（medium） | 1M / 128K |
| Claude | `claude-sonnet-5-5` | 速度與智力平衡；日常 coding | $2 / $10 | low–max（high） | 1M / 128K |
| Claude | `claude-haiku-5-5` | 最便宜最快；高量、subagent | $0.10 / $0.50（≤100K prompt） | low–max（medium） | 1M / 128K |
| GPT | `gpt-6-astra` | 旗艦；最難的推理 / 資安 / 科學 | $10 / $50 | low–max；不支援 none | 1.05M / 128K |
| GPT | `gpt-6.1-sol` | 中階主力；複雜 coding / agent | $2 / $10 | low–max（medium），無 none | 1.05M / 128K |
| GPT | `gpt-6.1-terra` | 視覺推理、精準 computer use、定界 code fix、自然寫作 | $1 / $5 | none–max（medium） | 1.05M / 128K |
| GPT | `gpt-6-sol` | 6.1 Sol 前一版 | $2 / $10 | none–max（medium） | 1.05M / 128K |
| GPT | `gpt-6-luna` | 便宜、高量、明確任務 | $0.10 / $0.50 | none–max（medium） | 1.05M / 128K |

REF：GPT 價格列為 Standard、未快取的 input 與 output 單價；長 context、cache 與速度模式另計。API 預設 effort 與 Codex UI 的預設設定須分別確認。

補充：

- Claude 全系列 adaptive thinking，knowledge cutoff 2026-06。Fable 5.1 / Opus 5.5 的 thinking 不能關。
- GPT knowledge cutoff：Astra、6.1 Sol 為 2026-04-30；6 Sol 為 2026-04-20；Luna 為 2026-05-18；Terra 為 2026-06-01。[來源][gpt-models]
- GPT 的 `low–max` 代表 `low`、`medium`、`high`、`xhigh`、`max`；6 Sol、Luna、6.1 Terra 另支援 `none`。所列 GPT 模型的支援清單均未包含 `minimal`。[來源][gpt-guide]、[Terra 規格][gpt-terra]
- GPT-6.1 Sol 與 GPT-6.1 Terra 的 prompt 超過 272K input tokens 時，整筆 request 的 input 與 cache rates ×2、output ×1.5。[Sol 規格][gpt-sol-61]、[Terra 規格][gpt-terra]
- 兩家的 effort 名稱相同但**不等價**，同名 effort 在不同模型思考量不同，不能直接搬設定。

## 2. Claude (Anthropic)

### Fable 5.1 — 最強，但不一定最適合寫 code

- **強項**：數小時的長程 agent、多步驟研究、從問題做到完成的文件 / 試算表 / 簡報、1M context 跨檔關聯、視覺（密集圖表、PDF 表格）。
- **注意**：
  - 第三方數據顯示 Terminal-Bench 4.0 上 Opus 5.5（66.4%）高於 Fable 5.1（55.8%）⚠️。純 coding 不必優先選它。
  - 平行 tool call 比前代少，agent loop 容易一回合只做一件事，變慢變貴。
  - 小改動傾向整檔重寫；摘要時可能未標註直接引用原文。
  - 不支援 ZDR，資料保留 30 天。
- **官方建議**：先用 Opus 5.5；Opus 在 xhigh / max 仍不夠時才升 Fable 5.1。

### Opus 5.5 — 預設主力

- **強項**：多小時自主 coding、大型重構、複雜系統工程、code review、判斷力要求高的開放式任務。FrontierCode 54.4%、CursorBench 57.8%，多數 benchmark 領先 Sonnet 5.5。
- **注意**：
  - 預設 effort 從 Opus 5 的 high 改成 **medium**；同 effort 下思考量比前代多。
  - 不支援強制 tool use（`tool_choice: any/tool` 會 400）。
  - tool call 之間的進度文字改放在 thinking block，UI 可能看起來「靜默」。

### Sonnet 5.5 — 性價比主力

- **強項**：修 bug、快速理解 codebase、批次 tool call 省步驟；Terminal-Bench 4.0 70.6% **高於 Opus 5.5**。文件 / 簡報 / UI 產出品質好。
- **官方定位**：實作 Opus 5.5 定好的架構或計畫、範圍明確的日常任務。
- **注意**：
  - 開放式、需要持續判斷的工作，Opus 5.5 仍明顯較強。
  - **不要開 max effort**：官方提到 max 反而比 xhigh 分數低，額外的 subagent review 造成 timeout 或改到範圍外。

### Haiku 5.5 — 便宜快速的 subagent

- **強項**：摘要、compaction、分類、資料查詢、從文件抽特定數字；首個可調 effort 的 Haiku。成本約 Haiku 4.5 的四分之一。
- **注意**：
  - 複雜 agentic coding 明顯較弱（Terminal-Bench 4.0 39.2%，Sonnet 5.5 為 70.6%）。
  - 只適合切得很細、驗收條件明確的 ticket。
  - 資安相關請求擋得比前代嚴（pentest 類會拒絕）。

## 3. GPT (OpenAI)

### GPT-6 Astra — 旗艦，貴

- **官方定位**：最強能力的旗艦，涵蓋複雜推理、coding、computer use、研究與文件工作。[來源][gpt-models]
- **成本**：Standard、未快取的 input 與 output token 單價為 6.1 Sol 的 5 倍；此比例不代表每個任務的總成本比例。[來源][gpt-models]
- **團隊建議**：用於高難度、需求模糊或需要持續判斷的任務；是否作為日常主力，取決於品質要求、時間與成本預算。[參考][gpt-selection]

### GPT-6.1 Sol — GPT 側預設主力

- **官方定位**：在複雜 coding、computer use 與專業工作上接近 Astra，成本較低；Codex 推薦用於複雜 coding 與 agentic workflows。[來源][gpt-sol-61]、[Codex 模型指引][codex-models]
- **評測範圍**：官方在 DeepSWE 1.1 報告其表現與 Astra 相當、成本約為五分之一。這是特定評測結果，不能推論所有 coding 任務皆相當，或每次均節省相同比例成本。[來源][gpt-sol-61-launch]
- **注意**：
  - 不支援 `none`、`minimal`；GPT-6 Sol 支援 `none`，其支援清單沒有 `minimal`。[來源][gpt-sol-61]、[6 Sol 規格][gpt-sol]
  - Tool calling 必須使用 Responses API；Chat Completions 僅支援不含 tools 的請求。[來源][gpt-sol-61]
  - 官方 Respecting Warnings 評測中，unwanted persistence 為 23.5%，Astra 為 17.4%。該評測主要測試日常低風險限制，且未啟用防止繞過的 system-level controls；數值不代表日常使用失敗率。[來源][gpt-sol-61-safety]
  - Review 時仍需核對完成證據、實際 diff 與授權範圍；這是團隊對所有實作角色的要求。
- **effort 建議**：API 預設 `medium`。官方 model-selection 指引以 medium 對應複雜技術工作與待修訂交付物，xhigh 對應定稿交付物及從矛盾證據下決策；這些是起點，須以實際任務驗證。[來源][gpt-sol-61]、[Model selection][gpt-selection]

### GPT-6.1 Terra — 視覺 / 操作 / 精準局部修改的中階選項（新增）

- **官方定位**：快速且高效率的視覺推理、精準 computer use，以及清楚自然的寫作；典型任務包括比對產品圖片、閱讀技術圖面、操作應用程式畫面、撰寫與修訂文字。[Terra 規格][gpt-terra]、[官方介紹][gpt-terra-launch]
- **Coding 適用範圍**：適合需求和驗收條件明確的 scoped code fixes、UI / 畫面問題修正、指定檔案或指定函式修改；大型跨模組架構或複雜長程 coding 優先考慮 6.1 Sol / Astra。[Model selection][gpt-selection]、[官方介紹][gpt-terra-launch]
- **事實錯誤評測**：官方內部難題集在 `low` effort 下錯誤率由前代的 53.6% 降至 16.7%；在 `max` effort 下為 4.3%。該數字不是普遍 hallucination rate。[官方介紹][gpt-terra-launch]
- **API 規格**：`gpt-6.1-terra`；1,050,000 context / 128,000 max output；knowledge cutoff **2026-06-01**；支援 `none`、`low`、`medium`（API 預設）、`high`、`xhigh`、`max`；文字輸入輸出、圖片輸入，不支援音訊及影片模態。[Terra 規格][gpt-terra]
- **工具與限制**：支援 function calling、structured outputs、web/file search、computer use、code interpreter、hosted shell、apply patch 等；**含工具呼叫必須使用 Responses API**。不支援 fine-tuning。[Terra 規格][gpt-terra]
- **effort 建議（團隊起始值，非官方最佳化保證）**：畫面對照、明確的 UI / XAML fix 或單點 Bug：`medium`；需要檢查多個狀態或回歸測試：`high`；提取 / 簡單文案可比較 `low`。只有困難案例再測 `xhigh` / `max`。
- **派工驗收**：提供可重現步驟、輸入截圖或技術圖、受影響檔案、允許修改範圍、測試指令；回報應包含 diff 與實際測試結果，不能只接受模型的完成宣告。[Model selection][gpt-selection]

### GPT-6 Luna — 便宜高量

- **官方定位**：高效率、範圍明確且高量的工作，包括摘要、抽取與 focused coding。[來源][codex-models]
- **注意**：
  - 是否適合任務應以驗收結果判斷，不能將不同 effort、版本或工具配置的分數直接當作能力排序。
  - GPT-5.6 Luna 與 GPT-6 Luna 是不同版本，引用評測時須確認完整 model ID。
  - 支援 `none`；Chat Completions 的 function calling 僅支援 `reasoning_effort: "none"`，含 reasoning 的 tool calling 使用 Responses API。[來源][gpt-luna]
- **effort 建議**：API 預設 `medium`；Codex 模型指引建議 Luna 從 high 開始。抽取、分類等明確任務可另比較 low 或 medium，以標註樣本驗證品質與成本。[來源][gpt-luna]、[Codex 模型指引][codex-models]、[Model selection][gpt-selection]

## 4. Team Nexense 角色對照與建議

以下為團隊策略與起始設定；角色對等不代表不同模型已在相同條件下證實能力相等。API 預設 effort、Codex UI 可選項與團隊建議值須分別確認。

| 角色 | 目前設定 | 評估 | 建議 |
|---|---|---|---|
| PM | claude-opus | 合適：規劃、判斷力強 | 寫 spec / 拆票時 effort 提到 high |
| MissWu | gpt-astra / medium | 建議：高難度、需求模糊、需持續判斷的任務 | 明確指定 `gpt-6-astra`；依驗收結果比較 medium、high 或 xhigh |
| QA | gpt-sol / high | 合適：跨家族 review Claude 寫的 code，盲點互補 | 指定 `gpt-6.1-sol` |
| ShiFu | claude-opus | 合適：多檔、架構性、需判斷的 ticket | 預設 medium，困難票 high |
| PRO | claude-sonnet | 合適：範圍明確的實作、修 bug | 預設 high，避免 max |
| SLAVE | claude-haiku | 僅適合小而明確的 ticket | 每票限單一檔案或單一函式、附驗收指令 |
| QA2 | claude-opus | 建議：跨家族 review GPT 寫的 code | 核對完成證據、實際 diff 與授權範圍 |
| PRO2 | gpt-sol | 建議：複雜 coding 與長任務；與 PRO 分工仍需實測 | 指定 `gpt-6.1-sol`，medium 起始；局部 / 視覺任務可比較 Terra |
| PRO-Terra（可選；非既有角色）| **未設定** | 專責圖面 / UI / scoped code fix；介於 PRO2 與 SLAVE2 的任務範圍 | |
| SLAVE2 | gpt-luna | 建議：範圍明確、可重複驗收的任務 | 指定 `gpt-6-luna`；coding 用 high 起始；反覆失敗則比較 Terra |
| 秘書 | gpt-6.1-sol / medium | 合適：調查、雜項 | 需要定稿的調查報告可升 xhigh；明確圖面/表單可評估 Terra |

派工通則：

- **ticket 難度 → 人選**：架構 / 跨模組 → ShiFu；範圍明確的功能或 bug → PRO / PRO2；機械式小改 → SLAVE / SLAVE2。
- **比較 model 與 effort**：以代表性任務比較不同設定，選擇達到品質要求的最低成本組合；不要求先提高 effort 才能換模型。[參考][gpt-selection]
- **跨家族 review**：維持 TeamA（Claude 寫、GPT 審）與 TeamB（GPT 寫、Claude 審）作為團隊策略，以實際缺陷發現與修正結果驗證互補效果。
- **共同驗收**：所有實作角色都需提供完成證據，review 對照實際 diff、測試結果與授權範圍。

## 5. 來源

Anthropic 官方：

- [Models overview](https://platform.claude.com/docs/en/models/overview)
- [Choosing a model](https://platform.claude.com/docs/en/about-claude/models/choosing-a-model)
- [What's new in Claude Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1)
- [What's new in Claude Opus 5.5](https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5)
- [Introducing Claude Sonnet 5.5](https://www.anthropic.com/claude-sonnet-5-5)
- [Introducing Claude Haiku 5.5](https://www.anthropic.com/claude-haiku-5-5)

OpenAI 官方（GPT 規格與建議的主要依據）：

- [Models][gpt-models]
- [Pricing][gpt-pricing]
- [GPT-6.1 Sol model][gpt-sol-61]
- [GPT-6.1 Terra model][gpt-terra]
- [GPT-6 Luna model][gpt-luna]
- [Using GPT-6][gpt-guide]
- [Model selection][gpt-selection]
- [Codex models][codex-models]
- [Introducing GPT-6.1 Sol][gpt-sol-61-launch]
- [GPT-6.1 Sol system card addendum][gpt-sol-61-safety]

第三方與其他平台背景資料（連結保留供追查；未逐項核實，不取代 OpenAI 官方規格）：

- [TechCrunch：GPT-6 Sol and Luna 發布](https://techcrunch.com/2026/09/22/openai-launches-gpt-6-sol-and-luna/)
- [MacRumors：GPT-6 Sol / Luna](https://www.macrumors.com/2026/09/22/openai-gpt-6-sol-luna/)
- [The New Stack：GPT-6.1 Sol vs GPT-6 Astra](https://thenewstack.io/gpt-6-1-sol-vs-gpt-6-astra/)
- [DataCamp：GPT-6.1 Sol](https://www.datacamp.com/blog/gpt-6-1-sol)
- [Respan：Sol vs Luna vs Astra](https://www.respan.ai/articles/gpt-6-sol-vs-luna-vs-astra)
- [CloudInsight：Astra / 6.1 Sol / Luna specs](https://cloudinsight.cc/en/blog/gpt-6-astra-sol-luna-guide)
- [Amazon Bedrock：GPT-6.1 Sol model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-6-1-sol.html)
- [flaviocopes：GPT-6.1 Sol code reviewer 教學](https://flaviocopes.com/gpt-6-1-sol/)
- [AIDEN：Best Codex model](https://aidenapp.org/best-codex-model)

[gpt-models]: https://developers.openai.com/api/docs/models
[gpt-terra]: https://developers.openai.com/api/docs/models/gpt-6.1-terra
[gpt-pricing]: https://developers.openai.com/api/docs/pricing
[gpt-sol-61]: https://developers.openai.com/api/docs/models/gpt-6.1-sol
[gpt-luna]: https://developers.openai.com/api/docs/models/gpt-6-luna
[gpt-guide]: https://developers.openai.com/api/docs/guides/latest-model
[gpt-selection]: https://developers.openai.com/api/docs/guides/model-selection
[codex-models]: https://developers.openai.com/codex/models/
[gpt-sol-61-launch]: https://openai.com/index/introducing-gpt-6-1-sol/
[gpt-sol-61-safety]: https://deploymentsafety.openai.com/gpt-6-1-sol
