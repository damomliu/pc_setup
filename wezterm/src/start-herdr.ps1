param([switch]$Verify)

$ErrorActionPreference = 'Stop'

function Set-LauncherState([string]$State) {
    $value = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($State))
    [Console]::Write("`e]1337;SetUserVar=PC_SETUP_WIN_HERDR=$value`a")
}

function Read-HerdrJson {
    $output = & $herdr --session default @args
    if ($LASTEXITCODE -ne 0) {
        throw "Herdr $args 回傳 $LASTEXITCODE"
    }
    $output | ConvertFrom-Json
}

function Get-DefaultHerdr {
    $status = Read-HerdrJson status server --json
    if ($status.status -eq 'not_running') {
        return
    }
    if ($status.status -ne 'running') {
        throw "無法判斷 Windows Herdr default 狀態 ($($status.status))。"
    }

    $panes = Read-HerdrJson pane list
    foreach ($pane in $panes.result.panes) {
        $info = Read-HerdrJson pane process-info --pane $pane.pane_id
        $paneShellPid = $info.result.process_info.shell_pid
        if ($paneShellPid -gt 0) {
            $shell = Get-Process -Id $paneShellPid -ErrorAction SilentlyContinue
            if ($shell) {
                return [pscustomobject]@{
                    SessionId = $shell.SessionId
                    Detached = $status.capabilities.detached_server_daemon
                }
            }
        }
    }
    throw 'Windows Herdr default 已執行，但找不到可驗證 Session ID 的 pane。'
}

try {
    $desktopSession = (Get-Process -Id $PID).SessionId
    if ($desktopSession -le 0) {
        throw '請從 Windows 桌面上的 WezTerm 執行此命令。'
    }
    $herdr = (Get-Command herdr.exe -CommandType Application).Source
    # 明確使用本機 default，避免繼承其他 Herdr pane 的連線環境。
    foreach ($name in 'HERDR_SOCKET_PATH', 'HERDR_SESSION_DIR', 'HERDR_SESSION', 'HERDR_PANE_ID', 'HERDR_TAB_ID', 'HERDR_WORKSPACE_ID', 'HERDR_ENV') {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }

    if ($Verify) {
        $wait = [Diagnostics.Stopwatch]::StartNew()
        $lastError = 'Windows Herdr default 尚未啟動。'
        do {
            try {
                $server = Get-DefaultHerdr
                if ($server) {
                    if ($server.SessionId -eq $desktopSession -and $server.Detached) {
                        Write-Output "Windows Herdr default 已在 Session $desktopSession 就緒。"
                        exit 0
                    }
                    $lastError = "Windows Herdr default 回報 Session $($server.SessionId)，需要在 Session $desktopSession 獨立執行。"
                }
            } catch {
                $lastError = $_.Exception.Message
            }
            Start-Sleep -Milliseconds 250
        } while ($wait.Elapsed.TotalSeconds -lt 15)
        throw "驗證 Windows Herdr 逾時。$lastError"
    }

    $server = Get-DefaultHerdr
    if ($server -and $server.SessionId -eq 0) {
        Set-LauncherState 'confirm'
        Write-Host 'Windows Herdr default 跑在 Session 0。重啟會結束 default 的 panes、agents 和命令，請先存好工作。'
        $answer = Read-Host '是否停止並從桌面重新啟動 default？[y/N]'
        if ($answer.Trim() -notin @('y', 'yes')) {
            throw '已取消重啟 Windows Herdr default。'
        }

        $server = Get-DefaultHerdr
        if ($server -and $server.SessionId -eq 0) {
            Set-LauncherState 'checking'
            & $herdr session stop default
            if ($LASTEXITCODE -ne 0) {
                throw 'Windows Herdr default 停止失敗。'
            }
            $wait = [Diagnostics.Stopwatch]::StartNew()
            do {
                $server = Get-DefaultHerdr
                if (!$server) { break }
                Start-Sleep -Milliseconds 250
            } while ($wait.Elapsed.TotalSeconds -lt 15)
            if ($server) {
                throw 'Windows Herdr default 仍在執行。請暫時離開 WSL Herdr 的 WIN 連線後再試。'
            }
        }
    }

    if ($server) {
        if ($server.SessionId -ne $desktopSession) {
            throw "Windows Herdr default 跑在 Session $($server.SessionId)，目前桌面是 Session $desktopSession。"
        }
        Set-LauncherState 'ready'
    } else {
        Set-LauncherState 'starting'
        & $herdr --session default
        throw "Windows Herdr client 已結束 (exit $LASTEXITCODE)。"
    }
} catch {
    if ($Verify) {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
    Write-Host $_.Exception.Message
    Set-LauncherState 'blocked'
}
