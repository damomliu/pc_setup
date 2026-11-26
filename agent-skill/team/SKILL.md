---
name: team
description: >-
  以 Herdr 組建並指揮多 agent 開發團隊 (nexense、claude、gpt 三套編制)，由當前 agent 擔任 PM，
  負責撰寫 plan/spec、安排 Reviewer 審查、通過使用者的 Approval Gate 後再開 Worker 派工。
  僅供手動叫用並附上隊名，例如 Claude Code 用 `/team nexense`，Codex 用 `$team nexense`。
disable-model-invocation: true
---

# Team

當前 agent 就是 PM。依指定的團隊編制，用 Herdr 開成員、審 plan/spec、派工並掌握進度。

## 進度清單

把以下清單複製到回覆中，每完成一步就更新勾選狀態。依序勾選：前一項未勾選，不得進行下一項；第 5 項必須有使用者明確核准的訊息。§1、§2 停止時不需輸出清單。

```text
Team 進度：
- [ ] 1. 前置檢查：HERDR_ENV=1 (§1)
- [ ] 2. 選定團隊，讀完必讀檔案 (§2-§3)
- [ ] 3. 依 Approval Gate 範本撰寫 plan/spec，Review 紀錄於第 4 項後補 (§4 步驟 1)
- [ ] 4. Review loop：VERDICT: APPROVE-PLAN，或第二輪後已取得使用者裁決並寫入 plan/spec (§4 步驟 2)
- [ ] 5. Approval Gate：使用者明確核准 plan/spec；拆 tickets 時，每張 ticket 含範本必要段落且正式 tickets 已核准 (§4 步驟 3-4)
- [ ] 6. 開 Worker 派工，Worker 回報完成；期間的 blocker 已處理，裁決已寫入 Review 紀錄 (§4 步驟 5、§5)
- [ ] 7. Code review：RESULT: APPROVE-IMPLEMENT，或第二輪後已取得使用者裁決 (§4 步驟 5)
- [ ] 8. 最終驗收，回報使用者 (§4 步驟 5)
```

## 1. 前置檢查

用當前 shell 的語法確認環境變數 `HERDR_ENV` 等於 `1`：POSIX shell `test "${HERDR_ENV:-}" = 1`，PowerShell `$env:HERDR_ENV -eq '1'`。不成立就告知使用者「不在 Herdr 內，無法組建團隊」並停止，不開任何成員。

Herdr 指令細節以 `herdr` skill 與 `herdr agent` 輸出為準。

## 2. 選擇團隊

隊名：`$ARGUMENTS`（Codex 不會代入此值，改讀使用者訊息中 `$team` 後的文字）。

PM 的廠牌由當前 agent 決定：Claude Code 為 Claude，Codex 為 GPT。本 skill 中「Claude / GPT」指廠牌，「Claude Code / Codex」指 agent。

| 隊名 | 說明 | PM=Claude | PM=GPT |
|---|---|---|---|
| `nexense` | 完整編制：跨廠牌 review、TeamA / TeamB、Helper、Grant-Helper | 可選 | 可選 |
| `claude` | 簡化版：Claude PM、GPT Reviewer、Claude Worker | 可選 | 不可選 |
| `gpt` | 簡化版：GPT PM、Claude Reviewer、GPT Worker | 不可選 | 可選 |

三套編制中，審 plan/spec 與審程式的 Reviewer，都與被審的 PM 或 Worker 不同廠牌，因為兩個廠牌的盲點不同，跨廠牌審查比同廠牌自審更容易抓到問題。

隊名缺少、不認得、或對目前 PM 不可選時：列出上表 (標明哪些不可選及原因)，請使用者重選後停止。不要自動替換成其他隊名。

## 3. 必讀檔案

選定團隊後，開任何成員之前讀：

