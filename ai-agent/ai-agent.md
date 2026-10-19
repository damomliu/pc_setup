# AI Agent Config

## 4 Agents

| 名稱 | 執行環境 | Agent | Global 規則檔 | Repo 設定來源 |
| --- | --- | --- | --- | --- |
| Win-Claude | Windows | Claude Code | `$HOME/.claude/CLAUDE.md` | `claude-settings.json` |
| Win-Codex | Windows | Codex | `$HOME/.codex/AGENTS.md` | `codex-config.toml` |
| WSL-Claude | WSL | Claude Code | `$HOME/.claude/CLAUDE.md` | `claude-settings.json` + `claude-settings.wsl.json` |
| WSL-Codex | WSL | Codex | `$HOME/.codex/AGENTS.md` | `codex-config.toml` |

統稱：`Win-*`、`WSL-*` 指同一執行環境的兩個 agent；`*-Claude`、`*-Codex` 指同一 agent 的兩個環境；「4 Agents」指全部。

## Global 共用規則

[AGENTS.md](AGENTS.md) 是 4 Agents 共用規則的唯一來源，佈署位置見上表「Global 規則檔」。

WSL 的 `$HOME` 屬於 Linux user；不同 user / distro 各自獨立。設定 `CODEX_HOME` 或 `CLAUDE_CONFIG_DIR` 時，對應檔案改由該目錄讀取。

VSCode 使用哪份規則取決於 backend 實際執行環境；切換 terminal 不等於切換 backend。

[sync.ps1](sync.ps1) 一次執行 `sync-claude.ps1` 與 `sync-codex.ps1`（參數相同）；`-PullWin` / `-PullWsl` 會先確認來源的 `CLAUDE.md` 與 `AGENTS.md` 一致才收回。

[update.ps1](update.ps1) 一次更新 Windows 與 WSL 的 Claude Code、Codex 及其 plugins / `npx skills` / asana skill（`-Distro`、`-SkipWin`、`-SkipWsl`）；單一步驟失敗只警告並繼續，最後彙整失敗清單。請在沒有執行中的 claude / codex 的 terminal 執行；plugin 更新需重啟 session 才生效。

### ChatGPT Codex

#### 佈署

用 [sync-codex.ps1](sync-codex.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo）：`AGENTS.md` 整檔覆寫；`codex-config.toml` 列出的 key（含 `[tui]` 這類 section）合併至各自的 `$HOME/.codex/config.toml`，保留既有 model、MCP 等設定（用法見檔頭）。

- Repo 副本：
  - [AGENTS.md](AGENTS.md)
  - [codex-config.toml](codex-config.toml)
  保存 approval / sandbox 與 `[tui]` status line 設定
- 啟用 Auto-Review（[OpenAI Docs](https://learn.chatgpt.com/docs/sandboxing/auto-review)）
  - CLI / 本機 config：repo 已設定 `approval_policy = "on-request"`、`approvals_reviewer = "auto_review"`、`sandbox_mode = "workspace-write"`。

#### Status line
Codex 與 Claude Code 共用 `Model · Workspace · 5h · weekly · Context · 用量` 的格式，Claude Code 向 Codex 的外觀對齊（Codex 只能挑內建 item，不能自訂）：

| | Codex（`tui.status_line`） | Claude Code（[claude-statusline.py](claude-statusline.py)） |
|---|---|---|
| Model | `model-with-reasoning` | `model.display_name` ＋ effort |
| Workspace | `project-name`、`thread-name` | 專案資料夾名稱（無 thread title） |
| 5h／week | `five-hour-limit`、`weekly-limit`（`5h N% left`） | 同格式 |
| Context | `context-used`（`Context N% used`） | 同格式 |
| 用量 | `used-tokens`（session 累計） | `$1.2`（`cost.total_cost_usd`；stdin JSON 沒有累計 token，故不放 token 數） |

Claude Code 另外依剩餘比例變色（5h／weekly 剩餘或 Context 剩餘 ≤25% 黃、≤10% 紅）；Codex 不隨數值變色，僅 `status_line_use_colors = true` 依 item 類型上色。

#### 快速鍵
- CLI：`/model` 切換 model、`/permissions` 調整權限、`/status` 查看 session 狀態；`Ctrl+R` 搜尋 prompt history，`/keymap` 調整 TUI 快速鍵（[OpenAI Docs](https://learn.chatgpt.com/docs/developer-commands?surface=cli)）。

### Claude Code

#### 佈署

用 [sync-claude.ps1](sync-claude.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo；`-PullWsl` 要求 WSL settings.json 等於 repo 合併結果）

- Repo 副本：
  - `AGENTS.md`
  - `claude-settings.json` - 母版、Windows 版
  - `claude-settings.wsl.json` - WSL 專屬變更
  - `claude-settings.cli.json` - CLI session 覆寫設定，Remote Control 啟動值為 `false`
  - `claude-keybindings.json` 
  - [claude-statusline.py](claude-statusline.py) - status line script，sync 到 `~/.claude/statusline.py`
- `claude` function 會載入 `settings.cli.json`；目前 CLI session 不會自動啟用 Remote Control

#### 快速鍵
- `Ctrl+P` 切換 model

#### Mods (Plugins)
- [next-steps](https://github.com/anthropics/claude-plugins-community/tree/main/next-steps)

## Project 初始化慣例

- 在 repo root 建立空的 `AGENTS.md`，並讓 `CLAUDE.md` 內容為 `@AGENTS.md`。
- 既有檔案保留，不覆寫。
- 空的 project `AGENTS.md` 不會停用 global 規則。

## 官方參考

- [OpenAI Docs：AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：global / project 搜尋順序、`CODEX_HOME`、`AGENTS.override.md`。
- [OpenAI Docs：Windows / WSL](https://developers.openai.com/codex/windows)：Windows native 與 WSL execution 的區別。
- [Claude Code：Memory](https://code.claude.com/docs/en/memory)：user / project instructions 與 `@AGENTS.md` import（適用不直接讀 AGENTS.md 的 session）。
- [Claude Code：Settings](https://code.claude.com/docs/en/settings)：`CLAUDE_CONFIG_DIR` 與設定範圍。
