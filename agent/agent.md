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
| [CLAUDE.md](config/CLAUDE.md) | `~/.claude/CLAUDE.md` | Claude 完整指引，不引用 pstack 設定 |
| [claude-pstack-models.md](config/claude-pstack-models.md) | `~/.claude/pstack-models.md` | Claude pstack 角色 model、default effort、session hook |
| [AGENTS.md](config/AGENTS.md) | `~/.codex/AGENTS.md` | Codex 完整指引，不含 pstack 設定 |

Codex 同步器將 `AGENTS.md` 當作一般文字檔，不要求 pstack 區塊，也不產生、比對或修改 `~/.codex/pstack-models.md`；既有非受管檔案需另行清理。Claude 仍同步獨立的 `pstack-models.md`，但 `CLAUDE.md` 不再引用它。

VSCode 使用哪份規則取決於 backend 實際執行環境；切換 terminal 不等於切換 backend。

### 忽略欄位

- Claude（`settings.json`）
  - 忽略欄位：`model`、`effortLevel`
  - 仍受管：`modelSettings.*.effortLevel`、pstack 設定
- Codex（`config.toml`）
  - 忽略欄位：`model`、`model_reasoning_effort`
  - 仍受管：repo 列出的其他 key（含 section）

比對時排除；推送與 `--force` 保留各目標原值，目標缺值不補入（含首次建立）；Pull 保留 repo 原值、repo 沒有的不新增。只有忽略欄位不同時視為 same，不改寫檔案。

## 腳本

### 同步

Windows:
`agent\\.venv\\windows\\Scripts\\python.exe agent\\sync.py --check-verbose`

WSL/Linux:
`agent/.venv/wsl/bin/python agent/sync.py --check-verbose`

macOS:
`agent/.venv/macos/bin/python agent/sync.py --check-verbose`

### 更新

[update.ps1](update.ps1) 是 PowerShell 7 的互動入口, 讓選定的 agent 執行 `update-core.ps1` 一次, 並以繁體中文總結成功 / 失敗 / 略過項目、版本、更新 exit code 與後續處理。

未指定 `-Agent` 或 `-Preview` 時顯示選單, Enter 預設只 preview, 不執行更新:

```text
1. Codex Luna   - 執行並總結
2. Claude Haiku - 執行並總結
3. Codex Luna   - 只 preview [預設]
4. Claude Haiku - 只 preview
Q. 離開
```

選單不顯示 effort, 兩個 agent 實際皆使用 `medium`。無效輸入會重新詢問; Q 或輸入結束時離開。指定 `-Agent` 或 `-Preview` 就略過選單; `-Model`、`-Distro`、`-SkipWin`、`-SkipWsl` 本身不略過選單。

```powershell
pwsh -File agent/update.ps1                              # 互動選單
pwsh -File agent/update.ps1 -Agent codex                 # gpt-6-luna, 直接執行並總結
pwsh -File agent/update.ps1 -Agent claude                # haiku, 直接執行並總結
pwsh -File agent/update.ps1 -SkipWsl                     # 選單, 只更新 Windows
pwsh -File agent/update.ps1 -Distro Ubuntu-24.04 -SkipWin # 選單, 只更新 WSL
pwsh -File agent/update.ps1 -Model <model-id>             # 選單, 覆寫 model ID
pwsh -File agent/update.ps1 -Preview                     # Codex preview, 不啟動 agent
pwsh -File agent/update.ps1 -Agent claude -Preview       # Claude preview
```

preview 完整顯示 agent、model、CLI 參數與 prompt (包含實際 effort), 不需要已安裝 agent CLI。執行時需要已安裝並登入對應 CLI, 且帳號可使用所選 model。Codex 使用 `--approve-for-me` 進行自動權限審查; Claude 使用 print mode 並沿用現有 permissions, 未授權的工具操作可能被拒絕。封裝不略過 permissions / sandbox, 需要互動的更新可能仍須手動執行。

[update-core.ps1](update-core.ps1) 是原本的更新腳本, 可直接執行以更新 Windows 與 WSL 的 Claude Code、Codex 及其 plugins / `npx skills` / asana skill, 支援 `-Distro`、`-SkipWin`、`-SkipWsl`。單一步驟失敗只警告並繼續, 最後彙整失敗清單。agent 本身也是更新目標, 可能造成執行中檔案鎖定; 遇到時請關閉其他 session, 在獨立 terminal 執行 `pwsh -File agent/update-core.ps1`。plugin 更新需重啟 Claude Code session 才生效。

入口的 exit code 是 agent CLI 的結果, 更新腳本的 exit code 以摘要為準; agent 正常結束不代表全部更新成功。

[update.sh](update.sh) 為 macOS 版, 步驟相同 (claude 為 Homebrew 安裝時改用 `brew upgrade --cask claude-code`)。

## ChatGPT Codex

### 佈署

