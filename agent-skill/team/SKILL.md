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
- [ ] 4. Review loop：VERDICT: APPROVE，或第二輪後已取得使用者裁決並寫入 plan/spec (§4 步驟 2)
- [ ] 5. Approval Gate：使用者明確核准 plan/spec；拆 tickets 時，每張 ticket 含範本必要段落且正式 tickets 已核准 (§4 步驟 3-4)
- [ ] 6. 開 Worker 派工 (§4 步驟 5、§5)
- [ ] 7. Code review：RESULT: PASS，或第二輪後已取得使用者裁決 (§4 步驟 5)
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

隊名缺少、不認得、或對目前 PM 不可選時：列出上表 (標明哪些不可選及原因)，請使用者重選後停止。不要自動替換成其他隊名。

## 3. 必讀檔案

選定團隊後，開任何成員之前讀：

- 團隊編制：[teams/team-nexense.md](teams/team-nexense.md)、[teams/team-claude.md](teams/team-claude.md) 或 [teams/team-gpt.md](teams/team-gpt.md) (只讀選定的那份)
- 權限矩陣：[references/permission.md](references/permission.md) (三套團隊都適用)
- 選模型或派工時：[references/model-guide.md](references/model-guide.md)；需要價格、effort、限制等細節時再讀 [references/model-guide-detail.md](references/model-guide-detail.md)

## 4. 流程

用 `herdr pane rename` 把自己的 pane 標成 `<PM 名稱> (PM) - <工作簡述>`，然後依序執行。**使用者核准前，不開 Worker、不派工、不改 code。**

1. 撰寫 plan/spec。
2. Review loop：開團隊檔指定的 Reviewer 審 plan/spec，要求最後一行回覆 `VERDICT: APPROVE` 或 `VERDICT: CHANGES_REQUESTED`。
   - 一輪 = Reviewer 回覆一次 VERDICT，最多兩輪。
   - 第一輪 `CHANGES_REQUESTED`：修改 plan/spec，再送同一位 Reviewer 審第二輪。
   - 第二輪仍是 `CHANGES_REQUESTED`：不再送審，列出分歧、選項與建議，等使用者裁決；裁決寫進 plan/spec 後進入下一步。
3. 把定版 plan/spec 交給使用者審查 (Approval Gate)。plan/spec 依下方「Approval Gate 範本」，每個段落都要填。
4. 若拆成 tickets：每張 ticket 都要包含範本的「目標」到「超出範圍時」各段，且正式 tickets 經使用者核准後才派工。
5. 開 Worker 派工；依權限矩陣掌握進度、安排 code review，最後做最終驗收。
   - Code review 比照 review loop：第一輪 `RESULT: FAIL` 時，Worker 修正後送同一位 Reviewer 審第二輪；第二輪仍是 `FAIL` 就不再送審，列出問題、選項與建議，等使用者裁決。拆成 tickets 時，每張 ticket 各自計算輪數。

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
- <Reviewer 角色名>：<輪數>，`VERDICT: <結果>`
- 未決分歧與使用者裁決：<無 / 內容>
```

## 5. 建立成員

1. 準備可用的 shell pane：依 `herdr` skill 的版面規則 `herdr pane split ... --no-focus`，cwd 依「啟動模式」的可寫範圍。
2. 以 pane ID 啟動 agent。`<alias>` 是 Herdr agent 名稱，須小寫且在執行中的 agents 間唯一：用角色名的小寫，同角色多人加序號，例如 `athena`、`thor`、`thor-2`、`shifu`。

   ```
   herdr agent start <alias> --kind codex --pane <ID> -- -m <model> [-c model_reasoning_effort=<effort>] --sandbox <mode> [--add-dir <worktree>]
   herdr agent start <alias> --kind claude --pane <ID> -- --settings '{"enabledPlugins":{"next-steps@claude-community":false}}' --model <model> [--effort <effort>] --permission-mode <mode> [--add-dir <worktree>]
   ```

   - 團隊檔以 `<model>/<effort>` 標示 effort 時，Codex 帶 `-c model_reasoning_effort=<effort>`、Claude Code 帶 `--effort <effort>`；未標示就省略，使用本機預設。
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
   - Reviewer 審 plan/spec：`回報 PM 的最後一行必須是 VERDICT: APPROVE 或 VERDICT: CHANGES_REQUESTED。`
   - Reviewer 做 code review：`回報 PM 的最後一行必須是 RESULT: PASS 或 RESULT: FAIL。`
   - Worker：`完成後也通知負責審你的 Reviewer：<Reviewer alias>。`
