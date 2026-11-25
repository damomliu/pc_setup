# Herdr 錄影與播放

以 asciinema 錄製 WSL Herdr 的畫面, 並以本機 HTML 播放頁重看. WezTerm 命令見 [wezterm.md](wezterm.md#快速鍵設定), Herdr 設定見 [herdr.md](herdr.md).

## 錄影

以 WezTerm 命令面板的 `錄製 Herdr tab` 錄製. 做法是另開 WezTerm tab, 以 asciinema 包住第二個 Herdr client; 主畫面可照常切到其他 tab, 不影響錄影. 只錄目前 WSL Herdr, WIN 的 pane 只在畫面上出現時一併錄到.

- 錄影 client 從主畫面目前的 tab 開始, 不是目標時在錄影畫面自行切換. 開始後只在錄影 client 收起 sidebar, 主畫面不變.
- 停止: 在錄影畫面按 `Ctrl+B, Q` detach. 錄影期間 `Ctrl+\` 會被 asciinema 攔截, 用於暫停/繼續錄影.
- 存放: WSL `~/recordings/herdr/YYYYMMDD-HHMMSS[-名稱].cast` (目錄 700, 檔案 600), 不自動刪除. 播放頁新增的 marker 存在旁掛的 `<同名>.markers.json` (600). 只留本機, 不進 git, 不上傳 asciinema.org.
- 終端機重看: `asciinema play -s 4 -i 2 <檔案>`. 錄影保留原始時間; agent 工作時 spinner 持續更新, 閒置上限不一定有效, 主要靠加速. 要逐 frame 查看或中途變速改用下方播放頁.
- 轉 GIF: `agg --text-font-family 'Noto Sans Mono CJK TC' --speed 4 --idle-time-limit 2 --select 1:00..2:30 <檔案> <輸出>.gif`, 只剪 1~2 分鐘片段. `--select` 的時間以加速後為準. 分享前人工檢視, 錄影可能含客戶名稱, IP 或 token.

**已知限制** (Herdr 0.9.5 實測)

- zoom 是 tab 共用狀態: 任一 client 或 CLI 在被錄的 tab 執行 zoom, 錄影畫面也會只剩被 zoom 的 pane.
- CLI `herdr tab focus` / `--focus` 會帶走所有 client, 錄影 client 會跳到別的 tab; 鍵盤切換只影響自己的 client.
- 兩個 client 看同一個 tab 時, pane 大小跟著最後操作的 client; 錄影 tab 開在同一個 WezTerm 視窗, 大小一致就不會裁切.
- 不支援自動跟隨 workspace 新增的 tab.

## 播放

以 WezTerm 命令面板的 `播放 Herdr 錄影` 開啟. 做法是另開 tab 執行 WSL `herdr-play`, 在 WSL eth0 IP 的 `:47615` 啟動本機 server (例如 `http://172.21.236.176:47615/`) 並以 Windows 預設瀏覽器開啟播放頁; 關閉該 tab 或按 `Ctrl+C` 即停止. server 已在執行時只開瀏覽器, tab 隨即關閉.

- 頁面左側列出 `~/recordings/herdr/*.cast`, 預設依修改時間由舊到新. 按「舊→新」或「新→舊」按鈕可切換方向. 可輸入檔名的一部分即時篩選 (忽略大小寫), 點選錄影即開啟播放.
- 拖曳側邊欄右緣可調整寬度, 也可按 Tab 聚焦把手後用左右方向鍵調整. 同一播放器網址重新整理或開新頁時, 瀏覽器會沿用記住的寬度.
- 錄影列的 ✎ 可直接編輯完整檔名 (`.cast` 固定保留), Enter 儲存, Esc 或移開焦點取消. 更名會一併更新同名的 marker 旁掛檔. 正在播放的錄影更名後, 會保留播放位置和播放狀態, 網址也會更新.
- 錄影列的 ✕ 按兩下 (3 秒內), 會永久刪除錄影及其 marker 旁掛檔. 若刪除的是目前播放的錄影, 播放器及 marker 清單會清空.
- 頁面下方有播放控制列 (marker 名稱框與 M 按鈕, 上一個 marker, ±30/±5 秒, 播放/暫停, 下一個 marker, 降速/加速), 按鈕提示含對應快速鍵. 滑鼠在影片上移動或按控制列按鈕後, 影片下緣的時間軸 (asciinema-player 內建進度條) 顯示 5 秒 (內建為 2 秒, 由頁面的 `HUD_MS` 延長); 底部狀態列只顯示速度, 右側列常用快速鍵, 完整說明按右下角 `?`.
- WSL 內也可直接執行 `herdr-play [檔名] [--speed N]`, 開啟指定錄影.
- URL 參數: `file` 檔名, `speed` 速度 (預設 4), `idle` 閒置上限秒數 (預設 2), `t` 起始秒數. 播放中 URL 會跟著更新, 重新整理回到同一位置.
- 時間軸與 `asciinema play -i` 相同, 已套用閒置上限, 不是原始時間.
- frame: 每個 output 事件為一 frame, 但 1/60 秒內的連續事件合併為一個 (Herdr 一次重繪會拆成多個事件). 跳 frame 時自動暫停.
- 變速: 速度只能在建立 player 時設定, 中途變速會在目前位置重建 player, 畫面會閃一下.
- marker:
  - 新增: `m` 以預設名稱 (依序 `A`-`Z`, 之後 `M27`, `M28`...) 標記目前位置; 每部錄影各自記住下一個編號, 用自訂名稱新增也佔一號, 刪除 marker 不會倒退 (例: 新增 A, "text2" 後預設為 C, 刪掉 "text2" 仍是 C). `M` 先輸入名稱. 也可用控制列最左側的名稱框加「M」按鈕: 名稱框空白時以灰色提示顯示預設名稱 (點進去即清空), 按 M 或 Enter 新增, Esc 取消. 同一位置不重複新增.
  - 跳轉: `p` / `PgUp` 上一個, `n` / `PgDn` 下一個. 控制列的 ⏮ / ⏭ 也是上一個 / 下一個 marker; 沒有上一個時跳到開頭, 已過最後一個時跳到結尾. 鍵盤 `Home` / `End` 仍是開頭 / 結尾.
  - 左側下半部列出目前錄影的 marker, 點一列跳轉, 目前所在的 marker 會高亮. ✎ 原地改名 (Enter 確定, Esc 取消), ✕ 按兩下 (3 秒內) 刪除.
  - 時間軸上有 marker 刻度, 滑鼠移上去顯示名稱. 新增, 改名, 刪除後會重建 player 更新刻度, 畫面會閃一下.
  - 儲存在 `~/recordings/herdr/<同名>.markers.json`, 格式為 `{"next": 下一個預設編號, "markers": [{"t", "label"}]}` (舊版的純陣列仍可讀, 下次存檔時轉換). 時間為原始時間 (未套閒置上限), 改 `idle` 參數也不會偏移. 原始 `.cast` 不變; cast 內建的 marker (asciinema 錄影時加的) 也會列出, 標 `(cast)`, 唯讀.
- 網址: WSL eth0 IP 每次 WSL 啟動可能改變, 不要把網址存成書籤, 一律從命令面板或 `herdr-play` 開啟.
- 為何不用 127.0.0.1: 本機 WSL localhost forwarding (`wslrelay`) 轉不到只綁 WSL `127.0.0.1` 的服務 (Windows 端連線會卡住); 綁 `0.0.0.0` 的服務 (如 sshd) 則正常. 這與 `pc-wsl` 的 SSH 2222 不同, 後者是 `WslSshForward.ps1` 以 netsh portproxy 轉到 WSL eth0 IP:22.
- 安全: WSL 為 NAT 模式, eth0 IP 只有本機 Windows 連得到, LAN / Tailscale 連不到. server 只接受 Host 等於綁定的 `IP:47615`. marker 儲存 (`POST /api/markers/<檔名>.cast`) 與錄影操作 (`POST /api/recordings/<檔名>.cast`) 要求 `Content-Type: application/json` 與相符的 `Origin`, 並驗證格式與大小. 錄影操作的 JSON 為 `{"action":"rename","stem":"新名稱"}` 或 `{"action":"delete"}`, 限於錄影目錄內的 `.cast` 及其同名旁掛檔. 更名遇到既有的錄影或旁掛檔會拒絕覆蓋.

**快速鍵**

| 按鍵 | 動作 |
|---|---|
| `Space` | 播放 / 暫停 |
| `,` / `.` | 上一 / 下一 frame |
| `<` / `>` | ±10 frames |
| `[` / `]` | ±50 frames |
| `{` / `}` | ±200 frames |
| `←` / `→` | ±5 秒; 加 `Shift` 為 ±30 秒 |
| `-` / `=` | 降速 / 加速 (0.25, 0.5, 1, 2, 4, 8, 16) |
| `0` | 速度回 1x |
| `Home` / `End` | 開頭 / 結尾 |
| `m` | 以預設名稱新增 marker |
| `M` | 輸入名稱新增 marker |
| `p` / `PgUp` | 上一個 marker |
| `n` / `PgDn` | 下一個 marker |
| `f` | 全螢幕 |
| `l` | 顯示 / 隱藏清單 |
| `?` | 顯示 / 隱藏快速鍵說明 |

## 安裝 (WSL)

| 項目 | 來源 | 位置 |
|---|---|---|
| asciinema 3.2.1 | [GitHub release](https://github.com/asciinema/asciinema/releases/tag/v3.2.1) `asciinema-x86_64-unknown-linux-gnu` | `~/.local/bin/asciinema` |
| agg 1.9.0 | [GitHub release](https://github.com/asciinema/agg/releases/tag/v1.9.0) `agg-x86_64-unknown-linux-gnu` | `~/.local/bin/agg` |
| 錄影 helper | [herdr-rec.sh](src/herdr-rec.sh) (LF) | `~/.local/bin/herdr-rec` |
| 播放 server | [herdr-play.py](src/herdr-play.py) (LF, Python 3 標準函式庫) | `~/.local/bin/herdr-play` |
| 播放頁 | [herdr-player/](src/herdr-player/) | `~/.local/share/herdr-player/` |
| asciinema-player 3.18.0 (Apache-2.0) | [npm](https://www.npmjs.com/package/asciinema-player/v/3.18.0) tarball 的 `dist/bundle/asciinema-player.min.js`, `asciinema-player.css` | `herdr-player/vendor/` |

asciinema 與 agg 下載後比對 release 頁面的 sha256 digest, 再以 `install -m 755` 放到 `~/.local/bin`. agg 的中文字型使用 Ubuntu 套件 `fonts-noto-cjk` 的 Noto Sans Mono CJK TC.

播放 server 與播放頁從 repo 安裝 (更新 repo 後重跑):

```bash
src=/mnt/c/Users/user/Documents/pc_setup/wezterm/src
install -m 755 "$src/herdr-play.py" ~/.local/bin/herdr-play
mkdir -p ~/.local/share/herdr-player && cp -r "$src/herdr-player/." ~/.local/share/herdr-player/
```

asciinema-player 的 tarball 已比對 npm `integrity` (sha512). vendor 檔 sha256:

- `asciinema-player.min.js`: `752c9b528b664f5b16f27c68ba22fc7973d1d6063a1c3e4795a4c8015943acf6`
- `asciinema-player.css`: `981fe7bc6042048b2a373b6da297f747e324e90a8b6264e833e3a92cec22dfb9`