- 團隊編制：[teams/team-nexense.md](teams/team-nexense.md)、[teams/team-claude.md](teams/team-claude.md) 或 [teams/team-gpt.md](teams/team-gpt.md) (只讀選定的那份)
- 成員模型：[models.json](models.json)，模型換版時只改那個檔 (團隊檔只留編制與職責)：
  - `teams.<隊名>.members`：key 是角色名小寫 (同時是 Herdr alias 基底，`thor-2` 查 `members.thor`)；`function` 是功能 (同權限矩陣)，`agent` 是 `herdr agent start --kind` 的值，另有 `model`、`effort` (`null` 表示用本機預設，不帶 effort 參數)。
  - `teams.<隊名>.pm`：選填，只供當前 PM 參考，不會啟動或切換 PM 模型。
- 權限矩陣：[references/permission.md](references/permission.md) (三套團隊都適用)
- 決定派哪位成員時：[references/model-guide.md](references/model-guide.md)；需要價格、effort、限制與各成員適合的 ticket 等細節時再讀 [references/model-guide-detail.md](references/model-guide-detail.md)

## 4. 流程

用 `herdr pane rename` 把自己的 pane 標成 `<PM 名稱> (PM) - <工作簡述>`，然後依序執行。**使用者核准前，不開 Worker、不派工、不改 code。**

1. 撰寫 plan/spec。
2. Review loop：開團隊檔指定的 Reviewer 審 plan/spec，要求最後一行回覆 `VERDICT: APPROVE-PLAN` 或 `VERDICT: CHANGES_REQUESTED`。
   - 一輪 = Reviewer 回覆一次 VERDICT，最多兩輪；上限是為了避免無限來回，兩輪還沒收斂的分歧交使用者裁決。
   - 第一輪 `CHANGES_REQUESTED`：修改 plan/spec，再送同一位 Reviewer 審第二輪。
   - 第二輪仍是 `CHANGES_REQUESTED`：不再送審，列出分歧、選項與建議，等使用者裁決；裁決寫進 plan/spec 後進入下一步。
3. 把定版 plan/spec 交給使用者審查 (Approval Gate)。plan/spec 依下方「Approval Gate 範本」，每個段落都要填。
4. 若拆成 tickets：每張 ticket 都要包含範本的「目標」到「超出範圍時」各段，且正式 tickets 經使用者核准後才派工。
5. 開 Worker 派工；依權限矩陣掌握進度，最後做最終驗收。成員之間的交接都經過 PM。
   - Blocker：Worker 回報 blocker 時，PM 先自行查證事實 (讀 code、跑指令)。牽涉 plan 決策時交使用者裁決，把裁決寫進 plan/spec 的 Review 紀錄，再通知 Worker 繼續。
   - Code review 由 PM 發起：Worker 回報完成後，PM 決定用哪個 Reviewer session。
     - 重用 plan review 的 Reviewer：Worker 的 cwd 與 PM 相同、負責 code review 的成員就是 plan Reviewer，且該 session 仍在 (`herdr agent get <alias>` 為 idle 或 done)。Reviewer 保留 plan 的 context，PM 送後續 prompt：任務是 code review，附 Worker 回報的 diff 與驗證證據、ticket 路徑，並帶 `RESULT:` 格式行。
     - 否則新建 Reviewer session (§5)，第一個 prompt 帶 `RESULT:` 格式行。Worker 在另開的 worktree 時，以 `--add-dir <worktree>` 加入；`--add-dir` 只能在啟動時加，既有 session 看不到新的 worktree。code reviewer 與 plan Reviewer 不同人時 (例如 nexense 的跨廠牌審查) 也要新建。
     - 新建時 alias 依 §5 往後找序號 (例如 `athena-2`)；重用沿用原 alias。Review 紀錄寫實際 alias，後續輪次才不會送錯 session。
   - Code review 比照 review loop：第一輪 `RESULT: CHANGES_REQUESTED` 時，PM 把問題轉給 Worker，Worker 修正後回報 PM，PM 再送同一位 Reviewer 審第二輪；第二輪仍是 `CHANGES_REQUESTED` 就不再送審，列出問題、選項與建議，等使用者裁決。拆成 tickets 時，每張 ticket 各自計算輪數。

### Approval Gate 範本

