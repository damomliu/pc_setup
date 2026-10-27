#!/usr/bin/env bash
# 一次更新 macOS 的 Claude Code、Codex 及其 plugins / skills。
# 對應 update.ps1（Windows / WSL），步驟相同。相容 macOS 內建 bash 3.2。
#
# 請在沒有執行中的 claude / codex 的 terminal 執行（更新時可能被鎖）。
# plugin 更新需重啟 Claude Code session 才生效。
#
# 依序執行：
#   - claude 更新：claude 實際路徑在 $(brew --prefix) 底下（Homebrew cask）
#     則 brew upgrade --cask claude-code，否則 claude update
#   - codex update（npx / codex 可能來自 nvm，先 source ~/.nvm/nvm.sh）
#   - claude plugin marketplace update
#   - 對每個已安裝的 plugin 執行 claude plugin update <id> --scope user
#     （plugin id 來自 claude plugin list --json，失敗時改讀 ~/.claude/plugins/installed_plugins.json；
#       以 /usr/bin/python3 解析 JSON，避開 pyenv shim）
#   - codex plugin marketplace upgrade
#   - npx -y skills update -g -y
#   - ~/.agent-skills/sources/asana-ai-skill 的 git pull --ff-only
#     （目錄不存在則略過，工作目錄不乾淨則警告並算失敗）
# 最後印出 claude / codex 版本。
# 單一步驟失敗只記錄警告並繼續，最後彙整失敗清單，有失敗則 exit 1。
#
# 用法：./update.sh

# 不用 set -e / set -u：單一步驟失敗需繼續，且 bash 3.2 的空陣列展開會誤報 unbound
source ~/.nvm/nvm.sh 2>/dev/null
failed=()

# 執行一個步驟：指令 exit code 非 0 只記錄警告，不中斷
step() {
    local name=$1; shift
    echo "-- $name"
    if ! "$@"; then
        echo "警告：$name 失敗" >&2
        failed+=("$name")
    fi
}

# claude 為 Homebrew 安裝時用 brew upgrade，否則用 claude update
claude_update() {
    local bin real prefix
    bin=$(command -v claude) || { echo "找不到 claude" >&2; return 1; }
    if command -v brew >/dev/null 2>&1; then
        real=$(realpath "$bin" 2>/dev/null || echo "$bin")
        prefix=$(brew --prefix 2>/dev/null)
        case "$real" in
            "$prefix"/*) brew upgrade --cask claude-code; return $? ;;
        esac
    fi
    claude update
}

# 已安裝的 plugin id：優先 claude plugin list --json，失敗或為空再讀 installed_plugins.json
plugin_ids() {
    local ids
    ids=$(claude plugin list --json 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for p in json.load(sys.stdin):
    print(p["id"])
' 2>/dev/null)
    if [ -z "$ids" ]; then
        echo "警告：claude plugin list --json 失敗，改讀 installed_plugins.json" >&2
        ids=$(/usr/bin/python3 -c '
import json, os, sys
with open(os.path.expanduser("~/.claude/plugins/installed_plugins.json")) as f:
    for k in json.load(f)["plugins"]:
        print(k)
' 2>/dev/null)
    fi
    printf '%s\n' "$ids"
}

update_plugins() {
    local id rc=0
    for id in $(plugin_ids); do
        echo "   $id"
        claude plugin update "$id" --scope user || { echo "警告：plugin update 失敗：$id" >&2; rc=1; }
    done
    return $rc
}

pull_asana() {
    local d=~/.agent-skills/sources/asana-ai-skill
    [ -d "$d" ] || { echo "   不存在，略過"; return 0; }
    if [ -n "$(git -C "$d" status --porcelain)" ]; then
        echo "警告：工作目錄不乾淨，略過 pull：$d" >&2
        return 1
    fi
    git -C "$d" pull --ff-only
}

# 只在直接執行時跑主流程（被 source 時只載入函式，供測試）
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo '== macOS =='
    step 'claude update' claude_update
    step 'codex update' codex update
    step 'claude plugin marketplace update' claude plugin marketplace update
    step 'claude plugin update' update_plugins
    step 'codex plugin marketplace upgrade' codex plugin marketplace upgrade
    step 'npx skills update' npx -y skills update -g -y
    step 'asana skill git pull' pull_asana

    echo '== 版本 =='
    claude --version
    codex --version

    echo 'plugin 更新需重啟 Claude Code session 才生效。'
    if [ ${#failed[@]} -gt 0 ]; then
        echo '以下步驟失敗：' >&2
        printf 'FAILED: %s\n' "${failed[@]}" >&2
        exit 1
    fi
    echo '全部完成。'
fi
