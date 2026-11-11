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

## 開發工具
- font: Fira Code、MesloLGS NF、Maple Mono NF CN
- VS Code（2026-10 起主力）
    - 設定見 `vscode/`（`vscode.md`；`sync.py` 同步至 `%APPDATA%\Code\User`）
    - Settings Sync（GitHub），keybindings 依平台分開
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
- bash
  - [ble.sh](https://github.com/akinomyoga/ble.sh) (類似 zsh-auto-suggestions)
- PowerShell：見 [power_shell.md](./power_shell/power_shell.md)
- openssh-server
    - SSH 設定副本與 Win／WSL 同步：見 [sync.py](./ssh/sync.py) 檔頭說明（`--check`／`--pull`／`--push`）
- sshfs（Win: SSHFS-Win + WinFsp；WSL: sshfs）→ 見 [herdr.md](./wezterm/herdr.md)
- usbipd-win
- WezTerm
    - 要安裝已修復 IME 的版本
    - 設定見 `wezterm/`（`wezterm.md`；`config/wezterm.lua` 為 `~/.wezterm.lua` 副本）
- [Herdr](./wezterm/herdr.md)

## AI Agent 相關

參考 [agent.md](./agent/agent.md)

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
    - script `dual_display.ps1`（桌面捷徑「Display」）
        - 顯示: PC Monitor 1/2 解析度
        - 選單:
            - (R) 更新狀態
            - (1) 螢幕1 25:9 (2560x1080)
            - (9) 螢幕1 16:9  (1920x1080)
            - (0) 螢幕1 16:10 (1920x1200)
            - (Q) 退出
- PowerToys
  - 系統工具-快速鍵指南: "按住 Windows 鍵"

## 已不使用

- Cursor
    - vscode settings: settings.json, keybindings.json
    - cursor settings: state.vscdb (sqlite), cli-config.json, mcp.json
    - terminal profile: None (不要 zsh)
