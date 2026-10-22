<#
.SYNOPSIS
    sync.ps1 / sync-claude.ps1 / sync-codex.ps1 的隔離整合測試（PowerShell 7，無外部依賴）。

.DESCRIPTION
    每個情境在暫存目錄建立 repo、Windows home、WSL home，並把同步腳本複製進暫存 repo，
    以 CLI 執行（隱藏參數 -TestWinHome / -TestWslRoot），只檢查檔案與輸出等可觀察結果。
    不會碰真實 repo 來源以外的檔案、真實 home 或 WSL；"real sources" 情境只讀取 repo 內的來源檔。
    用法：pwsh -NoProfile -File ai-agent/test-sync.ps1
#>
param([string]$Only = '*')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$pwsh = (Get-Process -Id $PID).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)
$here = $PSScriptRoot
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("sync-test-" + [guid]::NewGuid().ToString('N'))
$script:total = 0; $script:failed = 0

function Assert($cond, [string]$msg) {
    $script:total++
    if (-not $cond) { $script:failed++; Write-Host "  FAIL: $msg" -ForegroundColor Red }
}
function Case([string]$name, [scriptblock]$body) {
    if ($name -notlike $Only) { return }
    Write-Host "# $name"
    try { & $body } catch { $script:failed++; Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red; Write-Host $_.ScriptStackTrace }
}
function W([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}
function ReadF([string]$path) { [System.IO.File]::ReadAllText($path) }
function EditJson([string]$path, [scriptblock]$edit) {
    $o = ReadF $path | ConvertFrom-Json -AsHashtable
    & $edit $o
    W $path (($o | ConvertTo-Json -Depth 32) + "`n")
}
function Snap([string]$dir) {
    (Get-ChildItem $dir -Recurse -File | Sort-Object FullName | ForEach-Object {
        "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)|$((Get-FileHash $_.FullName).Hash)"
    }) -join "`n"
}

$block = @'
<!-- pstack-models:begin -->
# pstack model configuration

feature, refactoring: gpt-x
arena runners: gpt-a, gpt-b

default effort: session
session hook: off
<!-- pstack-models:end -->
'@
$block = $block -replace "`r`n", "`n"
$fixtures = @{
    'claude-settings.json'     = '{"permissions":{"allow":["A","B"]},"model":"sonnet","effortLevel":"medium","modelSettings":{"m1":{"effortLevel":"medium"}},"theme":"dark","count":1,"nested":{"ok":"visible-repo"},"env":{"X":"REPOENV"},"myToken":"REPOTOK"}'
    'claude-settings.wsl.json' = '{"permissions":{"allow":["B","C"]},"statusLine":{"command":"wsl-status"}}'
    'claude-keybindings.json'  = '{"bindings":[{"action":"x"}]}'
    'claude-statusline.py'     = "print(1)`n"
    'CLAUDE.md'                = "# rules`n`n@~/.claude/pstack-models.md`n"
    'claude-pstack-models.md'  = "# pstack`n`nfeature, refactoring: sonnet`n`ndefault effort: session`nsession hook: off`n"
    'AGENTS.md'                = "# rules`n`n- be nice`n`n$block`n"
    'codex-config.toml'        = "model = `"gpt-x`"`nmodel_reasoning_effort = `"medium`"`napproval_policy = `"on-request`"`n`n[tui]`nstatus_line = [`"a`", `"b`"]`n`n[tui.keymap.editor]`ninsert_newline = [`"ctrl-enter`"]`n`n[tools.env]`nA = `"REPOTOML`"`n"
}

function New-Env([switch]$RealSources) {
    $root = Join-Path $work ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $e = [pscustomobject]@{ Root = $root; Repo = "$root\repo"; Win = "$root\win"; Wsl = "$root\wsl"; Bin = "$root\bin" }
    foreach ($d in $e.Repo, $e.Win, $e.Wsl, $e.Bin) { New-Item -ItemType Directory -Force $d | Out-Null }
    foreach ($f in 'sync.ps1', 'sync-claude.ps1', 'sync-codex.ps1', 'sync-common.ps1') { Copy-Item "$here\$f" $e.Repo }
    foreach ($f in $fixtures.Keys) {
        if ($RealSources) { Copy-Item "$here\$f" $e.Repo } else { W "$($e.Repo)\$f" $fixtures[$f] }
    }
    # 假的 wsl：被呼叫就留下標記並失敗
    W "$($e.Bin)\wsl.cmd" "@echo called>`"%~dp0called.txt`"`r`n@exit /b 1`r`n"
    $e
}

# 以 CLI 執行腳本；預設附上成對的測試路徑。只在 PATH 前面加入假 wsl 以偵測是否被呼叫，不改任何 home 變數
function Run($e, [string]$script, [string[]]$a = @(), [switch]$NoTestPaths) {
    if (-not $NoTestPaths) { $a += '-TestWinHome', $e.Win, '-TestWslRoot', $e.Wsl }
    $savedPath = $env:PATH
    $env:PATH = "$($e.Bin);$env:PATH"
    try { $out = & $pwsh -NoProfile -File "$($e.Repo)\$script" @a 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { $env:PATH = $savedPath }
    [pscustomobject]@{ Out = $out; Code = $code }
}
function Pushed() { $e = New-Env; $r = Run $e 'sync.ps1'; Assert ($r.Code -eq 0) "初次推送應成功：$($r.Out)"; $e }
function Untouched($e) { -not (Test-Path "$($e.Bin)\called.txt") }

# ---------------------------------------------------------------------------
try {
    New-Item -ItemType Directory -Force $work | Out-Null

    Case 'syntax' {
        foreach ($f in 'sync.ps1', 'sync-claude.ps1', 'sync-codex.ps1', 'sync-common.ps1', 'test-sync.ps1') {
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile("$here\$f", [ref]$null, [ref]$errs) | Out-Null
            Assert (-not $errs) "$f 語法錯誤"
        }
    }

    Case '各工具自己的指引、pstack 配套檔與忽略欄位首次建立' {
        $e = Pushed
        foreach ($h in $e.Win, $e.Wsl) {
            Assert ((ReadF "$h\.claude\CLAUDE.md") -ceq (ReadF "$($e.Repo)\CLAUDE.md")) 'Claude 指引內容'
            Assert ((ReadF "$h\.claude\CLAUDE.md") -notmatch 'C:|/home/') 'Claude 引用不含環境專屬路徑'
            Assert ((ReadF "$h\.claude\pstack-models.md") -ceq (ReadF "$($e.Repo)\claude-pstack-models.md")) 'Claude pstack 設定'
            Assert ((ReadF "$h\.codex\AGENTS.md") -ceq (ReadF "$($e.Repo)\AGENTS.md")) 'Codex 指引內容'
            Assert ((ReadF "$h\.codex\AGENTS.md") -cne (ReadF "$h\.claude\CLAUDE.md")) '兩工具指引各自獨立'
            $derived = ReadF "$h\.codex\pstack-models.md"
            $inner = ((ReadF "$($e.Repo)\AGENTS.md") -split "(?m)^<!-- pstack-models:(?:begin|end) -->\r?\n")[1]
            Assert ($derived -ceq $inner) '配套檔等於 pstack 區塊內容'
            foreach ($line in 'feature, refactoring: gpt-x', 'arena runners: gpt-a, gpt-b', 'default effort: session', 'session hook: off') {
                Assert ($derived.Contains($line)) "配套檔含「$line」"
            }
            Assert ($derived -notmatch 'pstack-models:') '配套檔不含標記'
            $s = ReadF "$h\.claude\settings.json" | ConvertFrom-Json -AsHashtable
            Assert (-not $s.ContainsKey('model') -and -not $s.ContainsKey('effortLevel')) '忽略欄位首次建立不補入'
            Assert ($s.modelSettings.m1.effortLevel -eq 'medium') 'modelSettings effort 仍受管'
            $c = ReadF "$h\.codex\config.toml"
            Assert ($c -notmatch '(?m)^model') 'Codex 忽略欄位不補入'
            Assert ($c -match 'approval_policy = "on-request"') 'Codex 受管 key 建立'
        }
        $w = ReadF "$($e.Wsl)\.claude\settings.json" | ConvertFrom-Json -AsHashtable
        Assert ($w.statusLine.command -eq 'wsl-status') 'WSL overlay 合併'
        Assert (($w.permissions.allow -join ',') -eq 'A,B,C') 'WSL permissions 聯集'
        Assert (-not (Test-Path "$($e.Repo)\codex-pstack-models.md")) 'repo 沒有第二份 Codex pstack 來源'
        Assert (Untouched $e) '沒有呼叫 WSL'
    }

    Case 'Codex pstack 區塊無法解析：推送不寫任何目標' {
        $bad = @{
            'missing end'  = ($fixtures['AGENTS.md'] -replace '<!-- pstack-models:end -->', '')
            'missing hook' = ($fixtures['AGENTS.md'] -replace 'session hook: off', '')
            'no roles'     = "# r`n<!-- pstack-models:begin -->`ndefault effort: session`nsession hook: off`n<!-- pstack-models:end -->`n"
            'bad line'     = ($fixtures['AGENTS.md'] -replace 'gpt-a, gpt-b', 'gpt-a, gpt-b`nnot a setting line' -replace '`n', "`n")
            'empty block'  = "<!-- pstack-models:begin -->`n<!-- pstack-models:end -->`n"
            'hook typo'    = $fixtures['AGENTS.md'].Replace('session hook: off', 'session hook: of')
            'hook spaced'  = $fixtures['AGENTS.md'].Replace('session hook: off', 'session hook : off')
            'hook value'   = $fixtures['AGENTS.md'].Replace('session hook: off', 'session hook: maybe')
        }
        $bad['bad line'] = $fixtures['AGENTS.md'].Replace("default effort: session", "just words`ndefault effort: session")
        foreach ($k in $bad.Keys) {
            $e = New-Env; W "$($e.Repo)\AGENTS.md" $bad[$k]
            # 單獨的 Codex 同步器：本次所有目標都不變
            $before = Snap $e.Root
            $r = Run $e 'sync-codex.ps1'
            Assert ($r.Code -ne 0) "[$k] sync-codex.ps1 應失敗"
            Assert ((Snap $e.Root) -ceq $before) "[$k] 不得寫入任何目標"
            Assert ($r.Out -notmatch 'just words') "[$k] 診斷不回顯內容"
            # 總入口：Claude 先跑可能已寫入（不做跨工具 transaction），只要求 Codex 目標不寫
            $r = Run $e 'sync.ps1'
            Assert ($r.Code -ne 0) "[$k] sync.ps1 應失敗"
            Assert (@(Get-ChildItem $e.Win, $e.Wsl -Recurse -File | Where-Object FullName -like '*\.codex\*').Count -eq 0) "[$k] 總入口不得寫入 Codex 目標"
        }
    }

    Case 'pstack 區塊行正規化：前置空白不會讓 hook 讀不到整行' {
        $e = New-Env
        W "$($e.Repo)\AGENTS.md" ($fixtures['AGENTS.md'].Replace('session hook: off', '  session hook:   on').Replace('default effort: session', "`tdefault effort:  high  "))
        $r = Run $e 'sync-codex.ps1'
        Assert ($r.Code -eq 0) "可推送：$($r.Out)"
        $d = ReadF "$($e.Win)\.codex\pstack-models.md"
        Assert ($d -cmatch '(?m)^session hook: on$') '產物含精確整行 session hook: on'
        Assert ($d -cmatch '(?m)^default effort: high$') '產物含精確整行 default effort'
        Assert ($d -notmatch '(?m)^[ \t]+\S') '產物沒有前置空白行'
    }

    Case '字串大小寫有意義（JSON 與 TOML）' {
        $e = Pushed
        EditJson "$($e.Repo)\claude-settings.json" { param($o) $o['name'] = 'Value' }
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['name'] = 'value' }
        $r = Run $e 'sync-claude.ps1' @('-CheckVerbose')
        Assert ($r.Out -match 'differs' -and $r.Out -match 'name: "value" → "Value"') "JSON 大小寫差異：$($r.Out)"
        W "$($e.Repo)\codex-config.toml" ((ReadF "$($e.Repo)\codex-config.toml").Replace('"on-request"', '"CaseValue"'))
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Win)\.codex\config.toml").Replace('"on-request"', '"casevalue"'))
        $r = Run $e 'sync-codex.ps1' @('-CheckVerbose')
        Assert ($r.Out -match 'differs' -and $r.Out -match 'approval_policy: "casevalue" → "CaseValue"') "TOML 大小寫差異：$($r.Out)"
        # section 名稱區分大小寫：[TUI] 不是 [tui]
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Repo)\codex-config.toml").Replace('[tui]', '[TUI]'))
        $r = Run $e 'sync-codex.ps1' @('-CheckVerbose')
        Assert ($r.Out -match 'status_line: \(missing\)') "[TUI] 與 [tui] 視為不同 section：$($r.Out)"
    }

    Case 'Codex Pull：驗證來源區塊、不用配套檔反寫、失敗不動 repo' {
        $e = Pushed
        # 單獨修改配套檔
        W "$($e.Win)\.codex\pstack-models.md" "DERIVED-EDIT`n"
        $v = Run $e 'sync-codex.ps1' @('-CheckVerbose')
        Assert ($v.Code -eq 0 -and $v.Out -match 'DERIVED-EDIT' -and $v.Out -match 'pstack-models\.md') 'CheckVerbose 顯示配套檔差異'
        $agentsBefore = ReadF "$($e.Repo)\AGENTS.md"
        $r = Run $e 'sync-codex.ps1' @('-PullWin')
        Assert ($r.Code -eq 0) "Pull 成功：$($r.Out)"
        Assert ((ReadF "$($e.Repo)\AGENTS.md") -ceq $agentsBefore) 'Pull 不用配套檔覆蓋指引'
        # 來源指引改角色 -> repo 收回
        W "$($e.Win)\.codex\AGENTS.md" ($agentsBefore.Replace('feature, refactoring: gpt-x', 'feature, refactoring: gpt-y'))
        $r = Run $e 'sync-codex.ps1' @('-PullWin')
        Assert ($r.Code -eq 0 -and (ReadF "$($e.Repo)\AGENTS.md").Contains('gpt-y')) 'Pull 以來源指引為準'
        # 來源區塊缺少或無法解析
        foreach ($bad in ($agentsBefore -replace '<!-- pstack-models:begin -->', ''), $agentsBefore.Replace('session hook: off', 'oops')) {
            W "$($e.Wsl)\.codex\AGENTS.md" $bad
            W "$($e.Wsl)\.codex\config.toml" ((ReadF "$($e.Wsl)\.codex\config.toml").Replace('on-request', 'never'))
            $before = Snap $e.Repo
            $r = Run $e 'sync-codex.ps1' @('-PullWsl')
            Assert ($r.Code -ne 0) '來源區塊不合法時 Pull 失敗'
            Assert ((Snap $e.Repo) -ceq $before) 'Pull 失敗時 repo 檔案全不變'
        }
    }

    Case '不同工具指引不同時 Pull 不再中止' {
        $e = Pushed
        $r = Run $e 'sync.ps1' @('-PullWin')
        Assert ($r.Code -eq 0) "sync.ps1 -PullWin：$($r.Out)"
        $r = Run $e 'sync.ps1' @('-PullWsl')
        Assert ($r.Code -eq 0) "sync.ps1 -PullWsl：$($r.Out)"
    }

    Case '只有忽略欄位不同：same，檢查與同步都不改檔' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['model'] = 'LOCALMODEL'; $o['effortLevel'] = 'high' }
        EditJson "$($e.Wsl)\.claude\settings.json" { param($o) $o['model'] = 'WSLMODEL' }
        foreach ($h in $e.Win, $e.Wsl) {
            W "$h\.codex\config.toml" ("model = `"local`"`nmodel_reasoning_effort = `"high`"`n" + (ReadF "$h\.codex\config.toml"))
        }
        $before = Snap $e.Root
        foreach ($mode in @('-Check'), @('-CheckVerbose'), @()) {
            $r = Run $e 'sync.ps1' $mode
            Assert ($r.Code -eq 0) "[$mode] 成功：$($r.Out)"
            Assert ($r.Out -notmatch 'differs|missing|update') "[$mode] 全部 same"
            Assert ($r.Out -notmatch 'LOCALMODEL|WSLMODEL|effortLevel') "[$mode] 忽略欄位不出現"
        }
        Assert ((Snap $e.Root) -ceq $before) '沒有任何檔案被改寫'
    }

    Case 'Force 更新受管內容並保留各目標的忽略欄位' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['theme'] = 'light'; $o['model'] = 'LOCALMODEL' }
        EditJson "$($e.Wsl)\.claude\settings.json" { param($o) $o['theme'] = 'light'; $o['effortLevel'] = 'WSLEFF' }
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Win)\.codex\config.toml").Replace('on-request', 'never').Replace("approval_policy", "model = `"mine`"`nfoo = 1`napproval_policy"))
        $before = Snap $e.Root
        $r = Run $e 'sync.ps1'
        Assert ($r.Code -ne 0) '沒有 -Force 時中止'
        Assert ((Snap $e.Root) -ceq $before) '中止時不寫入'
        $r = Run $e 'sync.ps1' @('-Force')
        Assert ($r.Code -eq 0) "Force：$($r.Out)"
        $w = ReadF "$($e.Win)\.claude\settings.json" | ConvertFrom-Json -AsHashtable
        Assert ($w.theme -eq 'dark' -and $w.model -eq 'LOCALMODEL' -and -not $w.ContainsKey('effortLevel')) 'Win 受管更新、model 保留、缺值不補'
        $s = ReadF "$($e.Wsl)\.claude\settings.json" | ConvertFrom-Json -AsHashtable
        Assert ($s.theme -eq 'dark' -and $s.effortLevel -eq 'WSLEFF' -and -not $s.ContainsKey('model')) 'WSL 各自保留'
        $c = ReadF "$($e.Win)\.codex\config.toml"
        Assert ($c -match 'approval_policy = "on-request"' -and $c -match 'model = "mine"' -and $c -match 'foo = 1') 'Codex 受管更新、model 與額外 key 保留'
        Assert ($c -notmatch 'model_reasoning_effort') 'Codex 缺少的忽略欄位不補入'
    }

    Case 'Codex 只缺受管 key 時直接補入，不補忽略欄位' {
        $e = Pushed
        W "$($e.Wsl)\.codex\config.toml" "model = `"mine`"`n"
        $r = Run $e 'sync-codex.ps1'
        Assert ($r.Code -eq 0) "update 不需 Force：$($r.Out)"
        $c = ReadF "$($e.Wsl)\.codex\config.toml"
        Assert ($c -match 'model = "mine"' -and $c -match 'approval_policy' -and $c -notmatch 'model_reasoning_effort') '補入受管 key'
    }

    Case 'Pull 保留 repo 的忽略欄位' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['model'] = 'WINMODEL'; $o['theme'] = 'light'; $o['effortLevel'] = 'zz' }
        EditJson "$($e.Repo)\claude-settings.json" { param($o) $o.Remove('effortLevel') }
        W "$($e.Win)\.codex\config.toml" ("model = `"winmodel`"`n" + (ReadF "$($e.Win)\.codex\config.toml").Replace('on-request', 'never').Replace('model = "gpt-x"', ''))
        $r = Run $e 'sync.ps1' @('-PullWin')
        Assert ($r.Code -eq 0) "Pull：$($r.Out)"
        $s = ReadF "$($e.Repo)\claude-settings.json" | ConvertFrom-Json -AsHashtable
        Assert ($s.theme -eq 'light' -and $s.model -eq 'sonnet' -and -not $s.ContainsKey('effortLevel')) 'repo 忽略欄位維持、不新增'
        $t = ReadF "$($e.Repo)\codex-config.toml"
        Assert ($t -match 'model = "gpt-x"' -and $t -match 'model_reasoning_effort = "medium"' -and $t -match 'approval_policy = "never"') 'Codex repo 忽略欄位維持，受管回收'
    }

    Case 'Claude 巢狀 effort 是受管差異' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['modelSettings']['m1']['effortLevel'] = 'high' }
        $r = Run $e 'sync-claude.ps1' @('-CheckVerbose')
        Assert ($r.Out -match 'differs' -and $r.Out -match 'modelSettings\.m1\.effortLevel: "high" → "medium"') "辨識差異：$($r.Out)"
        Assert ((Run $e 'sync-claude.ps1').Code -ne 0) '推送需 Force'
        Assert ((Run $e 'sync-claude.ps1' @('-Force')).Code -eq 0) 'Force 可推送'
        Assert ((ReadF "$($e.Win)\.claude\settings.json" | ConvertFrom-Json -AsHashtable).modelSettings.m1.effortLevel -eq 'medium') '推送還原'
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['modelSettings']['m1']['effortLevel'] = 'high' }
        Assert ((Run $e 'sync-claude.ps1' @('-PullWin')).Code -eq 0) 'Pull 成功'
        Assert ((ReadF "$($e.Repo)\claude-settings.json" | ConvertFrom-Json -AsHashtable).modelSettings.m1.effortLevel -eq 'high') 'Pull 回收巢狀 effort'
    }

    Case 'WSL overlay 與本機忽略欄位' {
        $e = Pushed
        EditJson "$($e.Wsl)\.claude\settings.json" { param($o) $o['model'] = 'WSLMODEL' }
        $repoBefore = ReadF "$($e.Repo)\claude-settings.json"
        $r = Run $e 'sync-claude.ps1' @('-PullWsl')
        Assert ($r.Code -eq 0) "只有忽略欄位不同不阻擋 PullWsl：$($r.Out)"
        Assert ((ReadF "$($e.Repo)\claude-settings.json") -ceq $repoBefore) 'PullWsl 略過 settings.json'
        EditJson "$($e.Wsl)\.claude\settings.json" { param($o) $o['theme'] = 'light' }
        $before = Snap $e.Repo
        $r = Run $e 'sync-claude.ps1' @('-PullWsl')
        Assert ($r.Code -ne 0 -and (Snap $e.Repo) -ceq $before) '受管設定不同時中止且不收回任何檔案'
    }

    Case '排序與排版不影響比對，array 順序與型別會' {
        $e = Pushed
        $s = ReadF "$($e.Win)\.claude\settings.json" | ConvertFrom-Json -AsHashtable
        $rev = [ordered]@{}; foreach ($k in $s.Keys | Sort-Object -Descending) { $rev[$k] = $s[$k] }
        W "$($e.Win)\.claude\settings.json" ($rev | ConvertTo-Json -Depth 32 -Compress)
        W "$($e.Win)\.codex\config.toml" "approval_policy = `"on-request`"`n`n[tui.keymap.editor]`ninsert_newline = [`"ctrl-enter`"]`n`n[tools.env]`nA = `"REPOTOML`"`n`n[tui]`nstatus_line = [`"a`", `"b`"]`n"
        $r = Run $e 'sync.ps1' @('-Check')
        Assert ($r.Code -eq 0 -and $r.Out -notmatch 'differs|update|missing') "換序／排版為 same：$($r.Out)"
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['permissions']['allow'] = @('B', 'A') }
        Assert ((Run $e 'sync-claude.ps1' @('-Check')).Out -match 'differs') 'JSON array 換序為 differs'
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['permissions']['allow'] = @('A', 'B'); $o['count'] = '1' }
        Assert ((Run $e 'sync-claude.ps1' @('-Check')).Out -match 'differs') '型別改變為 differs'
        EditJson "$($e.Win)\.claude\settings.json" { param($o) $o['count'] = 1 }
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Win)\.codex\config.toml").Replace('["a", "b"]', '["b", "a"]'))
        Assert ((Run $e 'sync-codex.ps1' @('-Check')).Out -match 'differs') 'TOML array 換序為 differs'
    }

    Case 'CheckVerbose 單獨使用即唯讀，並顯示總覽、設定與文字差異' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\keybindings.json" { param($o) $o['bindings'][0]['action'] = 'changed' }
        W "$($e.Wsl)\.claude\CLAUDE.md" "# other rules`n"
        Remove-Item "$($e.Win)\.claude\statusline.py"
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Win)\.codex\config.toml").Replace('["ctrl-enter"]', '["ctrl-j"]'))
        $before = Snap $e.Root
        $r = Run $e 'sync.ps1' @('-CheckVerbose')
        Assert ($r.Code -eq 0) "成功：$($r.Out)"
        Assert ($r.Out -match '(?m)^missing +.*statusline\.py') 'missing 總覽'
        Assert ($r.Out -match '(?m)^same +') 'same 總覽'
        Assert ($r.Out -match '(?m)^differs +.*keybindings\.json') 'differs 總覽'
        Assert ($r.Out -match 'bindings\[0\]\.action: "changed" → "x"') 'JSON 路徑與本機 → 預期'
        Assert ($r.Out -match 'tui\.keymap\.editor\.insert_newline: \["ctrl-j"\] → \["ctrl-enter"\]') '非敏感 TOML 值顯示'
        Assert ($r.Out -match '(?m)^\s+- # other rules' -and $r.Out -match '(?m)^\s+\+ # rules') '文字逐行 diff'
        Assert ((Snap $e.Root) -ceq $before) '來源與目標 bytes、修改時間不變，也不建立缺少的檔案'
        $c = Run $e 'sync.ps1' @('-Check')
        Assert ($c.Out -notmatch 'changed|other rules') '-Check 只有總覽'
    }

    Case '敏感值遮蔽與忽略欄位不外洩' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\settings.json" { param($o)
            $o['model'] = 'LEAKMODEL'; $o['env'] = @{ X = 'LEAKENV' }; $o['myToken'] = 'LEAKTOK'
            $o['nested'] = @{ ok = 'visible-local'; apiKey = 'LEAKKEY' }; $o['auth'] = @{ deep = @{ v = 'LEAKAUTH' } }
        }
        W "$($e.Win)\.codex\config.toml" ((ReadF "$($e.Win)\.codex\config.toml").Replace('REPOTOML', 'LEAKTOML') + "model = `"LEAKCODEXMODEL`"`n")
        $all = ''
        $v = Run $e 'sync.ps1' @('-CheckVerbose'); $all += $v.Out
        foreach ($a in @('-CheckVerbose'), @(), @('-Force')) {
            $r = Run $e 'sync-claude.ps1' $a; $all += $r.Out
            $r = Run $e 'sync-codex.ps1' $a; $all += $r.Out
            if ($a -contains '-Force') { break }
        }
        Assert ($all -notmatch 'LEAK') "敏感值或忽略欄位外洩：$($all -replace '(?s).*(LEAK\w*).*', '$1')"
        Assert ($v.Out -match 'nested\.ok: "visible-local" → "visible-repo"' -and $v.Out -match '\*\*\*') '非敏感值仍顯示、敏感值為 ***'
    }

    Case '壞掉的 JSON 診斷不帶出內容' {
        $e = Pushed
        W "$($e.Win)\.claude\settings.json" '{"env": {"X": "LEAKBAD"} oops'
        $r = Run $e 'sync-claude.ps1' @('-CheckVerbose')
        Assert ($r.Code -ne 0 -and $r.Out -notmatch 'LEAK') "診斷不洩漏：$($r.Out)"
    }

    Case 'Check／CheckVerbose 與 Pull／Force 衝突、兩種 Pull 互斥：I/O 前拒絕' {
        $e = Pushed
        $conflicts = @(@('-Check', '-Force'), @('-CheckVerbose', '-PullWin'), @('-Check', '-PullWsl'), @('-CheckVerbose', '-Force'), @('-PullWin', '-PullWsl'))
        foreach ($s in 'sync.ps1', 'sync-claude.ps1', 'sync-codex.ps1') {
            foreach ($c in $conflicts) {
                $before = Snap $e.Root
                $r = Run $e $s $c
                Assert ($r.Code -ne 0) "$s $($c -join ' ') 應失敗"
                Assert ((Snap $e.Root) -ceq $before) "$s $($c -join ' ') 不得寫入"
                $r2 = Run $e $s $c -NoTestPaths
                Assert ($r2.Code -ne 0 -and (Untouched $e)) "$s $($c -join ' ') 在 WSL 呼叫前拒絕"
            }
        }
    }

    Case '測試路徑必須成對，成對時不呼叫 WSL' {
        $e = New-Env
        foreach ($s in 'sync.ps1', 'sync-claude.ps1', 'sync-codex.ps1') {
            foreach ($one in @('-TestWinHome', $e.Win), @('-TestWslRoot', $e.Wsl)) {
                $r = Run $e $s (@('-Check') + $one) -NoTestPaths
                Assert ($r.Code -ne 0 -and $r.Out -match '成對') "$s 單獨 $($one[0]) 拒絕"
            }
            $r = Run $e $s @('-CheckVerbose')
            Assert ($r.Code -eq 0) "$s 成對時可執行"
        }
        Assert (Untouched $e) '沒有呼叫 WSL'
        Assert (@(Get-ChildItem $e.Win, $e.Wsl -Recurse -File).Count -eq 0) '檢查不建立檔案'
    }

    Case '總入口：第一個同步器失敗後不執行第二個，輸出與個別同步器一致' {
        $e = Pushed
        EditJson "$($e.Win)\.claude\keybindings.json" { param($o) $o['bindings'][0]['action'] = 'changed' }
        $r = Run $e 'sync.ps1'
        Assert ($r.Code -ne 0 -and $r.Out -match '== Claude ==' -and $r.Out -notmatch '== Codex ==') '失敗即中止'
        $agg = (Run $e 'sync.ps1' @('-Check')).Out
        foreach ($s in 'sync-claude.ps1', 'sync-codex.ps1') {
            foreach ($line in ((Run $e $s @('-Check')).Out -split '\r?\n' | Where-Object { $_.Trim() })) {
                Assert ($agg.Contains($line)) "總入口包含 $s 的輸出：$line"
            }
        }
    }

    Case 'real sources：實際 repo 來源可推送、重複為 same、Pull 往返不改 repo' {
        $e = New-Env -RealSources
        $r = Run $e 'sync.ps1' @('-CheckVerbose')
        Assert ($r.Code -eq 0 -and $r.Out -notmatch '(?m)^same|(?m)^differs') "全部 missing：$($r.Out)"
        $r = Run $e 'sync.ps1'
        Assert ($r.Code -eq 0) "推送：$($r.Out)"
        foreach ($h in $e.Win, $e.Wsl) {
            Assert ((ReadF "$h\.claude\CLAUDE.md") -notmatch 'C:|/home/') '實際 Claude 指引不含絕對路徑'
            Assert ((ReadF "$h\.codex\pstack-models.md") -match '(?m)^session hook: off$' -and (ReadF "$h\.codex\pstack-models.md") -match '(?m)^default effort: session$') '實際配套檔含 default effort 與 hook'
            Assert ((ReadF "$h\.claude\pstack-models.md") -match '(?m)^session hook: off') '實際 Claude pstack 設定'
        }
        $r = Run $e 'sync.ps1' @('-Check')
        Assert ($r.Out -notmatch 'differs|missing|update') "再次檢查全 same：$($r.Out)"
        $hash = { (Get-ChildItem $e.Repo -File | Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName).Hash)" }) -join "`n" }
        $before = & $hash
        Assert ((Run $e 'sync.ps1' @('-PullWin')).Code -eq 0) 'PullWin'
        Assert ((Run $e 'sync.ps1' @('-PullWsl')).Code -eq 0) 'PullWsl'
        Assert ((& $hash) -ceq $before) 'Pull 往返後 repo 內容不變'
    }
}
finally {
    $full = [System.IO.Path]::GetFullPath($work)
    $tmp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path $full -Parent) -ieq $tmp -and (Split-Path $full -Leaf) -like 'sync-test-*' -and (Test-Path -LiteralPath $full)) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

Write-Host ""
if ($script:failed) { Write-Host "失敗 $script:failed / $script:total 項斷言" -ForegroundColor Red; exit 1 }
Write-Host "全部通過（$script:total 項斷言）" -ForegroundColor Green
