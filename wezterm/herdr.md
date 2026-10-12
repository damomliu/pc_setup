# Herdr 設定共識

## 配置狀態

- Repo 副本：[herdr-config.toml](herdr-config.toml)。
- Windows 實際載入：`%APPDATA%\herdr\config.toml`。
- WSL Ubuntu-24.04 實際載入：`/home/damon/.config/herdr/config.toml`，套用相同的 `[keys]` 快速鍵。
- `herdr-config.toml` 是快速鍵片段，需合併至上述實際設定；只修改 repo 副本不會生效。保留原本的 `onboarding`、`[ui.toast]` 等設定，不要整份覆蓋。
- 修改後執行 `herdr server reload-config`，確認回傳 `status: applied` 且 `diagnostics` 為空。
- Windows 與 WSL 的 Herdr 設定各自獨立，需分別合併並在各自環境執行 reload。
- 以已安裝的 Herdr 0.9.3 為準；下次啟動 Herdr 時載入。已開啟的 client 可用 `Ctrl+B, Shift+R` reload config。

## 快速鍵分工

主要 pane／tab 操作交給 Herdr，WezTerm 保留外層管理功能。

| 按鍵 | 用途 |
|---|---|
| `Ctrl+B` | Herdr prefix |
| `Alt+方向鍵` | Herdr：切換至該方向的 pane |
| `Alt+Z` | Herdr：切換 pane zoom |
| `Alt+Shift+方向鍵` | Herdr：調整 pane 大小 |
| `Prefix, \` | Herdr：左右分割 pane |
| `Ctrl+Space` | 保留給中文輸入法，不可用作 prefix |

`Prefix, \` 表示先按 `Ctrl+B`，放開後再按 `\`；對應 `split_vertical`，取代預設的 `Prefix, V`。

## 暫時保留與未定事項

- WezTerm 的 `Alt+1`～`Alt+9`、`Alt+[`／`Alt+]`、`Ctrl+PageUp`／`Ctrl+PageDown` 與 Ubuntu prefix `Ctrl+U` 暫時保留，留給 WezTerm。
