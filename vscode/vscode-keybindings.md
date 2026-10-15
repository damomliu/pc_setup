# VS Code 快速鍵（Windows）

設定檔：`vscode/keybindings.json`，以 VS Code 預設為基礎，不使用 keymap extension。下面只列跟 VS Code 預設不同的按鍵。

## 視窗

| 按鍵 | 動作 |
|---|---|
| `Ctrl+Q` | 關閉視窗 |
| `Ctrl+Alt+R` | Reload Window（在 terminal 內也能用；取代 Run Recent Command） |
| `Ctrl+Shift+W` | 關閉所有 editor |
| `Ctrl+K Shift+W` | 關閉同群組其他 editors（保留目前 editor 與 Sticky tabs） |
| `Ctrl+Shift+S` | 全部儲存 |
| `Ctrl+K Z` | 全螢幕（取代 Zen Mode） |
| `Ctrl+0` | 重設縮放 |

## 終端機、面板、側邊欄

| 按鍵 | 動作 |
|---|---|
| `Ctrl+'` | 開關 terminal（已有 terminal 時） |
| `Ctrl+Shift+'` | 最大化／還原面板 |
| `Ctrl+M` | 開關右側欄（Claude Code／Codex；在 terminal 內也能用） |
| `Ctrl+K Ctrl+M` | 最大化／還原右側欄（Secondary Side Bar；取代 Maximize Editor Group） |
| `Ctrl+B`（terminal 內） | 開關側邊欄 |
| `Ctrl+J`（terminal 內） | 開關面板 |
| `Ctrl+R`（terminal 內） | 開啟最近的資料夾 |
| `Shift+Enter`（terminal 內） | 送出 `ESC`+`CR`，在 Claude Code／Codex CLI 中換行 |

## 編輯器群組

| 按鍵 | 動作 |
|---|---|
| `Ctrl+K ←/→/↑/↓` | 把目前 editor 移到左／右／上／下的群組 |
| `Ctrl+K -` | 往垂直方向分割 |
| `Ctrl+K N` | 把目前 editor 移到新視窗 |
## 編輯

| 按鍵 | 動作 |
|---|---|
| `Ctrl+D` | 刪除整行 |
| `Alt+D` | 選取下一個相同字（VS Code 原本的 `Ctrl+D`） |
| `Ctrl+Shift+Backspace` | 刪除游標左側到行首 |
| `Ctrl+Alt+J` | 合併行 |
| `Shift+Enter` | 在下方插入新行（find／replace 輸入框內除外） |
| `Ctrl+1` | Quick Fix |
## 導覽

| 按鍵 | 動作 |
|---|---|
| `F3` | 移至宣告 |
| `F12` | 移至參考 |
| `Shift+F12` | 移至實作 |
| `Alt+F12` | 預覽實作 |

## 字型縮放

| 按鍵 | 動作 |
|---|---|
| `Ctrl+Shift+=` | 放大 editor 字型 |
| `Ctrl+Shift+-` | 縮小 editor 字型 |
| `Ctrl+Shift+9` | 重設 editor 字型 |

## 偵錯

| 按鍵 | 動作 |
|---|---|
| `F11`（未在偵錯時） | 開始偵錯 |
| `Ctrl+F11` | 選擇設定後開始 |
| `F8`（偵錯中） | 繼續執行 |
| `Ctrl+F2`（偵錯中） | 停止 |
| `Ctrl+F10` | 執行到游標處 |
| `Ctrl+Y`（偵錯中、editor 內） | 把選取內容送到 Debug Console |
| `Ctrl+U`（偵錯中、editor 內） | 把選取內容加入 Watch |
| `Ctrl+K Ctrl+D` | 跳到 call stack 最上層 |
| `Ctrl+Shift+Y`（Debug Console 開著時） | 開關 Debug Console |

## Git

