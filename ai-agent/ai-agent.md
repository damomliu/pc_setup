# AI Agent Config

## 4 Agents

| 名稱 | 執行環境 | Agent | Global 規則檔 | Repo 設定來源 |
| --- | --- | --- | --- | --- |
| Win-Claude | Windows | Claude Code | `$HOME/.claude/CLAUDE.md`、`pstack-models.md` | `claude-settings.json` |
| Win-Codex | Windows | Codex | `$HOME/.codex/AGENTS.md` | `codex-config.toml` |
| WSL-Claude | WSL | Claude Code | `$HOME/.claude/CLAUDE.md`、`pstack-models.md` | `claude-settings.json` + `claude-settings.wsl.json` |
| WSL-Codex | WSL | Codex | `$HOME/.codex/AGENTS.md` | `codex-config.toml` |

統稱：`Win-*`、`WSL-*` 指同一執行環境的兩個 agent；`*-Claude`、`*-Codex` 指同一 agent 的兩個環境；「4 Agents」指全部。

## Global 規則

Claude 與 Codex 各自維護一份完整的 global 指引，同工具的 Win／WSL 共用同一份來源；共同規則允許在兩份重複，不抽共用模板，也不要求兩份內容一致。

| Repo 來源 | 佈署目標（Win／WSL） | 說明 |
| --- | --- | --- |
| [CLAUDE.md](CLAUDE.md) | `~/.claude/CLAUDE.md` | Claude 完整指引，不引用 pstack 設定 |
| [claude-pstack-models.md](claude-pstack-models.md) | `~/.claude/pstack-models.md` | Claude pstack 角色 model、default effort、session hook |
| [AGENTS.md](AGENTS.md) | `~/.codex/AGENTS.md` | Codex 完整指引，不含 pstack 設定 |

Codex 同步器將 `AGENTS.md` 當作一般文字檔，不要求 pstack 區塊，也不產生、比對或修改 `~/.codex/pstack-models.md`；既有非受管檔案需另行清理。Claude 仍同步獨立的 `pstack-models.md`，但 `CLAUDE.md` 不再引用它。

WSL 的 `$HOME` 屬於 Linux user；不同 user / distro 各自獨立。設定 `CODEX_HOME` 或 `CLAUDE_CONFIG_DIR` 時，對應檔案改由該目錄讀取（同步腳本尚不支援這兩個變數）。

VSCode 使用哪份規則取決於 backend 實際執行環境；切換 terminal 不等於切換 backend。

### 忽略欄位

各環境自己選擇的 model、effort 不參與同步，只限下列設定檔的頂層 key（不遞迴到同名巢狀 key）：

| 工具 | 忽略欄位 | 仍受管 |
| --- | --- | --- |
| Claude（`settings.json`） | `model`、`effortLevel` | `modelSettings.*.effortLevel`、pstack 設定 |
| Codex（`config.toml`） | `model`、`model_reasoning_effort` | repo 列出的其他 key（含 section） |

比對時排除；推送與 `-Force` 保留各目標原值，目標缺值不補入（含首次建立）；Pull 保留 repo 原值、repo 沒有的不新增。只有忽略欄位不同時視為 same，不改寫檔案。

### sync 用法

[sync.ps1](sync.ps1) 一次執行 [sync-claude.ps1](sync-claude.ps1) 與 [sync-codex.ps1](sync-codex.ps1)（參數相同，第一支失敗即不跑第二支；兩者沒有跨工具 transaction）。共用邏輯在 [sync-common.ps1](sync-common.ps1)。

- 預設：repo → Windows 與 WSL；目標內容不同需 `-Force`。
- `-PullWin` / `-PullWsl`：收回 repo；兩者互斥，Claude 與 Codex 各自收回自己的指引，不再要求兩者一致。
- `-Check`：唯讀，只列出每個目標的 `missing` / `same` / `differs`（Codex config 另有 `update`）。
- `-CheckVerbose`：唯讀，單獨使用即包含 `-Check`，另列出設定路徑與「本機 → repo 預期」值（WSL 為合併後結果）及指引／pstack 文字的逐行 diff。忽略欄位不出現；env 子樹與路徑含 token / secret / password / auth / credential、或為 key 類名稱（`key`、`apiKey`、`api_key`…）的值顯示 `***`。
- `-Check` / `-CheckVerbose` 不能與 `-PullWin` / `-PullWsl` / `-Force` 併用，會在任何 I/O 前拒絕。
- JSON 比對忽略 object key 順序與排版（array 順序、值與型別、字串大小寫都有意義）；TOML 依 section／key 查找，忽略排列順序。
- 隱藏參數 `-TestWinHome` / `-TestWslRoot` 供測試使用，必須成對指定，指定後不呼叫 WSL。

### 測試

[test-sync.ps1](test-sync.ps1) 以暫存 repo / Windows home / WSL home 執行同步腳本 CLI，不碰真實設定、不需外部套件：`pwsh -NoProfile -File ai-agent/test-sync.ps1`（`-Only '<情境名稱萬用字元>'` 可只跑部分情境）。實機驗證請另外對真實 4 Agents 執行唯讀 `.\sync.ps1 -CheckVerbose`。

## 更新

