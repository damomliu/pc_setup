<#
.SYNOPSIS
    一次更新 Windows 與 WSL 的 Claude Code、Codex 及其 plugins / skills。

.DESCRIPTION
    每個環境依序執行：
      claude update、codex update（各自依安裝方式更新；WSL 的 codex 來自 nvm，先 source ~/.nvm/nvm.sh）
      claude plugin marketplace update、claude plugin update <id> --scope user（Windows 與 WSL 的 plugins 各自獨立，兩邊都更新）
      codex plugin marketplace upgrade
      npx skills update -g -y
      ~/.agent-skills/sources/asana-ai-skill 的 git pull --ff-only（工作目錄不乾淨則警告略過）
    之後讀兩邊 cc-usage@claude-community 的新版本，若與 claude-settings.json / claude-settings.wsl.json
    statusLine.command 內的 /cc-usage/<版本>/ 不同，就改 repo 檔並執行 sync-claude.ps1 -Force（-NoSync 時只提示）；
    有改 repo 檔記得 commit。
    單一步驟失敗只記錄警告並繼續，最後彙整失敗清單，有失敗則 exit 1。
    -SkipWin / -SkipWsl：略過該環境。-NoSync：不自動執行 sync-claude.ps1。
    請在沒有執行中的 claude / codex 的 terminal 執行（更新時 exe 可能被鎖）。
    plugin 更新需重啟 Claude Code session 才生效。
    需要 PowerShell 7。