| 按鍵 | 動作 |
|---|---|
| `Ctrl+Shift+J` | Source Control 檢視 |
| `Ctrl+K Ctrl+G` | Git Graph |
| `Ctrl+Shift+Alt+O` | 在新視窗開啟 worktree |

## Markdown

| 按鍵 | 動作 |
|---|---|
| `Alt+B`／`Alt+I`／`Alt+M` | 粗體／斜體／數學式（Markdown All in One，所有 profile） |
| `Ctrl+K Shift+V` | 在側邊開啟鎖定的 Markdown Preview Enhanced |
| `Ctrl+Alt+M` | 開關 MPE 同步捲動 |
| `F5`（Markdown 檔或 preview 內） | 重新整理 preview |

## AI

| 按鍵 | 動作 |
|---|---|
| `Ctrl+L` | 焦點在 Claude Code 外時移到 Claude 輸入框（在 terminal 內也能用）；已經在 Claude 裡時回到 editor |
| `Ctrl+Shift+Alt+L` | 在新 tab 開啟 Claude Code（取代 Quick Chat） |
| `Ctrl+Alt+L` | 把選取範圍以 @-mention 插入 Claude Code |
| `Ctrl+Alt+F`（Claude Code 內） | 開關 Focus view（extension 預設，不在 `keybindings.json`） |
| `Ctrl+N`（Codex 內） | 開新對話（extension 預設，不在 `keybindings.json`） |
| `Ctrl+Shift+M`（Codex 內） | 開啟 model picker（Codex 內建；解除 VS Code Problems 的同鍵綁定） |
| `Ctrl+O` | 開啟 Codex sidebar（取代開啟檔案；terminal 內留給 CLI） |
| `Ctrl+Alt+O` | 把選取範圍加入 Codex thread |

Claude Code 切換 model：按 `Ctrl+L` 聚焦輸入框後，輸入 `/model` 開啟 picker。目前沒有可直接綁定的 model 切換 VS Code command。

## 解除綁定

只列解除後沒有改綁到別的動作的按鍵；改綁的已寫在各節的「取代」。

| 按鍵 | 原本的動作 |
|---|---|
| ``Ctrl+` `` | 開關 terminal（已有 terminal 時；改用 `Ctrl+'`） |
| `Ctrl+Shift+M` | 開啟 Problems（按鍵留給 Codex；Problems 仍可透過 Command Palette 開啟） |
| `Ctrl+E` | Quick Open |
| `Ctrl+Shift+PageUp`／`Ctrl+Shift+PageDown` | 在群組內左右移動 editor |
| `Ctrl+Shift+K` | 刪除整行（已改用 `Ctrl+D`） |
| `Ctrl+Shift+G` | Source Control 檢視（已改用 `Ctrl+Shift+J`） |
| `Ctrl+Y`（偵錯以外） | Redo |
| `Ctrl+U`（editor 內，偵錯以外） | Cursor Undo |
| `Shift+F8` | 上一個問題（跨檔案） |
| `Ctrl+F12` | 移至實作 |
| `Ctrl+Shift+F12` | 預覽實作 |
| `Ctrl+Shift+Alt+Y` | 開關 Debug Console |
| `Ctrl+K V` | Markdown Preview 開在側邊（Markdown 檔） |
| `Ctrl+Shift+Enter`／`Shift+Enter`（Markdown 檔） | MPE 執行 code chunk |
| `Ctrl+K M` | Notebook cell 切換語言 |
| `Ctrl+Shift+I` | Chat 開啟 Agent |
| `Ctrl+Alt+I` | Chat 開啟 |
| `Ctrl+I` | Inline Chat、Chat 提問、Notebook cell chat、Terminal chat |

所有 profile 的 extension 清單都未包含 Copilot，所以 VS Code 內建 chat 指令的快速鍵一併解除。

## 其他

| 按鍵 | 動作 |
|---|---|
| `Ctrl+K E` | 用 Edit CSV 開啟（`keybindings.json` 沒限制 profile，但只有 Python profile 裝了該 extension，其他 profile 按了沒作用） |