```markdown
# <標題>

## 目標
<要解決的問題與預期結果>

## 範圍
- 允許修改：<檔案 / 模組 / worktree>
- 不在範圍：<明確排除的項目>

## 分工
| 功能 | 成員 | 模型 | 負責 |
|---|---|---|---|
| Reviewer | <角色名> | <model/effort> | plan/spec 與 code review |
| Worker | <角色名> | <model/effort> | <模組或 ticket> |

## 驗收條件
- [ ] <可驗證的條件>

## 驗證與回報證據
- 必跑：<test / lint / build 指令>
- 回報：<diff 摘要、指令輸出、截圖等>

## 超出範圍時
<停止並回報 PM 的條件與方式>

## Review 紀錄
- <Reviewer alias> (plan/spec)：<輪數>，`VERDICT: <結果>`
- <Reviewer alias> (code review)：<輪數>，`RESULT: <結果>`
- 未決分歧與使用者裁決 (含實作 blocker)：<無 / 內容>
```

## 5. 建立成員

1. 準備可用的 shell pane：依 `herdr` skill 的版面規則 `herdr pane split ... --no-focus`，cwd 依「啟動模式」的可寫範圍。
2. 以 pane ID 啟動 agent。`<alias>` 是 Herdr agent 名稱，須小寫且在執行中的 agents 間唯一：先跑 `herdr agent list`，用角色名的小寫；已有同名就往後找可用序號，例如 `athena`、`thor`、`thor-2`、`shifu`。

   ```
   herdr agent start <alias> --kind codex --pane <ID> -- -m <model> [-c model_reasoning_effort=<effort>] --sandbox <mode> [--add-dir <worktree>]
   herdr agent start <alias> --kind claude --pane <ID> -- --settings '{"enabledPlugins":{"next-steps@claude-community":false}}' --model <model> [--effort <effort>] --permission-mode <mode> [--add-dir <worktree>]
   ```

   - `--kind`、`<model>`、`<effort>` 取自 [models.json](models.json) 的 `teams.<隊名>.members.<alias 基底>`。effort 為 `null` 就省略，使用本機預設；否則 Codex 帶 `-c model_reasoning_effort=<effort>`、Claude Code 帶 `--effort <effort>`。
   - Claude Code 成員一律在 `--` 之後帶上述 `--settings`，停用 `next-steps` plugin；Codex 成員不需要。
   - `--sandbox <mode>`、`--permission-mode <mode>`、pane cwd 與 `--add-dir` 依 [references/permission.md](references/permission.md) 的「啟動模式」，按成員的功能選擇。
3. `herdr pane rename <pane_id> "<角色名> (<功能>) - <工作簡述>"`，例如 `ATHENA (Reviewer) - review plan/spec`。
4. 用 `herdr agent prompt <alias> ...` 送出第一個 prompt，依下方範本填寫，不要省略任何一行。`<PM pane ID>` 是 PM 自己的 `$HERDR_PANE_ID`。

   ```text
   你是 <角色名> (<功能>)，PM 是 <PM 名稱> (Herdr pane <PM pane ID>)。
   任務：<任務內容；plan/spec 或 ticket 的路徑>
   允許修改：<檔案、模組或 worktree>；其他檔案一律不改。
   權限限制：<該功能在權限矩陣中所有適用的限制：❌、🔒 與附條件的 ✅>
   完成後：用 `herdr agent prompt <PM pane ID> "<回報>"` 回報 PM，附上 <要回報的證據>。
   超出範圍或不確定時：停止並回報 PM，不要自行擴大範圍。
   ```

   依功能再加一行：
   - Reviewer 審 plan/spec：`回報 PM 的最後一行必須是 VERDICT: APPROVE-PLAN 或 VERDICT: CHANGES_REQUESTED。`
   - Reviewer 做 code review：`回報 PM 的最後一行必須是 RESULT: APPROVE-IMPLEMENT 或 RESULT: CHANGES_REQUESTED。`
   - Worker：`完成或遇到 blocker 時只回報 PM；blocker 要說明卡住的事實與已查證的內容。`
   - Claude Code Worker：`改檔用 Edit / Write 工具；指令直接在 pane cwd 執行，檔案路徑以參數帶入，不加 cd 前綴。`
