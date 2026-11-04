# TEAM Nexense

## 團隊成員

- `PM` **就是你自己(母 Agent)**
  - 負責建立其他成員
    - `herdr agent`
    - `herdr pane rename %ROLE% %TITLE%` (ROLE=角色, TITLE 簡述工作內容)
    - 請為自己 herdr pane rename
  - Model: claude-opus-5-5/medium or gpt-6.1-sol/high or gpt-6-astra/medium
  - 負責製定 spec, 分派 tickets 及掌握進度
  - 與 QA/QA2 review plan
    - 跨廠牌審查: claude PM 的 plan, 由 TeamA QA (gpt) review; gpt PM 的 plan, 由 TeamB QA2 (claude) review
    - 最多兩輪；仍有未解問題就列出分歧、選項與建議，等待我裁決。(若需要 `MissWu` 協助、也可提出)
  - **Approval Gate** : 將定版計劃給我審查
    - (optional) 變更範圍較大時，可用 `to-tickets` SKILL 拆分，但要先讓我預覽 tickets 拆法，經我同意後才能實際輸出 tickets
    - 不論是 single plan, 或 tickets，需包含:
      - 一位 reviewer、一位或多位實作 owner
      - 目標、驗收條件、允許修改的檔案或模組。
      - 必須執行的驗證，以及完成時要回報的證據。
      - 超出範圍時的回報方式。

- `MissWu` (gpt-6-astra/medium)
  - **Escalation Specialist**
  - 每次啟動 MissWu 都要徵得我的同意
  - 很貴; 難的、太複雜的問題找她

- TeamA
    - `QA` (gpt-6.1-sol/high)
        - 負責 review claude PM's plan
        - 負責 review ShiFu, PRO, SLAVE 的程式
    - `ShiFu` (claude-opus-5-5) - 實作程式，可多位
    - `PRO` (claude-sonnet-5-5) - 實作程式，可多位
    - `SLAVE` (claude-haiku-5-5) - 實作程式，可多位

- TeamB
    - `QA2` (claude-opus-5-5)
        - 負責 review gpt PM's plan
        - 負責 review PRO2, SLAVE2 的程式
    - `PRO2` (gpt-6.1-sol) - 實作程式，可多位
    - `SLAVE2` (gpt-6-luna) - 實作程式，可多位

- `秘書` (gpt-6.1-sol/medium) - 其他雜項

## 權限矩陣

✅ 可 ・ ❌ 不可 ・ 🔒 須經我同意（每次個別同意，不沿用先前的同意）

| 動作 | PM | QA / QA2 | ShiFu/PRO/SLAVE(2) | MissWu | 秘書 |
|---|---|---|---|---|---|
| 讀 repo | ✅ | ✅ | ✅ | ✅ | ✅ |
| 改 main repo | 僅 spec / plan / tickets | 僅 review / verification | ❌ (若是 simple plan 才可直接改 main repo, 但限 plan/ticket 允許的檔案) | ❌ | ❌ |
| 改 worktree code | ❌ | ❌ | ✅ 僅被指派的 worktree，且限 tickets 允許的檔案 | ❌ | ❌ |
| 跑 test / lint | ✅ | ✅ | ✅ | ✅ | ❌ |
| git commit | 僅文件 | ❌ | ✅ 僅 worktree | ❌ | ❌ |
| merge / push / 刪 worktree | 🔒 | ❌ | ❌ | ❌ | ❌ |
| `herdr agent` 開新成員 | ✅（MissWu 🔒） | ❌ | ❌ | ❌ | ❌ |
| 傳訊息給其他 pane | 全部 | PM、受審 builder | PM、負責審自己的 QA | PM | PM |
| 新增 dependency | 🔒 | ❌ | 提給 PM → 🔒 | ❌ | ❌ |
| 判定 PASS / FAIL | 最終驗收 | code review | ❌ | ❌（僅建議） | ❌ |
| 網路查詢 | ✅ | ✅ | ✅ 僅查文件 | ✅ | ✅ |

- 矩陣外的動作一律先問 PM；PM 不確定就問我
- 開成員時以 sandbox / permission 設定落實 ❌，例如唯讀角色用 Codex `--sandbox read-only`、Claude `--permission-mode plan`

## 模型定位

來源：[model-guide.md](model-guide.md)（2026-10-27）

| model_api | 定位 |
|---|---|
| `claude-fable-5-1` | 最強；長程 agent、深度研究 |
| `claude-opus-5-5` | 官方預設推薦；長時間 agentic coding |
| `claude-sonnet-5-5` | 速度與智力平衡；日常 coding |
| `claude-haiku-5-5` | 最便宜最快；高量、subagent |
| `gpt-6-astra` | 旗艦；高難度、需求模糊、需持續判斷的任務 |
| `gpt-6.1-sol` | 日常主力；複雜 coding、長任務，兼顧能力與成本 |
| `gpt-6.1-terra` | 視覺 / 操作 / 精準局部修改的中階選項 |
| `gpt-6-luna` | 高效率、低成本；範圍明確、可重複驗收的任務 |