[update.ps1](update.ps1) 一次更新 Windows 與 WSL 的 Claude Code、Codex 及其 plugins / `npx skills` / asana skill（`-Distro`、`-SkipWin`、`-SkipWsl`）；單一步驟失敗只警告並繼續，最後彙整失敗清單。請在沒有執行中的 claude / codex 的 terminal 執行；plugin 更新需重啟 session 才生效。

## ChatGPT Codex

### 佈署

用 [sync-codex.ps1](sync-codex.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo）：`AGENTS.md` 整檔覆寫；`codex-config.toml` 列出的 key（含 `[tui]` 這類 section，頂層 `model` / `model_reasoning_effort` 除外）合併至各自的 `$HOME/.codex/config.toml`，保留既有 model、MCP 等設定（用法見檔頭）。

- Repo 副本：
  - [AGENTS.md](AGENTS.md)
  - [codex-config.toml](codex-config.toml)
  保存 approval / sandbox、`[tui]` status line 與 keymap 設定；`AGENTS.md` 保存 Codex global 指引
- `Ctrl+Enter` 換行：透過 `[tui.keymap.editor].insert_newline` 設定，保留預設換行按鍵；一般 `Enter` 仍由 composer 送出。Windows 與 WSL 共用，修改後重啟 Codex CLI 生效。
- 啟用 Auto-Review（[OpenAI Docs](https://learn.chatgpt.com/docs/sandboxing/auto-review)）
  - CLI / 本機 config：repo 已設定 `approval_policy = "on-request"`、`approvals_reviewer = "auto_review"`、`sandbox_mode = "workspace-write"`。

## Claude Code

### 佈署

用 [sync-claude.ps1](sync-claude.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo；`-PullWsl` 要求 WSL settings.json 等於 repo 合併結果，忽略欄位除外）

- Repo 副本：
  - `CLAUDE.md`、`claude-pstack-models.md`
  - `claude-settings.json` - 母版、Windows 版
  - `claude-settings.wsl.json` - WSL 專屬變更
  - `claude-keybindings.json` 
  - [claude-statusline.py](claude-statusline.py) - status line script，sync 到 `~/.claude/statusline.py`

### 快速鍵
- `Ctrl+P` 切換 model

### Mods (Plugins)
- [next-steps](https://github.com/anthropics/claude-plugins-community/tree/main/next-steps)

## Global 共同項目

### Status line
Codex 與 Claude Code 共用 `Model · Workspace · 5h · weekly · Context · 用量` 的格式，Claude Code 向 Codex 的外觀對齊（Codex 只能挑內建 item，不能自訂）：

| | Codex（`tui.status_line`） | Claude Code（[claude-statusline.py](claude-statusline.py)） |
|---|---|---|
| Model | `model-with-reasoning` | `model.display_name` ＋ effort |
| Workspace | `project-name`、`thread-name` | 專案資料夾名稱（無 thread title） |
| 5h／week | `five-hour-limit`、`weekly-limit`（`5h N% left`） | 同格式 |
| Context | `context-used`（`Context N% used`） | 同格式 |
| 用量 | `used-tokens`（session 累計） | `$1.2`（`cost.total_cost_usd`；stdin JSON 沒有累計 token，故不放 token 數） |

Claude Code 另外依剩餘比例變色（5h／weekly 剩餘或 Context 剩餘 ≤25% 黃、≤10% 紅）；Codex 不隨數值變色，僅 `status_line_use_colors = true` 依 item 類型上色。

### Skills
- asana-ai-skill
- herdr（Windows、WSL 各執行一次；裝到 `~/.agents/skills/herdr`，Codex 直接讀取，Claude Code 以 symlink 連結）：
  `npx skills add herdrdev/herdr --skill herdr -g -a claude-code -a codex -y`
  更新：執行 `ai-agent/update.ps1`（含 `npx skills update -g`）；手動更新時 WSL 的 npx 來自 nvm，非互動 shell 需先 `source ~/.nvm/nvm.sh`
- 本機技能正本放 `.agents/skills/`，`.claude/skills/` 底下用 junction 指過去（git 不會保留 junction，clone 後要重建）：
  `New-Item -ItemType Junction -Path .claude\skills\wezterm -Target .agents\skills\wezterm`
- [pstack](https://github.com/michael-denyer/pstack-claude)
  - Claude plugin 在 Win／WSL 均設為停用，保留 marketplace 來源。Claude 的獨立設定仍放 `claude-pstack-models.md` 並參與 sync；global 指引不再引用它。Codex 的 pstack 設定不參與 sync。


## Project 初始化慣例

- 在 repo root 建立空的 `AGENTS.md`，並讓 `CLAUDE.md` 內容為 `@AGENTS.md`。
- 既有檔案保留，不覆寫。
- 空的 project `AGENTS.md` 不會停用 global 規則。

## 官方參考

- [OpenAI Docs：AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：global / project 搜尋順序、`CODEX_HOME`、`AGENTS.override.md`。
- [OpenAI Docs：Windows / WSL](https://developers.openai.com/codex/windows)：Windows native 與 WSL execution 的區別。
- [Claude Code：Memory](https://code.claude.com/docs/en/memory)：user / project instructions 與 `@AGENTS.md` import（適用不直接讀 AGENTS.md 的 session）。
- [Claude Code：Settings](https://code.claude.com/docs/en/settings)：`CLAUDE_CONFIG_DIR` 與設定範圍。
