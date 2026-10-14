# AI Agent Config

## Global 共用規則

[AGENTS.md](AGENTS.md) 是 Codex 與 Claude Code 共用規則的唯一來源。

| 執行環境 | Codex | Claude Code |
| --- | --- | --- |
| Windows | `$HOME/.codex/AGENTS.md` | `$HOME/.claude/CLAUDE.md` |
| WSL | `$HOME/.codex/AGENTS.md` | `$HOME/.claude/CLAUDE.md` |

WSL 的 `$HOME` 屬於 Linux user；不同 user / distro 各自獨立。設定 `CODEX_HOME` 或 `CLAUDE_CONFIG_DIR` 時，對應檔案改由該目錄讀取。

VSCode 使用哪份規則取決於 backend 實際執行環境；切換 terminal 不等於切換 backend。

[sync.ps1](sync.ps1) 一次執行 `sync-claude.ps1` 與 `sync-codex.ps1`（參數相同）；`-PullWin` / `-PullWsl` 會先確認來源的 `CLAUDE.md` 與 `AGENTS.md` 一致才收回。

### ChatGPT Codex

#### 佈署

用 [sync-codex.ps1](sync-codex.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo）：`AGENTS.md` 整檔覆寫；`codex-config.toml` 的 top-level key 合併至各自的 `$HOME/.codex/config.toml`，保留既有 model、MCP 等設定（用法見檔頭）。

- Repo 副本：
  - [AGENTS.md](AGENTS.md)
  - [codex-config.toml](codex-config.toml)
  保存 approval / sandbox 設定
- 啟用 Auto-Review（[OpenAI Docs](https://learn.chatgpt.com/docs/sandboxing/auto-review)）
  - CLI / 本機 config：repo 已設定 `approval_policy = "on-request"`、`approvals_reviewer = "auto_review"`、`sandbox_mode = "workspace-write"`。

#### 快速鍵
- CLI：`/model` 切換 model、`/permissions` 調整權限、`/status` 查看 session 狀態；`Ctrl+R` 搜尋 prompt history，`/keymap` 調整 TUI 快速鍵（[OpenAI Docs](https://learn.chatgpt.com/docs/developer-commands?surface=cli)）。

### Claude Code

#### 佈署

用 [sync-claude.ps1](sync-claude.ps1) 同步到 Windows 與 WSL（`-PullWin` / `-PullWsl` 可從 Windows 或 WSL 收回 repo；`-PullWsl` 要求 WSL settings.json 等於 repo 合併結果）

- Repo 副本：
  - `AGENTS.md`
  - `claude-settings.json` - 母版、Windows 版
  - `claude-settings.wsl.json` - WSL 專屬變更
  - `claude-settings.cli.json` - 
  - `claude-keybindings.json` 
- 從 CLI 開的 session 會自動啟用 Remote Control. 參考 `power_shell\profile.ps1` 的 `claude` function

#### 快速鍵
- `Ctrl+P` 切換 model

#### Mods (Plugins)
- [next-steps](https://github.com/anthropics/claude-plugins-community/tree/main/next-steps)
- [cc-usage](https://github.com/zipkero/cc-usage)
  - community marketplace 的 statusLine 版（`cc-usage@claude-community`）顯示 model／cost／5h／7d usage

## Project 初始化慣例

- 在 repo root 建立空的 `AGENTS.md`，並讓 `CLAUDE.md` 內容為 `@AGENTS.md`。
- 既有檔案保留，不覆寫。
- 空的 project `AGENTS.md` 不會停用 global 規則。

## 官方參考

- [OpenAI Docs：AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：global / project 搜尋順序、`CODEX_HOME`、`AGENTS.override.md`。
- [OpenAI Docs：Windows / WSL](https://developers.openai.com/codex/windows)：Windows native 與 WSL execution 的區別。
- [Claude Code：Memory](https://code.claude.com/docs/en/memory)：user / project instructions 與 `@AGENTS.md` import（適用不直接讀 AGENTS.md 的 session）。
- [Claude Code：Settings](https://code.claude.com/docs/en/settings)：`CLAUDE_CONFIG_DIR` 與設定範圍。