#>
param(
    [string]$Distro = 'Ubuntu-24.04',
    [switch]$SkipWin,
    [switch]$SkipWsl,
    [switch]$NoSync
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$utf8 = [System.Text.UTF8Encoding]::new($false)
$failures = [System.Collections.Generic.List[string]]::new()

# 執行一個步驟：丟例外或 native 指令 exit code 非 0 都只記錄警告，不中斷
function Invoke-Step([string]$name, [scriptblock]$body) {
    Write-Host "-- $name"
    try {
        & $body
        if ($LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
    } catch {
        Write-Warning "$name 失敗：$($_.Exception.Message)"
        $failures.Add($name)
    }
    $global:LASTEXITCODE = 0
}

# 已安裝的 plugin id：優先 claude plugin list --json，失敗再讀 installed_plugins.json
function Get-PluginIds {
    try {
        $json = claude plugin list --json | Out-String
        if ($LASTEXITCODE) { throw 'claude plugin list 失敗' }
        return @($json | ConvertFrom-Json | ForEach-Object { $_.id })
    } catch {
        Write-Warning "claude plugin list --json 失敗，改讀 installed_plugins.json"
        $global:LASTEXITCODE = 0
        return @((Get-Content "$HOME\.claude\plugins\installed_plugins.json" -Raw | ConvertFrom-Json -AsHashtable).plugins.Keys)
    }
}

# 讀 installed_plugins.json 裡 cc-usage@claude-community 的版本
function Get-CcUsageVersion([string]$root) {
    $f = Join-Path $root '.claude\plugins\installed_plugins.json'
    $j = Get-Content $f -Raw | ConvertFrom-Json -AsHashtable
    $j.plugins['cc-usage@claude-community'][0].version
}

# 把 settings 檔中 /cc-usage/<版本>/ 換成新版本（純文字替換，保留排版與 UTF-8 無 BOM）；回傳是否有改
function Update-CcUsageVersion([string]$file, [string]$ver) {
    $text = [System.IO.File]::ReadAllText($file)
    $new = [regex]::Replace($text, '(/cc-usage/)[^/"\\]+(/)', "`${1}$ver`${2}")
    if ($new -ceq $text) { return $false }
    [System.IO.File]::WriteAllText($file, $new, $utf8)
    Write-Host "已更新 $file -> cc-usage $ver"
    $true
}

# 執行 WSL bash script：寫到 WSL 的 /tmp 再以檔案執行，stdin 保留給 console，
# 指令（例如 codex update）詢問時可直接回答
function Invoke-WslBash([string]$script) {
    $name = "pc_setup-update-$([guid]::NewGuid()).sh"
    $file = "\\wsl.localhost\$Distro\tmp\$name"
    [System.IO.File]::WriteAllText($file, ($script -replace "`r", ''), $utf8)
    try { wsl -d $Distro -- bash -l "/tmp/$name" }
    finally { Remove-Item $file -ErrorAction SilentlyContinue }
}

# 取得 WSL 家目錄
if (-not $SkipWsl) {
    $wslHome = (wsl -d $Distro -- printenv HOME | Out-String).Trim()
    if (-not $wslHome) { throw "讀不到 WSL ($Distro) 的 HOME" }
    $wslRoot = "\\wsl.localhost\$Distro" + ($wslHome -replace '/', '\')
}

if (-not $SkipWin) {
    Write-Host '== Windows =='
    Invoke-Step 'Win: claude update' { claude update }
    Invoke-Step 'Win: codex update' { codex update }
    Invoke-Step 'Win: claude plugin marketplace update' { claude plugin marketplace update }
    Invoke-Step 'Win: claude plugin update' {
        foreach ($id in Get-PluginIds) {
            Write-Host "   $id"
            claude plugin update $id --scope user
            if ($LASTEXITCODE) { Write-Warning "plugin update 失敗：$id"; $failures.Add("Win: plugin $id"); $global:LASTEXITCODE = 0 }
        }
    }
    Invoke-Step 'Win: codex plugin marketplace upgrade' { codex plugin marketplace upgrade }
    Invoke-Step 'Win: npx skills update' { npx -y skills update -g -y }
    Invoke-Step 'Win: asana skill git pull' {
        $asana = Join-Path $HOME '.agent-skills\sources\asana-ai-skill'
        if (-not (Test-Path $asana)) { Write-Host '   不存在，略過'; return }
        if (git -C $asana status --porcelain) { Write-Warning "工作目錄不乾淨，略過 pull：$asana"; return }
        git -C $asana pull --ff-only
    }
}

if (-not $SkipWsl) {
    Write-Host "== WSL ($Distro) =="
    $bash = @'
source ~/.nvm/nvm.sh 2>/dev/null
failed=()
step() {
    local name=$1; shift
    echo "-- WSL: $name"
    if ! "$@"; then
        echo "WARNING: $name failed" >&2
        failed+=("$name")
    fi
}
plugin_ids() {
    local ids
    ids=$(claude plugin list --json | grep -oP '"id":\s*"\K[^"]+') && [ -n "$ids" ] || \
        ids=$(grep -oP '^\s{4}"\K[^"]+@[^"]+(?=":\s*\[)' ~/.claude/plugins/installed_plugins.json)
    printf '%s\n' "$ids"
}
update_plugins() {
    local id rc=0
    for id in $(plugin_ids); do
        echo "   $id"
        claude plugin update "$id" --scope user || { echo "WARNING: plugin update failed: $id" >&2; rc=1; }
    done
    return $rc
}
pull_asana() {
    local d=~/.agent-skills/sources/asana-ai-skill
    [ -d "$d" ] || { echo "   not found, skipped"; return 0; }
    if [ -n "$(git -C "$d" status --porcelain)" ]; then
        echo "WARNING: working tree not clean, skip pull: $d" >&2
        return 1
    fi
    git -C "$d" pull --ff-only
}

step 'claude update' claude update
step 'codex update' codex update
step 'claude plugin marketplace update' claude plugin marketplace update
step 'claude plugin update' update_plugins
step 'codex plugin marketplace upgrade' codex plugin marketplace upgrade
step 'npx skills update' npx -y skills update -g -y
step 'asana skill git pull' pull_asana

if [ ${#failed[@]} -gt 0 ]; then
    printf 'FAILED: %s\n' "${failed[@]}" >&2
fi
exit ${#failed[@]}
'@
    Invoke-WslBash $bash
    if ($LASTEXITCODE) {
        Write-Warning "WSL 有 $LASTEXITCODE 個步驟失敗"
        $failures.Add("WSL: $LASTEXITCODE 個步驟失敗")
    }
    $global:LASTEXITCODE = 0
}

# cc-usage 的 statusLine 路徑寫死版本，plugin 更新後同步 repo 設定
Write-Host '== cc-usage statusLine =='
$changed = $false
$targets = @()
if (-not $SkipWin) { $targets += [pscustomobject]@{ Name = 'Win'; Root = $HOME; File = 'claude-settings.json'; Exe = 'bin\cc-usage-windows-amd64.exe' } }
if (-not $SkipWsl) { $targets += [pscustomobject]@{ Name = 'WSL'; Root = $wslRoot; File = 'claude-settings.wsl.json'; Exe = 'bin\run.sh' } }
foreach ($t in $targets) {
    try {
        $ver = Get-CcUsageVersion $t.Root
        $exe = Join-Path $t.Root ".claude\plugins\cache\claude-community\cc-usage\$ver\$($t.Exe)"
        if (-not (Test-Path $exe)) { throw "找不到新路徑的執行檔：$exe" }
        if (Update-CcUsageVersion (Join-Path $repo $t.File) $ver) { $changed = $true }
        else { Write-Host "$($t.Name): cc-usage $ver 與 $($t.File) 相同" }
    } catch {
        Write-Warning "$($t.Name): cc-usage 路徑修正失敗：$($_.Exception.Message)"
        $failures.Add("$($t.Name): cc-usage statusLine")
    }
}
if ($changed) {
    if ($NoSync) {
        Write-Host 'repo 設定已變更；請執行 ai-agent\sync-claude.ps1 -Force 同步，並記得 commit。'
    } else {
        try {
            & "$PSScriptRoot\sync-claude.ps1" -Force -Distro $Distro
            Write-Host 'repo 設定已變更並已同步；記得 commit。'
        } catch {
            Write-Warning "sync-claude.ps1 失敗：$($_.Exception.Message)"
            $failures.Add('sync-claude.ps1')
        }
    }
}

Write-Host '== 版本 =='
if (-not $SkipWin) {
    Write-Host 'Win:'
    claude --version
    codex --version
    $global:LASTEXITCODE = 0
}
if (-not $SkipWsl) {
    Write-Host 'WSL:'
    Invoke-WslBash 'source ~/.nvm/nvm.sh 2>/dev/null; claude --version; codex --version'
    $global:LASTEXITCODE = 0
}

Write-Host 'plugin 更新需重啟 Claude Code session 才生效。'
if ($failures.Count) {
    Write-Warning "以下步驟失敗：`n  $($failures -join "`n  ")"
    exit 1
}
Write-Host '全部完成。'
