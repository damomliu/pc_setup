# 權限矩陣

## 角色功能

各成員的功能標在團隊檔的名字旁，例如 `ODIN (PM)`。

| 功能 | 職責 |
|---|---|
| PM | 當前 agent；撰寫 plan/spec、開成員、派工、掌握進度、最終驗收 |
| Reviewer | 審 PM 的 plan/spec 與 Worker 的程式，判定 code review PASS / FAIL |
| Worker | 依核准的 plan/spec 或 ticket 實作程式 |
| Helper | 調查與其他雜項 |
| Grant-Helper | Escalation Specialist；處理困難、複雜的問題，成本高 |

## 矩陣

✅ 可 ・ ❌ 不可 ・ 🔒 須經使用者同意 (每次個別同意，不沿用先前的同意)

| 動作 | PM | Reviewer | Worker | Grant-Helper | Helper |
|---|---|---|---|---|---|
| 讀 repo | ✅ | ✅ | ✅ | ✅ | ✅ |
| 改 main repo | 僅 plan/spec / tickets | 僅 review / verification | ❌ (簡單的 plan/spec 才可直接改 main repo，但限 plan/spec 或 ticket 允許的檔案) | ❌ | ❌ |
| 改 worktree code | ❌ | ❌ | ✅ 僅被指派的 worktree，且限核准的 plan/spec 或 ticket 允許的檔案 | ❌ | ❌ |
| 跑 test / lint | ✅ | ✅ | ✅ | ✅ | ❌ |
| git commit | 僅文件 | ❌ | ✅ 僅 worktree | ❌ | ❌ |
| merge / push / 刪 worktree | 🔒 | ❌ | ❌ | ❌ | ❌ |
| `herdr agent` 開新成員 | ✅ (Grant-Helper 🔒) | ❌ | ❌ | ❌ | ❌ |
| 傳訊息給其他 pane | 全部 | PM、受審 Worker | PM、負責審自己的 Reviewer | PM | PM |
| 新增 dependency | 🔒 | ❌ | 提給 PM → 🔒 | ❌ | ❌ |
| 判定 PASS / FAIL | 最終驗收 | code review | ❌ | ❌ (僅建議) | ❌ |
| 網路查詢 | ✅ | ✅ | ✅ 僅查文件 | ✅ | ✅ |

- 矩陣外的動作一律先問 PM；PM 不確定就問使用者

## 啟動模式

開成員時依功能選 sandbox / permission。唯讀模式會擋掉寫暫存檔的 test，所以只用在不跑 test 也不改檔的功能；其餘功能的改檔範圍由第一個 prompt 限制。

| 功能 | Codex | Claude Code |
|---|---|---|
| Reviewer、Worker、Grant-Helper | `--sandbox workspace-write` | `--permission-mode acceptEdits` |
| Helper | `--sandbox read-only` | `--permission-mode plan` |

可寫範圍：
- Worker：pane cwd 設在被指派的 worktree；獲准直接改 main repo 時 (簡單的 plan/spec) 設在 main repo。
- Reviewer：pane cwd 設在 main repo (可寫 review / verification 檔)。Code review 時，以 `--add-dir <worktree>` 加入每個待審的 worktree (Codex、Claude Code 同名參數)；審 plan/spec 時開的 session 沒有這些目錄，code review 要重新啟動。
