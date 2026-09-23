# Claude Code 設定移轉筆記（舊筆電 nb → 新 PC）

已完成（1–4）：
- `~/.claude/CLAUDE.md`：語言偏好（台灣繁體中文、術語保留英文）
- `~/.claude/settings.json`：`permissions.allow` 白名單、`defaultMode: auto`、`model/effortLevel/modelSettings`、
  `tui/editorMode/skipAutoPermissionPrompt` 等非機密設定（路徑已從 `damon.liu` 改成 `user`）
- `~/.claude/keybindings.json`：`ctrl+p` → model picker
- `mattpocock-skills@claude-plugins-official` plugin：已手動重建 plugin cache
  （`~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/1.2.3`）並在 `settings.json` 加上
  `enabledPlugins`。啟用了 `ask-matt`, `code-review`, `tdd`, `grilling`, `teach`, `wayfinder` 等一整組技能。
  另外也複製了兩個獨立技能資料夾：`~/.claude/skills/install-skill-from-git`、`~/.claude/skills/skill-creator`。

---

## 待你決定的項目

### 5. 通知系統（`hooks/notify.sh` + `hooks/notify.ps1`）
邏輯：平日 08:30–18:00 用 Windows Toast 通知；其餘時間轉發到個人 ntfy 頻道
`https://ntfy.sh/damou1iu-tw-Claude`（訂閱這個 topic 就能在手機收到）。掛在
`PreToolUse(AskUserQuestion)`、`PermissionRequest`、`Stop` 三個 hook 上。

- 若要移植：直接把 `hooks/notify.sh`、`hooks/notify.ps1` 複製到新 PC 的 `~/.claude/hooks/`，
  並在 `settings.json` 的 `hooks` 區塊加回對應的 `command: "bash ~/.claude/hooks/notify.sh"`。
  需要新 PC 有 Git Bash（`bash`）、`curl`、`powershell` 可用（Windows 內建應該都有）。
- 若不需要：略過即可，純選配。

### 6. OpenPets 整合
`settings.json` 的 hooks 裡每個事件都掛了一段呼叫：
```
node "C:\Users\damon.liu\AppData\Local\Programs\openpets\...\cli.js" hook --openpets-managed
```
這是桌面寵物 App「OpenPets」跟 Claude Code 的整合（在 UserPromptSubmit / PreToolUse /
PermissionRequest / Stop / Notification / StopFailure 都有掛）。

- 若要移植：**必須先在新 PC 安裝 OpenPets App**，安裝後路徑會變成 `C:\Users\user\...`，
  且該路徑目前是寫死的版本路徑（可能隨 App 更新變動），建議安裝好後回頭確認一次實際路徑，
  再把對應 hook 設定加回 `settings.json`。
- 若不再用 OpenPets：可以完全不管這段。

### 7. `wsh badge ...` 通知指令
在 `Notification` / `Stop` hook 裡呼叫 `wsh badge message-question ...`、`wsh badge check ...`
之類的指令（用來改工作列圖示顏色/角標）。在舊筆電 PATH 裡找不到這個指令，代表它可能是：
- 你自己寫的腳本，安裝在某個沒加進系統 PATH 的資料夾；或
- 某個沒加進 PATH 的第三方 CLI。

**需要你補充**：這支 `wsh` 是什麼、裝在哪裡，才知道能不能/怎麼搬到新 PC。若你已經不記得或不再需要，也可以直接捨棄這幾行 hook。

### 8. Statusline（`statusline-command.sh`）
```bash
PYTHONUTF8=1 "C:/Users/damon.liu/AppData/Local/.../PythonSoftwareFoundation.Python.3.13_.../claude-statusbar.exe"
```
呼叫一個透過 pip 裝的 Python 套件產生的 `claude-statusbar.exe`，路徑綁死在舊機器的
Python 3.13 embeddable 安裝路徑（含使用者名稱）。

- 若要移植：在新 PC 用同一個管道重新安裝那個 Python 套件（需要先知道套件名稱/來源，
  這段目前只看得到執行檔名稱 `claude-statusbar.exe`，建議你確認一下裝這個套件時用的指令），
  裝完後把 `~/.claude/statusline-command.sh` 的路徑換成新 PC 產生的路徑。
- 若沒有這個 statusline 也無妨：新 PC 目前沒有設定任何 statusLine，Claude Code 會用預設的。

---

## 不建議搬 / 已略過的項目

- `.credentials.json`、`history.jsonl`、`sessions/`、`projects/`、`cache/`、`plugins/cache`（其他 plugin）、
  `stats-cache.json`、`telemetry/`：機器或 session 專屬狀態，會自動重建，不用搬。
- `plugins/blocklist.json`：Anthropic 遠端拉下來的測試用黑名單快取，會自動更新，不用搬。
- `settings.json` 裡的 `autoMode.environment`：是 Claude 針對舊筆電上「RyokoTower / NexenseTech」
  這個專案自己整理出來的專案上下文（.NET/WPF、OpenSpec workflow 等），跟新 PC 無關。
- `.agents/skills/*`（junction 到各技能的資料夾）：這些跟 `~/.claude/skills/` 下的 junction
  一一對應，來源就是 `mattpocock-skills` plugin 本身（可從 `~/.agents/.skill-lock.json` 看出
  `pluginName: "mattpocock-skills"`）。既然 plugin 已經在新 PC 啟用，這組 junction 是重複的，不需要複製。

## 額外小提醒

- `~/.claude/settings.json` 裡 `permissions.allow` 保留了 `Bash(openspec *)`、`Bash(dotnet *)` 這類
  舊專案（RyokoTower）常用指令的白名單。這些規則在新 PC 上如果用不到也不會造成問題（只是允許規則沒有對應到任何操作），
  但如果你之後想清乾淨，可以之後再手動移除。
