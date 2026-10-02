# PC Setup

## 應用程式
- 嘸蝦米 (輸入法: 只留嘸蝦米、預設英打)
    - Boshiahk2
- GCC - 軀動程式
- SSH, Tailscale, AnyDesk
- `C:\Notes\`
- Firefox
- Notion, Asana
- DBeaver
- SublimeText
    - 快速鍵設定
    - 用 installer 版安裝至 Program Files, 不要用 WinGet
    - 右鍵選單
- Snipaste (開機啟動 + 快速鍵設定)

## 開發相關
- font: Fira Code、MesloLGS NF
- Cursor
    - vscode settings: settings.json, keybindings.json
    - cursor settings: state.vscdb (sqlite), cli-config.json, mcp.json
    - terminal profile: None (不要 zsh)
- Claude - Desktop, CLI
    - settings.json, keybindings.json
- Skills
    - asana-ai-skill
- 程式語言 (版本參考 `ssh nb`)
    - python (uv)
    - .net, dotnet-ef
    - npx(npm)
- WSL
- Docker
- scoop, just
- vim (scoop)
- git 相關
    - git, git config
    - github cli, github ssh key
- PowerShell
    - PowerShell 7
    - profile.ps1
        - `Set-PSReadLineOption -EditMode Vi`
        - $utf8
    - Windows Terminal settings
    - Vim
- openssh-server
    - ~/.ssh/config (shared.conf)
- usbipd-win
- WezTerm
    - 要安裝已修復 IME 的版本
    - 設定見 `wezterm/`（`wezterm.md`；`wezterm.lua` 為 `~/.wezterm.lua` 副本）

## 個人化
- RGB（OpenRGB）：`rgb/Set-RgbMode.ps1`（off、on、dim、idle、cycle、wave）；桌面捷徑「RGB 模式」
- AutoHotkey
- Office 停用 OneDrive 鎖定 / 不要求登入
    - onedrive global.ini: CoAuthEnabledUserSetting=false
    - HKCU Office SignInOptions=3、UseOnlineContent=0
- Windows
    - 檔案總管不顯示"圖庫"
    - 時鐘顯示"秒"
- 雙螢幕、雙電腦
    - PowerToys - 無框線滑鼠
    - Spacedesk (Driver: PC / Viewer: NB)
    - LG34: HDMI1=NB、HDMI2=PC（無法軟體切 Input，請用搖桿）
    - 熱鍵半自動：Windows / Spacedesk 自動切，LG 用手撥 HDMI；PC 為唯一 coordinator，每次都重新套用目標 profile
    - script `dual_display.ps1`（桌面捷徑「Display」）
        - 首次：`pwsh .\dual_display.ps1 -Install`（跳一次 UAC）；`spacedeskService` 改 Manual，並註冊 elevated 排程工作 `DualDisplay-StartDriver` / `DualDisplay-StopDriver`；`-Uninstall` 還原
        - 非互動：`-Mode Single|Dual`；`-WhatIf` 只印動作
        - 顯示: PC Driver 狀態 & NB Viewer 狀態
        - 選單:
            - (R) 更新狀態
            - (1) 單螢幕模式
                - NB 停止 viewer、PC 停止 driver（Tray 一併關閉）；虛擬螢幕沒消失時警告並詢問是否強制卸載
            - (2) 雙螢幕模式
                - PC 啟動 driver、NB 啟動 viewer；以 PC 螢幕數 +1 判定成功
            - (F) 強制卸載虛擬顯示器（`Disable-PnpDevice`，跳 UAC）
            - (Q) 退出
        - NB 端（`ssh nb`）
            - Viewer 是 Store 版，無 CLI 參數；需設定為開啟後自動連 PC
            - SSH 在 session 0，故啟動 Viewer 靠 NB 上的互動排程工作 `DualDisplay-StartViewer`（每次自動重建）

## 其他
- ~~review 開機啟動項目~~（已完成）
    - 停用 Logitech Download Assistant ×2（HKLM StartupApproved）、AMD `StartCN` 排程工作
    - `spacedeskService` 改手動（由 `dual_display.ps1` 啟停）
    - 待確認：AnyDesk service（Auto）是否要改 Manual