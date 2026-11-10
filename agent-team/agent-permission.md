# 權限矩陣

✅ 可 ・ ❌ 不可 ・ 🔒 須經我同意（每次個別同意，不沿用先前的同意）

| 動作 | ODIN / ZMen / SOLAR | ATHENA / THEMIS / HuFa / HALLEY | THOR / ARES / LOKI / VULCAN / PAN / ShiFu / ShiZa / ShiDi / JUPITER / SATURN / LUNA | SOPHIA | HEBE |
|---|---|---|---|---|---|
| 讀 repo | ✅ | ✅ | ✅ | ✅ | ✅ |
| 改 main repo | 僅 spec / plan / tickets | 僅 review / verification | ❌ (若是 simple plan 才可直接改 main repo, 但限 plan/ticket 允許的檔案) | ❌ | ❌ |
| 改 worktree code | ❌ | ❌ | ✅ 僅被指派的 worktree，且限 tickets 允許的檔案 | ❌ | ❌ |
| 跑 test / lint | ✅ | ✅ | ✅ | ✅ | ❌ |
| git commit | 僅文件 | ❌ | ✅ 僅 worktree | ❌ | ❌ |
| merge / push / 刪 worktree | 🔒 | ❌ | ❌ | ❌ | ❌ |
| `herdr agent` 開新成員 | ✅（SOPHIA 🔒） | ❌ | ❌ | ❌ | ❌ |
| 傳訊息給其他 pane | 全部 | 母 Agent、受審 builder | 母 Agent、負責審自己的 reviewer | 母 Agent | 母 Agent |
| 新增 dependency | 🔒 | ❌ | 提給母 Agent → 🔒 | ❌ | ❌ |
| 判定 PASS / FAIL | 最終驗收 | code review | ❌ | ❌（僅建議） | ❌ |
| 網路查詢 | ✅ | ✅ | ✅ 僅查文件 | ✅ | ✅ |

- 矩陣外的動作一律先問母 Agent；母 Agent 不確定就問我
- 開成員時以 sandbox / permission 設定落實 ❌，例如唯讀角色用 Codex `--sandbox read-only`、Claude `--permission-mode plan`
