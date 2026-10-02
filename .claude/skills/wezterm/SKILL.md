---
name: wezterm
description: >-
  修改這份 pc_setup 的 WezTerm 設定時使用。使用者要新增、修改或刪除 WezTerm 快速鍵、命令面板命令、prefix、外觀、字型、啟動行為，或其他 wezterm.lua / wezterm.md 設定時，都要先讀這個 skill，即使對方沒有說「skill」或檔名。
  新增快速鍵時要詢問是否同時新增至命令面板，不要自行決定。新增命令時要詢問是否同時新增快速鍵，不要自行決定。
  新增或修改的快速鍵、命令或設定，要更新 wezterm.md 以及 wezterm.lua，最後 sync wezterm.lua 並 reload wezterm。
---

# WezTerm 設定

這份 repo 的 WezTerm 有兩個 lua，只有家目錄那份會被正在跑的 WezTerm 讀到。改完 repo 裡的檔卻沒同步，使用者會覺得命令沒出現。

| 角色 | 路徑 |
|---|---|
| 編輯用的設定 | `wezterm/wezterm.lua` |
| 給人看的說明 | `wezterm/wezterm.md` |
| 實際載入 | `%USERPROFILE%\.wezterm.lua` |

快速鍵寫在 `config.keys`（以及 `config.key_tables`）。命令面板的項目寫在 `wezterm.on('augment-command-palette', ...)`，顯示名稱是 `brief`。Prefix 是 `Ctrl+B`。說明的分段跟 `wezterm.md` 現有的「快速鍵設定」「命令面板」對齊，不要另起一套標題。

## 先問，不要自己決定

使用者只說要新增快速鍵時，先停下來問是否同時新增至命令面板。不要自行決定。

使用者只說要新增命令時，先停下來問是否同時新增快速鍵。不要自行決定。

對方還沒回答之前，不要寫另一邊。同一句話裡已經講明兩邊都要（或只要一邊）時，就照那句話做，不必再問一次。

刪除或修改已經同時存在的快速鍵與命令時，兩邊一起改，並在 `wezterm.md` 刪掉或改掉對應說明。不要為了「順便」補上使用者沒要的綁定。

## 改設定

1. 改 `wezterm/wezterm.lua`。命令的 `brief` 用使用者給的完整名稱，不要自行縮短或改寫。
2. 把同一項變更寫進 `wezterm/wezterm.md` 的對應段落。
3. 啟動外部程式時用該程式的完整路徑，工作目錄用 `cwd`。不要用相對的 `cmd.exe` 再串一條命令列；WezTerm 會在 `cwd` 底下找那個執行檔，路徑不存在或引號不對時，pane 會出現「系統找不到指定的路徑」或「檔案名稱、目錄名稱或磁碟區標籤語法錯誤」。

## 同步並重載

改完 lua 與 md 之後，執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/skills/wezterm/scripts/sync-wezterm.ps1
```

腳本把 `wezterm/wezterm.lua` 複製到 `%USERPROFILE%\.wezterm.lua`。正在跑的 WezTerm 盯的是家目錄這份，檔案一換掉就會重載，不需要另開視窗，也不要為了重載去按使用者的鍵盤。

複製後用 `wezterm show-keys` 確認設定檔載得起來。若輸出有 Lua 錯誤，先修 `wezterm/wezterm.lua`，再重跑同步腳本。