用 [sync_codex.py](src/sync_codex.py) 同步到 Windows 與 WSL（`--pull-win` / `--pull-wsl` 可從 Windows 或 WSL 收回 repo）：`AGENTS.md` 整檔覆寫；`codex-config.toml` 列出的 key（含 `[tui]` 這類 section，頂層 `model` / `model_reasoning_effort` 除外）合併至各自的 `$HOME/.codex/config.toml`，保留既有 model 與未受管設定（用法見 sync 用法）。

- Repo 副本：
  - [AGENTS.md](config/AGENTS.md)
  - [codex-config.toml](config/codex-config.toml)
  保存 approval / sandbox、`[tui]` status line 與 keymap、plugin 啟用狀態等；`AGENTS.md` 保存 Codex global 指引
- `Ctrl+Enter` 換行：透過 `[tui.keymap.editor].insert_newline` 設定，保留預設換行按鍵；一般 `Enter` 仍由 composer 送出。Windows 與 WSL 共用，修改後重啟 Codex CLI 生效。
- 啟用 Auto-Review（[OpenAI Docs](https://learn.chatgpt.com/docs/sandboxing/auto-review)）
  - CLI / 本機 config：repo 已設定 `approval_policy = "on-request"`、`approvals_reviewer = "auto_review"`、`sandbox_mode = "workspace-write"`。

## Claude Code

### 佈署

用 [sync_claude.py](src/sync_claude.py) 同步到 Windows 與 WSL（`--pull-win` / `--pull-wsl` 可從 Windows 或 WSL 收回 repo；`--pull-wsl` 要求 WSL settings.json 等於 repo 合併結果，忽略欄位除外）

- Repo 副本：
  - `CLAUDE.md`、`claude-pstack-models.md`
  - `claude-settings.json` - 母版、Windows 版
  - `claude-settings.wsl.json` - WSL 專屬變更
  - `claude-settings.macos.json` - macOS 專屬變更
  - `claude-keybindings.json` 
  - [claude-statusline.py](config/claude-statusline.py) - status line script，sync 到 `~/.claude/statusline.py`

### 快速鍵
- `Ctrl+P` 切換 model

### Mods (Plugins)
- [next-steps](https://github.com/anthropics/claude-plugins-community/tree/main/next-steps)

## macOS

macOS 不在上方「4 Agents」內，比照 WSL 本機模式：只同步本機 `~/.claude`、`~/.codex`，不查詢 Windows 或 WSL。

- Claude settings：`claude-settings.json` + `claude-settings.macos.json`（statusLine 用 `/usr/bin/python3`，避開 pyenv shim）；Codex 與 Windows／WSL 共用 `AGENTS.md`、`codex-config.toml`。
- `--pull-mac` 收回 repo，要求 `~/.claude/settings.json` 等於 repo 合併結果（忽略欄位除外），相同則略過 settings.json；`--pull-win`、`--pull-wsl`、`--win-only` 在 macOS 不可用。
- venv 放 `agent/.venv/macos/`（見 [sync.py](sync.py) 的 Python 環境）。
- 更新：執行 [update.sh](update.sh)（Claude Code、Codex 及其 plugins / skills）。

## 共同項目

### Status line
Codex 與 Claude Code 共用 `Model · Workspace · 5h · weekly · Context · 用量` 的格式，Claude Code 向 Codex 的外觀對齊（Codex 只能挑內建 item，不能自訂）：

| | Codex（`tui.status_line`） | Claude Code（[claude-statusline.py](config/claude-statusline.py)） |
|---|---|---|
| Model | `model-with-reasoning` | `model.display_name` ＋ effort |
| Workspace | `project-name`、`thread-name` | 專案資料夾名稱（無 thread title） |
| 5h／week | `five-hour-limit`、`weekly-limit`（`5h N% left`） | 同格式 |
| Context | `context-used`（`Context N% used`） | 同格式 |
| 用量 | `used-tokens`（session 累計） | `$1.2`（`cost.total_cost_usd`；stdin JSON 沒有累計 token，故不放 token 數） |

Claude Code 另外依剩餘比例變色（5h／weekly 剩餘或 Context 剩餘 ≤25% 黃、≤10% 紅）；Codex 不隨數值變色，僅 `status_line_use_colors = true` 依 item 類型上色。

### Skills
- [asana-ai-skill](https://github.com/elibosley/asana-ai-skill)（Windows、WSL 各一份 checkout：`~/.agent-skills/sources/asana-ai-skill`；PAT／context／cache 放 `~/.agent-skills/asana/`，兩個 agent 共用）
  - Claude：上游 installer 在 `~/.claude/skills/` 建立 `asana` 與 6 個 `asana-*` entrypoint 連結
  - Codex：只在 `~/.agents/skills/asana` 建一個連結指向 checkout（Windows 用 Junction，WSL 用 `ln -sT`）；Codex 會遞迴掃描並自動找到 `entrypoints/*`，不另建 entrypoint 連結，避免名稱重複
    `New-Item -ItemType Junction -Path $HOME\.agents\skills\asana -Target $HOME\.agent-skills\sources\asana-ai-skill`
  - Codex 的 entrypoint 寫 `../asana/SKILL.md`，從子目錄解析不到，agent 會改從 `asana` 根目錄載入，實測 Win／WSL 都正常
  - Codex sandbox 會擋 Asana API 連線，Windows 還會擋讀取 PAT，所以呼叫時要提權（auto_review 審核）
  - `update-core.ps1`／`update.sh` 會 `git pull` 更新內容；skill 內建的 `update_skill.py` 只 reconcile `~/.claude/skills`、`~/.codex/skills`，不會處理 `~/.agents/skills`
- [herdr-skill]（Windows、WSL 各執行一次；裝到 `~/.agents/skills/herdr`，Codex 直接讀取，Claude Code 以 symlink 連結）：
  `npx skills add herdrdev/herdr --skill herdr -g -a claude-code -a codex -y`
- [wezterm-skill] 本機技能正本放 `.agents/skills/`，`.claude/skills/` 底下用 junction 指過去（git 不會保留 junction，clone 後要重建）：
  `New-Item -ItemType Junction -Path .claude\skills\wezterm -Target .agents\skills\wezterm`
- [pstack](https://github.com/michael-denyer/pstack-claude)
  - Claude 與 Codex plugin 在 Win／WSL 均設為停用，保留 marketplace 來源。Claude 的獨立設定仍放 `claude-pstack-models.md` 並參與 sync；global 指引不再引用它。Codex 的 marketplace 與 plugin 啟用狀態由 `codex-config.toml` 管理，hook trust state 仍由本機維護。
- [Matt-Pocock Skills](https://github.com/mattpocock/skills)
- [diagram-design](https://github.com/cathrynlavery/diagram-design)（manual only；Windows、WSL 各執行一次，裝法同 herdr）：
  `npx skills add cathrynlavery/diagram-design --skill diagram-design -g -a claude-code -a codex -y`
  - Claude：`claude-settings.json` 的 `skillOverrides` 設 `user-invocable-only`，description 不進 context，只能 `/diagram-design` 叫用
  - Codex：`~/.agents/skills/diagram-design/agents/openai.yaml` 設 `policy.allow_implicit_invocation: false`，只能 `$diagram-design` 叫用；skills 重裝會清掉此檔，`update-core.ps1` / `update.sh` 在 `npx skills update` 後補回
- team（本機 global skill，manual only）：以 Herdr 組建多 agent 團隊，當前 agent 為 PM；`/team nexense|claude`（Claude）、`$team nexense|gpt`（Codex）
  - 正本：[agent-skill/team/](../agent-skill/team/SKILL.md)；舊版文件保留在 `agent-team-legacy/`
  - 佈署：`python agent-skill/sync.py --check` / `--push`，把 `team`、`review-pal` 兩個 skill 各自 mirror 到 `~/.claude/skills/<skill>` 與 `~/.agents/skills/<skill>`（複製，不用 symlink）；Windows 執行時一併處理 WSL（`--distro`、`--win-only`），WSL 只處理本機
  - Manual only 設定跟著 skill：`SKILL.md` frontmatter `disable-model-invocation: true`、`agents/openai.yaml` `policy.allow_implicit_invocation: false`
  - 測試：`python agent-skill/test_sync.py`
- review-pal（本機 global skill，manual only）：`team` 的精簡版，不分 PM/Worker；當前 agent 是 Engineer，自己做 plan 與實作，用 Herdr 開一位或多位 Reviewer 先審 plan (`APPROVE-PLAN`)、實作後再審實作 (`APPROVE-IMPLEMENT`)；`/review-pal [<key>[/effort] ...]`（Claude）、`$review-pal [<key>[/effort] ...]`（Codex），不帶引數開一位跨廠牌 Reviewer
  - 正本：[agent-skill/review-pal/](../agent-skill/review-pal/SKILL.md)；佈署與測試同 team
  - key 與模型的對照在 [models.json](../agent-skill/review-pal/models.json)（`sol`、`astra`、`opus`、`fable`、`sonnet`），模型換版只改這個檔

## Project 初始化慣例

- 在 repo root 建立空的 `AGENTS.md`，並讓 `CLAUDE.md` 內容為 `@AGENTS.md`。
- 既有檔案保留，不覆寫。
- 空的 project `AGENTS.md` 不會停用 global 規則。

## 官方參考

- [OpenAI Docs：AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：global / project 搜尋順序、`CODEX_HOME`、`AGENTS.override.md`。
- [OpenAI Docs：Windows / WSL](https://developers.openai.com/codex/windows)：Windows native 與 WSL execution 的區別。
- [Claude Code：Memory](https://code.claude.com/docs/en/memory)：user / project instructions 與 `@AGENTS.md` import（適用不直接讀 AGENTS.md 的 session）。
- [Claude Code：Settings](https://code.claude.com/docs/en/settings)：`CLAUDE_CONFIG_DIR` 與設定範圍。
