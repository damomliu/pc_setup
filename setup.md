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
    - python
    - .net
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

## 個人化
- RGB（OpenRGB）：`rgb/Set-RgbMode.ps1`（off、on、dim、idle、cycle、wave）；桌面捷徑「RGB 模式」
- AutoHotkey
- Office 停用 OneDrive 鎖定 (onedrive - gloabl.ini)
    - HoldEnabledUserSetting/CoAuthEnabledUserSetting
- Windows
    - 檔案總管不顯示"圖庫"
    - 時鐘顯示"秒"
- 雙螢幕、雙電腦
    - 安裝與操作：[dual-pc/README.md](dual-pc/README.md)
    - 設計共識：[dual-pc/design.md](dual-pc/design.md)
    - IP 變更：修改 `dual-pc/config.psd1` 的 `PC.IP` 或 `NB.IP`，再重新執行部署腳本
    - PowerToys - 無框線滑鼠
    - Spacedesk (Driver: PC / Viewer: NB)
    - LG34: HDMI1=NB、HDMI2=PC（無法軟體切 Input，請用搖桿）
    - 熱鍵半自動：Windows / Spacedesk 自動切，LG 用手撥 HDMI；PC 為唯一 coordinator，每次都重新套用目標 profile
    - mix↔PC 共用 HDMI2，不提示切 LG；進／出 NB 才提示撥搖桿與鍵鼠
    - profile-PC(Ctrl+Alt+F9): PC 延伸至兩個螢幕（LG→HDMI2 且為主螢幕；NB Viewer 自動連 PC 並全螢幕；關閉無框線滑鼠；提示鍵盤滑鼠切到 PC）
    - profile-mix(Ctrl+Alt+F10): LG34 顯示 PC, NB 顯示於自己螢幕（LG→HDMI2；NB 僅內建；開啟無框線滑鼠）
    - profile-NB(Ctrl+Alt+F12): NB 延伸至兩個螢幕（LG→HDMI1 且為主螢幕；NB 內建為延伸；關閉無框線滑鼠；鎖定 PC；提示鍵盤滑鼠切到 NB）

## 其他
- review 開機啟動項目