---
name: review-pal
description: >-
  以 Herdr 開一位或多位 Reviewer，審當前 agent (Engineer) 的 plan 與實作；想讓另一個 agent 把關，又不需要 team 的 PM/Worker 編制時使用。
  僅供手動叫用並可附上 Reviewer 模型關鍵字與 effort 後綴，例如 Claude Code 用 `/review-pal` 或 `/review-pal sol opus/high`，Codex 用 `$review-pal`。
disable-model-invocation: true
---

# Review Pal

當前 agent 是 Engineer：自己產出 plan、自己實作。Reviewer 只審，不改檔。與 `team` 不同的是不分 PM/Worker、Reviewer 可多位 (預設一位)。

兩道關卡：先審 plan，通過才實作；實作完再審實作，通過後由 Engineer 總結給使用者。各段依序執行：所有 Reviewer 對同一版本通過，或第二輪後取得使用者裁決，才進入下一段。

## 1. 前置檢查

用當前 shell 的語法確認環境變數 `HERDR_ENV` 等於 `1`：POSIX shell `test "${HERDR_ENV:-}" = 1`，PowerShell `$env:HERDR_ENV -eq '1'`。不成立就告知使用者「不在 Herdr 內，無法開 Reviewer」並停止。

Herdr 指令細節以 `herdr` skill 與 `herdr agent` 輸出為準。

## 2. Reviewer 編制

引數：`$ARGUMENTS` (Codex 不會代入此值，改讀使用者訊息中 `$review-pal` 後面的文字)。每個引數是一位 Reviewer，格式 `<key>[/<effort>]`，例如 `sol`、`opus/high`。

key 對應的 agent、模型與預設 effort 寫在 [models.json](models.json)，模型換版時只改那個檔：

- `reviewers`：每個 key 的 `agent` (`herdr agent start --kind` 的值)、`model`、`effort` (`null` 表示用本機預設，不帶 effort 參數)。
- `default_reviewer`：沒帶引數時開哪一位。以 Engineer 的 agent kind (`claude` 或 `codex`) 為 key，預設是跨廠牌，因為兩個廠牌的盲點不同。

規則：
- 有引數：依序各開一位；使用者明確列出同廠牌也照辦。引數的 effort 後綴覆蓋 JSON 的 effort。
- 不認得的引數：列出 `reviewers` 的 key，請使用者重選後停止。
- effort 參數：Codex 用 `-c model_reasoning_effort=<effort>`，Claude Code 用 `--effort <effort>`。
- alias 是 Herdr agent 名稱，也是 Reviewer 在本 skill 的唯一識別：預設用 key (`sol`、`opus`)，須小寫且在所有執行中的 agents 間唯一。先跑 `herdr agent list`，已有 `sol` 就往後找可用序號 (`sol-2`、`sol-3`)；引數中同一個 key 重複時同理。

## 3. 共識階段

先確認目前的 plan 已與使用者達成共識；有 plan 但尚未共識也算未完成。尚未共識時，先與使用者談到共識 (可用 `grilling` skill)。

plan 存成檔案 (Claude Code 在 plan mode 時就是 plan file)，路徑用 forward slash 寫成絕對路徑交給 Reviewer。plan 依下方範本，每個段落都要填。

```markdown
# <標題>

## 目標
<要解決的問題與預期結果>

## 範圍
- 允許修改：<檔案 / 模組>
- 不在範圍：<明確排除的項目>

## 分工
| 功能 | 成員 | 模型 | 負責 |
|---|---|---|---|
| Engineer | <當前 agent> | <model> | plan 與實作 |
| Reviewer | <alias> | <model/effort> | plan review 與 implementation review |

## 驗收條件
- [ ] <可驗證的條件>

## 驗證
- 必跑：<test / lint / build 指令>

## 超出範圍時
<停止並請使用者裁決的條件>

## Review 紀錄
- <alias>：<輪數>，`VERDICT: <結果>` / `RESULT: <結果>`
- 未決分歧與使用者裁決：<無 / 內容>
```

## 4. 開 Reviewer

先用 `herdr pane rename` 把自己的 pane 標成 `<Engineer 名稱> (Engineer) - <工作簡述>`。開 Reviewer 需要跑 `herdr` 指令：依目前 session 的權限執行，被擋就照工具的流程處理。叫用這個 skill 不代表已授權任何動作。

每位 Reviewer：

1. 依 `herdr` skill 的版面規則 `herdr pane split ... --no-focus` 準備 shell pane，cwd 設在 main repo。
2. 以 pane ID 啟動 agent：該 key 的 `agent` 是 `codex` 用第一行、`claude` 用第二行；`<model>`、`<effort>` 取自 [models.json](models.json) 與引數：

   ```
   herdr agent start <alias> --kind codex --pane <ID> -- -m <model> [-c model_reasoning_effort=<effort>] --sandbox workspace-write
   herdr agent start <alias> --kind claude --pane <ID> -- --settings '{"enabledPlugins":{"next-steps@claude-community":false}}' --model <model> [--effort <effort>] --permission-mode auto
   ```

   Claude Code Reviewer 一律帶 `--settings` 停用 `next-steps` plugin；Codex 不需要。Reviewer 要跑 test，所以不用唯讀模式，「不改檔」由第一個 prompt 限制。
