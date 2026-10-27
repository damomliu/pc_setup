"""一次同步 Claude Code 與 Codex 設定（依序執行 sync_claude、sync_codex）。

參數與兩支同步器相同；第一個失敗（例如目標內容不同又沒加 --force）即中止，不跑第二個。
兩個工具之間沒有 transaction：Claude 成功後 Codex 失敗，不回復 Claude 的變更。
共用邏輯在 sync_common.py。

Python 環境：
Windows 與 WSL 經 /mnt/c 共用同一份 checkout 時，兩邊各用自己的 venv，不共用 interpreter 或
site-packages（macOS 同樣用自己的 venv）；ai-agent/.venv/ 已列入 .gitignore。
**不要對 .venv/ 容器遞迴刪除或使用 --clear**（會刪到另一個平台的環境）。
    Windows: ai-agent/.venv/windows/
        建立：<python 3.13.15>\\python.exe -m venv ai-agent\\.venv\\windows
        安裝依賴：ai-agent\\.venv\\windows\\Scripts\\python.exe -m pip install -r ai-agent\\requirements.txt
    WSL: ai-agent/.venv/wsl/
        建立：python3 -m venv ai-agent/.venv/wsl
        安裝依賴：ai-agent/.venv/wsl/bin/python -m pip install -r ai-agent/requirements.txt
    macOS: ai-agent/.venv/macos/
        建立：python3 -m venv ai-agent/.venv/macos，或 uv venv ai-agent/.venv/macos --python 3.13.15
        安裝依賴：ai-agent/.venv/macos/bin/python -m pip install -r ai-agent/requirements.txt
    （安裝依賴時都明確指定該平台 venv 的 interpreter）

用法（明確指定各平台 venv 的 interpreter）：
    Windows: ai-agent\\.venv\\windows\\Scripts\\python.exe ai-agent\\sync.py --check-verbose
    WSL:     ai-agent/.venv/wsl/bin/python ai-agent/sync.py --check-verbose
    macOS:   ai-agent/.venv/macos/bin/python ai-agent/sync.py --check-verbose

選項：
    預設              repo → 目標；目標內容不同需 --force。
    --pull-win / --pull-wsl / --pull-mac
                      收回 repo；三者互斥（--pull-mac 僅 macOS），Claude 與 Codex 各自收回自己的指引，不再要求兩者一致。
    --check           唯讀，只列出每個目標的 missing / same / differs（Codex config 另有 update）。
    --check-verbose   唯讀，單獨使用即包含 --check，另列出設定路徑與「本機 → repo 預期」值
                      （WSL、macOS 為合併後結果）及指引／pstack 文字的逐行 diff。忽略欄位不出現；
                      env 子樹與路徑含 token / secret / password / auth / credential、
                      或為 key 類名稱（key、apiKey、api_key…）的值顯示 ***。
    --test-win-home / --test-wsl-root
                      隱藏參數，供測試使用，必須成對指定，指定後不呼叫 WSL（Codex config.toml 使用 tomlkit）。

參數限制：
    - --check / --check-verbose 不能與任何 --pull-* / --force 併用；
      --win-only 不能與 --pull-wsl 併用；衝突會在任何 I/O 前拒絕。
    - macOS 本機執行只同步目前 user（比照 WSL）：拒絕 --pull-win / --pull-wsl / --win-only 與
      --test-win-home / --test-wsl-root，--distro 忽略；Windows 與 WSL 拒絕 --pull-mac。
    - 參數不接受縮寫，舊 PowerShell 參數名稱（-PullWin 等）不再支援。

檔案處理：
    - 以 bytes 讀寫，保留換行字元與尾端空行；目標若有 UTF-8 BOM，JSON／TOML 可正常解析。
    - JSON 比對忽略 object key 順序與排版（array 順序、值與型別、字串大小寫都有意義，
      true 與 1、1 與 1.0 為不同）。
"""
import sys

sys.dont_write_bytecode = True

import sync_claude  # noqa: E402
import sync_codex  # noqa: E402
import sync_common as c  # noqa: E402


def main(argv=None, repo=None) -> int:
    c.configure_stdio()
    argv = sys.argv[1:] if argv is None else list(argv)
    try:
        # 依賴 preflight：參數與平台檢查後、開始 Claude 寫入前，先確認 Codex 所需依賴（不是跨工具 transaction）
        c.validate_platform(c.parse_args(argv, "sync.py"))
        sync_codex.load_tomlkit()
    except c.SyncError as e:
        print(f"錯誤: {e}", file=sys.stderr)
        return 1
    print("== Claude ==")
    rc = sync_claude.main(argv, repo)
    if rc:
        return rc
    print("== Codex ==")
    return sync_codex.main(argv, repo)


if __name__ == "__main__":
    raise SystemExit(main())
