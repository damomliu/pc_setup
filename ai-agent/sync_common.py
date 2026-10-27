"""sync.py、sync_claude.py、sync_codex.py 共用：參數檢查、平台與家目錄解析、JSON／文字差異輸出。"""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_DISTRO = "Ubuntu-24.04"


class SyncError(Exception):
    """預期內的失敗：顯示訊息後以非零結束，不印 traceback。"""


def configure_stdio() -> None:
    """stdout／stderr 設為 UTF-8，避免非 UTF-8 的 Windows terminal 無法輸出繁體中文與箭頭。"""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure:
            reconfigure(encoding="utf-8")


def warn(message: str) -> None:
    print(f"警告: {message}", file=sys.stderr)


# ---------------------------------------------------------------------------
# 平台與家目錄
# ---------------------------------------------------------------------------

def detect_platform() -> str:
    """回傳 windows / wsl / macos / linux / other；平台偵測集中在這裡。"""
    if sys.platform == "win32":
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("linux"):
        if os.environ.get("WSL_DISTRO_NAME") or "microsoft" in platform.release().lower():
            return "wsl"
        return "linux"
    return "other"


def local_home() -> Path:
    return Path.home()


def find_wsl() -> str | None:
    return shutil.which("wsl")


def query_wsl_home(distro: str) -> str:
    exe = find_wsl()
    if not exe:
        raise SyncError("找不到 wsl 命令")
    try:
        result = subprocess.run([exe, "-d", distro, "--", "printenv", "HOME"],
                                capture_output=True, timeout=60, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        raise SyncError(f"讀不到 WSL ({distro}) 的 HOME") from None
    home = result.stdout.decode("utf-8", errors="replace").strip()
    if result.returncode != 0 or not home:
        raise SyncError(f"讀不到 WSL ({distro}) 的 HOME")
    return home


def wsl_unc_root(distro: str, wsl_home: str) -> Path:
    return Path("\\\\wsl.localhost\\" + distro + wsl_home.replace("/", "\\"))


# ---------------------------------------------------------------------------
# 參數
# ---------------------------------------------------------------------------

class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise SyncError(message)


def build_parser(prog: str) -> argparse.ArgumentParser:
    p = _Parser(prog=prog, allow_abbrev=False,
                description="在 repo 的 ai-agent/ 與 Windows、WSL 之間同步設定與規則。")
    p.add_argument("--pull-win", action="store_true", help="Windows -> repo")
    p.add_argument("--pull-wsl", action="store_true", help="WSL -> repo")
    p.add_argument("--check", action="store_true", help="唯讀，只列出每個目標的狀態")
    p.add_argument("--check-verbose", action="store_true", help="唯讀，另列出差異")
    p.add_argument("--force", action="store_true", help="覆蓋內容不同的目標")
    p.add_argument("--distro", default=DEFAULT_DISTRO, help=f"WSL distro（預設 {DEFAULT_DISTRO}；WSL 本機執行時忽略）")
    p.add_argument("--win-only", action="store_true", help="只同步 Windows，不查詢或存取 WSL")
    p.add_argument("--test-win-home", help=argparse.SUPPRESS)
    p.add_argument("--test-wsl-root", help=argparse.SUPPRESS)
    return p


def parse_args(argv, prog: str) -> argparse.Namespace:
    """解析並檢查參數；衝突一律在任何檔案 I/O 與 WSL 呼叫前拒絕。"""
    a = build_parser(prog).parse_args(argv)
    pull = a.pull_win or a.pull_wsl
    if a.pull_win and a.pull_wsl:
        raise SyncError("--pull-win 與 --pull-wsl 不能同時使用")
    if (a.check or a.check_verbose) and (pull or a.force):
        raise SyncError("--check / --check-verbose 只能唯讀檢查，不能與 --pull-win / --pull-wsl / --force 併用")
    if a.win_only and a.pull_wsl:
        raise SyncError("--win-only 不能與 --pull-wsl 併用")
    if (a.test_win_home is None) != (a.test_wsl_root is None):
        raise SyncError("--test-win-home 與 --test-wsl-root 必須成對指定")
    if a.test_win_home is not None and (not a.test_win_home.strip() or not a.test_wsl_root.strip()):
        raise SyncError("--test-win-home 與 --test-wsl-root 不能是空字串")
    return a


@dataclass
class Target:
    name: str  # Windows / WSL
    root: Path
    is_wsl: bool


@dataclass
class Context:
    args: argparse.Namespace
    targets: list[Target] = field(default_factory=list)  # 推送／檢查的目標
    pull: Target | None = None  # Pull 的來源


def validate_platform(a) -> str:
    """平台與平台相關的參數檢查；不讀寫任何設定、不呼叫 WSL。"""
    plat = detect_platform()
    if plat == "wsl":
        if a.pull_win or a.win_only:
            raise SyncError("WSL 本機執行只同步目前 Linux user，不接受 --pull-win 或 --win-only")
    elif plat != "windows":
        raise SyncError(f"尚未支援此平台（{plat}）；目前僅支援 Windows 與 WSL，未讀寫任何設定")
    return plat


def build_context(argv, prog: str, preflight=None) -> Context:
    """preflight（例如載入選用依賴）在參數與平台檢查後、任何設定 I/O 與 WSL 呼叫前執行。"""
    a = parse_args(argv, prog)
    plat = validate_platform(a)
    if preflight:
        preflight()
    if plat == "wsl":
        home = Path(a.test_wsl_root) if a.test_wsl_root is not None else local_home()
        t = Target("WSL", home, True)
        return Context(a, [t], t if a.pull_wsl else None)

    def win() -> Target:
        return Target("Windows", Path(a.test_win_home) if a.test_win_home is not None else local_home(), False)

    def wsl() -> Target:
        if a.test_wsl_root is not None:
            return Target("WSL", Path(a.test_wsl_root), True)
        return Target("WSL", wsl_unc_root(a.distro, query_wsl_home(a.distro)), True)

    if a.pull_win:
        t = win()
        return Context(a, [t], t)
    if a.pull_wsl:
        t = wsl()
        return Context(a, [t], t)
    targets = [win()] if a.win_only else [win(), wsl()]
    return Context(a, targets)


# ---------------------------------------------------------------------------
# 檔案與 JSON
# ---------------------------------------------------------------------------

def read_bytes(path: Path) -> bytes:
    try:
        return Path(path).read_bytes()
    except OSError as e:
        raise SyncError(f"無法讀取：{path}（{e.strerror}）") from None


def write_bytes(path: Path, data: bytes, mkdir: bool = False) -> None:
    path = Path(path)
    try:
        if mkdir:
            path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    except OSError as e:
        raise SyncError(f"無法寫入：{path}（{e.strerror}）") from None


def decode_text(data: bytes) -> str:
    return data.decode("utf-8-sig", errors="replace")


def read_json(path: Path) -> dict:
    """解析失敗時不帶出原始內容，避免診斷訊息洩漏設定值。"""
    try:
        value = json.loads(Path(path).read_bytes().decode("utf-8-sig"))
        if not isinstance(value, dict):
            raise ValueError
        return value
    except Exception:
        raise SyncError(f"無法讀取或解析 JSON：{path}") from None


def canonical(value) -> str:
    """字串比對用的正規化 JSON；true 與 1、1 與 1.0 因此不會被視為相同。"""
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def select_managed(obj: dict, ignore) -> dict:
    return {k: v for k, v in obj.items() if k not in ignore}


def json_same(a: dict, b: dict, ignore=()) -> bool:
    return canonical(select_managed(a, ignore)) == canonical(select_managed(b, ignore))


def join_ignored(managed: dict, order: dict, ignored_from: dict, ignore) -> dict:
    """依 order 的 key 順序組出結果：受管 key 取 managed，忽略 key 取 ignored_from（沒有就不放）。"""
    out: dict = {}
    for k in order:
        if k in ignore:
            if k in ignored_from:
                out[k] = ignored_from[k]
        elif k in managed:
            out[k] = managed[k]
    for k in managed:
        if k not in ignore and k not in out:
            out[k] = managed[k]
    for k in ignored_from:
        if k in ignore and k not in out:
            out[k] = ignored_from[k]
    return out


def to_json_bytes(obj) -> bytes:
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def _flatten(v, seg: list, out: dict) -> None:
    if isinstance(v, dict) and v:
        for k, x in v.items():
            _flatten(x, seg + [str(k)], out)
    elif isinstance(v, list) and v:
        for i, x in enumerate(v):
            _flatten(x, seg + [f"[{i}]"], out)
    else:
        text = "{}" if isinstance(v, dict) else "[]" if isinstance(v, list) else json.dumps(v, ensure_ascii=False)
        out[".".join(seg)] = (seg, text)


# ---------------------------------------------------------------------------
# 差異輸出
# ---------------------------------------------------------------------------

_SENSITIVE = re.compile(r"token|secret|password|auth|credential", re.I)
_KEYLIKE = re.compile(r"^(key|api[_-]?key|access[_-]?key|private[_-]?key)$", re.I)


def is_sensitive_path(segments) -> bool:
    """任一路徑段含 token / secret / password / auth / credential、為 key 類名稱，或位於 env 子樹。"""
    for s in segments:
        if _SENSITIVE.search(s) or _KEYLIKE.match(s) or s.lower() == "env":
            return True
    return False


def write_value_diff(segments, local: str, want: str) -> None:
    if is_sensitive_path(segments):
        local = want = "***"
    print(f"  {'.'.join(segments).replace('.[', '[')}: {local} → {want}")


def write_json_diff(local: dict, want: dict) -> None:
    a: dict = {}
    b: dict = {}
    _flatten(local, [], a)
    _flatten(want, [], b)
    for k in list(b) + [k for k in a if k not in b]:
        l = a[k][1] if k in a else "(missing)"
        w = b[k][1] if k in b else "(missing)"
        if l == w:
            continue
        write_value_diff((b[k] if k in b else a[k])[0], l, w)


def line_diff(a: list, b: list) -> list:
    """逐行差異（LCS）：'-' 為本機、'+' 為預期，只列出不同的行。"""
    n, m = len(a), len(b)
    t = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            t[i][j] = t[i + 1][j + 1] + 1 if a[i] == b[j] else max(t[i + 1][j], t[i][j + 1])
    out = []
    i = j = 0
    while i < n and j < m:
        if a[i] == b[j]:
            i += 1
            j += 1
        elif t[i + 1][j] >= t[i][j + 1]:
            out.append(f"- {a[i]}")
            i += 1
        else:
            out.append(f"+ {b[j]}")
            j += 1
    out.extend(f"- {x}" for x in a[i:])
    out.extend(f"+ {x}" for x in b[j:])
    return out


def write_text_diff(local: str, want: str) -> None:
    lines = line_diff(re.split(r"\r?\n", local.rstrip("\r\n")), re.split(r"\r?\n", want.rstrip("\r\n")))
    if not lines:
        print("  （僅 BOM、換行字元或結尾空行不同）")
        return
    print("  - 本機 / + 預期")
    for line in lines:
        print(f"  {line}")


@dataclass
class PlanItem:
    target: Path
    data: bytes
    kind: str  # json / text / toml
    state: str  # missing / same / differs / update
    local: object = None
    want: object = None
    changes: list = field(default_factory=list)


def write_plan_overview(plan) -> None:
    for p in plan:
        print(f"{p.state:<8} {p.target}")


def report_plan_and_stop(plan, force: bool) -> None:
    """有 differs 且未 --force 時警告並中止（不寫入任何檔案）。"""
    differs = [p for p in plan if p.state == "differs"]
    if differs and not force:
        for p in differs:
            warn(f"內容與 repo 不同：{p.target}")
        raise SyncError("已中止，未寫入任何檔案。要覆蓋加 --force；要保留本機變更先跑 --pull-win / --pull-wsl。")


def apply_plan(plan) -> None:
    for p in plan:
        if p.state == "same":
            continue
        write_bytes(p.target, p.data, mkdir=True)
        print(f"[{p.state}] -> {p.target}")
    print(f"已同步；{sum(p.state == 'same' for p in plan)} 個檔案原本就相同。")


def run_main(func, argv, repo) -> int:
    """入口共用的外殼：UTF-8 輸出、預期內錯誤轉為訊息與非零結束。"""
    configure_stdio()
    repo = Path(repo) if repo is not None else Path(__file__).resolve().parent
    try:
        func(argv, repo)
    except SyncError as e:
        print(f"錯誤: {e}", file=sys.stderr)
        return 1
    return 0