3. `herdr pane rename <pane_id> "<alias> (Reviewer) - <工作簡述>"`。
4. 依下方範本準備第一個 prompt，不要省略任何一行；送出統一在「送審與讀回覆」執行。`<Engineer pane ID>` 是自己的 `$HERDR_PANE_ID`。

   ```text
   你是 Reviewer <alias>，Engineer 是 <Engineer 名稱> (Herdr pane <Engineer pane ID>)。
   任務：<審 plan 或審實作；plan 的絕對路徑、diff 範圍、Engineer 已跑的驗證輸出>
   允許修改：無；不改任何檔案。
   權限限制：只讀 repo、可跑 test；不 commit、不 push、不開新 agent、不傳訊息給其他 pane。
   完成後：在本 pane 回覆審查結果，列出具體問題與建議修正；Engineer 會讀取你的 pane。
   超出範圍或不確定時：在回覆中說明，不要自行擴大範圍。
   回覆的最後一行必須是 <Plan review：VERDICT: APPROVE-PLAN 或 VERDICT: CHANGES_REQUESTED；Implementation review：RESULT: APPROVE-IMPLEMENT 或 RESULT: CHANGES_REQUESTED>。
   ```

驗證指令由 Engineer 跑，輸出附在送審內容裡；Reviewer 的環境可能缺少 runtime (例如沒有 python)，能重跑就重跑，不能就在回覆中說明。

## 5. 送審與讀回覆

所有 Reviewer 都是同一套做法，多位時自然平行：

1. 對每位 Reviewer 各送一次 `herdr agent prompt <alias> "<內容>"`，不帶 `--wait`。內容含多行或特殊字元時先存成變數或檔案再送 (PowerShell 用單引號 here-string)，路徑一律用 forward slash。
2. 逐一 `herdr agent wait <alias> --timeout 120000`。一次 review 通常 1-2 分鐘，每次等待保持短，才能定期檢查狀態；外層 Bash / PowerShell 工具的 timeout 要比它長 (例如 150000)。
3. 逾時就 `herdr agent get <alias>`：還在 working 就繼續 wait；blocked 就先 `herdr agent read` 看卡在哪個 UI，交使用者處理。不要重送 prompt，否則 Reviewer 會重複審查。
4. 完成後 `herdr agent read <alias> --source recent-unwrapped --lines 200`；結論看不全就加到 400，仍不行就請 Reviewer 在 pane 裡只重貼結論與最後一行。

只有第一次送審用完整範本。後續輪次只送修正摘要、驗證輸出與格式行，例如：

```text
第 2 輪：已依你的意見修訂同一份 plan (路徑同前)。修正摘要：<逐點>。驗證輸出：<輸出>。
回覆的最後一行必須是 VERDICT: APPROVE-PLAN 或 VERDICT: CHANGES_REQUESTED。
```

## 6. Plan review

所有 Reviewer 平行審，最後一行回 `VERDICT: APPROVE-PLAN` 或 `VERDICT: CHANGES_REQUESTED`。

- plan review、implementation review 各自最多兩輪；一輪 = 所有 Reviewer 對同一版本各回覆一次。上限是為了避免無限來回，兩輪還沒收斂的分歧交使用者裁決。
- 任一 Reviewer 回 `CHANGES_REQUESTED`：Engineer 修正後，把同一份修訂版送給所有 Reviewer 重審，已 approve 的也要重審，因為修正可能影響他們已認可的部分。
- Reviewer 的修改要求若會改變已與使用者達成共識的決策：先取得使用者裁決並更新 plan，再繼續送審或實作，不自行採納或駁回。
- Reviewer 之間意見衝突：Engineer 提出取捨與理由，放進下一輪送審。
- 前進條件：所有 Reviewer 對同一版本 approve，或第二輪後取得使用者裁決。Engineer 不能自行推翻仍存在的 `CHANGES_REQUESTED`。
- 第二輪仍有 `CHANGES_REQUESTED`：不再送審，列出分歧、選項與建議，等使用者裁決；裁決寫進 plan 的 Review 紀錄。

通過後若 Engineer 仍在 Claude Code 的 plan mode，用原生的 ExitPlanMode 流程進入實作，不另外加 skill 自訂的 Approval Gate。

## 7. 實作

Engineer 直接在 main repo 實作，範圍以 plan 為限，跑 plan 的驗證指令。commit、push、新增 dependency、刪檔都先取得使用者同意。

遇到範圍外的需求，或必須改變共識決策時：停下相關工作，交使用者裁決，裁決寫進 Review 紀錄後再繼續。

## 8. Implementation review

送給同一批 Reviewer session (main repo 不需要 `--add-dir`，Reviewer 保留 plan 的 context)，附上 diff 範圍與驗證指令輸出。最後一行回 `RESULT: APPROVE-IMPLEMENT` 或 `RESULT: CHANGES_REQUESTED`。輪數、重審與前進條件同 Plan review。

## 9. 總結給使用者

回報：改了什麼、驗證結果、Review 紀錄 (每位 Reviewer 的輪數與結果、使用者裁決)、仍開著的 Reviewer pane (使用者要求時才關)。
