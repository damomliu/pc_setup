"""同步 team skill：把 repo 的 agent-skill/team/ mirror 到 Claude Code 與 Codex 的 global skills 目錄。

目標（每個 home）：
    <home>/.agents/skills/team   Codex
    <home>/.claude/skills/team   Claude Code

平台：
    Windows：Windows home + WSL home（--distro，預設 Ubuntu-24.04；--win-only 完全略過 WSL）
    WSL / macOS / Linux：只處理本機 HOME

用法：
    python agent-skill/sync.py --check   列出差異，不寫入；有差異 exit 1
    python agent-skill/sync.py --push    mirror 寫入；目標多出的檔案會刪除

安全：
    - 目標路徑元件（home、.agents、.agents/skills、.claude、.claude/skills、team 及其內容）任一為
      symlink / junction 就拒絕，任何寫入前先檢查全部目標
    - 目錄掃描錯誤一律中止，不以不完整的掃描結果計算 diff
    - 寫入與刪除前都以解析後的實際路徑確認在 team/ 之下；寫入用同目錄暫存檔加 os.replace，
      不原地截斷（避免改到 hard link 的外部檔案）；目錄逐層建立並檢查；多出的目錄在清空後用 rmdir 移除
    - 只比對與寫入 bytes，保留換行字元

Exit code：0 無差異或推送完成；1 --check 有差異；2 錯誤。
"""
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "agent" / "src"))

import argparse  # noqa: E402
import os  # noqa: E402
import stat  # noqa: E402
import tempfile  # noqa: E402
from dataclasses import dataclass  # noqa: E402

import sync_common as c  # noqa: E402

SKILL = "team"
SOURCE = HERE / SKILL
# (agent 標籤, home 底下的路徑元件)
TOOLS = (("Claude", (".claude", "skills", SKILL)), ("Codex", (".agents", "skills", SKILL)))


@dataclass
class Target:
    label: str
    home: Path
    parts: tuple

    @property
    def path(self) -> Path:
        return self.home.joinpath(*self.parts)


@dataclass
class Diff:
    added: list
    modified: list
    removed: list  # 目標多出的檔案與目錄（相對路徑，目錄結尾為 /）

    def empty(self) -> bool:
        return not (self.added or self.modified or self.removed)


def parse_args(argv):
    p = argparse.ArgumentParser(prog="sync.py", allow_abbrev=False,
                                description="同步 team skill 到 global skills 目錄")
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="列出差異，不寫入")
    mode.add_argument("--push", action="store_true", help="mirror 寫入目標")
    p.add_argument("--distro", default=c.DEFAULT_DISTRO, help="WSL distro（僅 Windows）")
    p.add_argument("--win-only", action="store_true", help="只處理 Windows，不碰 WSL（僅 Windows）")
    p.add_argument("--test-win-home", help=argparse.SUPPRESS)
    p.add_argument("--test-wsl-root", help=argparse.SUPPRESS)
    return p.parse_args(argv)


def is_link(p: Path) -> bool:
    """symlink 或 Windows reparse point（junction 等）。路徑不存在回傳 False。"""
    try:
        st = os.lstat(p)
    except FileNotFoundError:
        return False
    if stat.S_ISLNK(st.st_mode):
        return True
    attrs = getattr(st, "st_file_attributes", 0)
    return bool(attrs & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def build_targets(a, plat: str) -> list:
    for flag, value in (("--test-win-home", a.test_win_home), ("--test-wsl-root", a.test_wsl_root)):
        if value is not None and not value.strip():
            raise c.SyncError(f"{flag} 不能是空字串")
    homes = []
    if plat == "windows":
        # 測試覆寫須成對（或 --win-only 只給 Windows），避免一端回退到真實 HOME
        if a.win_only and a.test_wsl_root is not None:
            raise c.SyncError("--win-only 不能與 --test-wsl-root 併用")
        if not a.win_only and (a.test_win_home is None) != (a.test_wsl_root is None):
            raise c.SyncError("--test-win-home 與 --test-wsl-root 須同時指定（或搭配 --win-only 只指定 --test-win-home）")
        homes.append(("Win", Path(a.test_win_home) if a.test_win_home is not None else c.local_home()))
        if not a.win_only:
            if a.test_wsl_root is not None:
                homes.append(("WSL", Path(a.test_wsl_root)))
            else:
                homes.append(("WSL", c.wsl_unc_root(a.distro, c.query_wsl_home(a.distro))))
    elif plat in ("wsl", "macos", "linux"):
        if a.win_only or a.test_win_home is not None:
            raise c.SyncError("--win-only / --test-win-home 只能在 Windows 使用")
        prefix = {"wsl": "WSL", "macos": "macOS", "linux": "Linux"}[plat]
        homes.append((prefix, Path(a.test_wsl_root) if a.test_wsl_root is not None else c.local_home()))
    else:
        raise c.SyncError(f"不支援的平台：{plat}")
    return [Target(f"{prefix}-{tool}", home, parts) for prefix, home in homes for tool, parts in TOOLS]


def walk(root: Path):
    """回傳 (files, dirs) 相對 posix 路徑集合；遇到 link 拋錯，不 follow。"""
    files, dirs = set(), set()

    def fail(err: OSError):
        raise c.SyncError(f"無法掃描目錄：{err}")

    for dirpath, dirnames, filenames in os.walk(root, onerror=fail, followlinks=False):
        base = Path(dirpath)
        for name in dirnames + filenames:
            if is_link(base / name):
                raise c.SyncError(f"拒絕處理 symlink / junction：{base / name}")
        rel = base.relative_to(root)
        for d in dirnames:
            dirs.add((rel / d).as_posix())
        for f in filenames:
            files.add((rel / f).as_posix())
    return files, dirs


def check_links(t: Target) -> None:
    """home 與其下每個路徑元件、team/ 內容都不能是 link。"""
    p = t.home
    if is_link(p):
        raise c.SyncError(f"{t.label}: 拒絕處理 symlink / junction：{p}")
    for part in t.parts:
        p = p / part
        if is_link(p):
            raise c.SyncError(f"{t.label}: 拒絕處理 symlink / junction：{p}")
    if t.path.exists():
        if not t.path.is_dir():
            raise c.SyncError(f"{t.label}: 目標不是目錄：{t.path}")
        walk(t.path)


def diff(src_files: set, src_dirs: set, dst: Path) -> Diff:
    if not dst.exists():
        return Diff(sorted(src_files), [], [])
    dst_files, dst_dirs = walk(dst)
    added, modified = [], []
    for rel in sorted(src_files):
        if rel not in dst_files:
            added.append(rel)
        elif (SOURCE / rel).read_bytes() != (dst / rel).read_bytes():
            modified.append(rel)
    removed = sorted(dst_files - src_files) + sorted(d + "/" for d in dst_dirs - src_dirs)
    return Diff(added, modified, removed)


def real(p: Path) -> str:
    return os.path.normcase(os.path.realpath(p))


def inside(root_real: str, p: Path) -> Path:
    """p 不能是 link，且解析後的實際路徑須在 root_real 之下（不含 root 本身）。"""
    if is_link(p):
        raise c.SyncError(f"拒絕處理 symlink / junction：{p}")
    q = real(p)
    if q == root_real or os.path.commonpath([root_real, q]) != root_real:
        raise c.SyncError(f"路徑超出 {root_real}：{p}")
    return p


def make_dirs(base: Path, parts, root_real: str | None = None) -> Path:
    """由 base 逐層建立目錄；每層建立前後都確認不是 link，有 root_real 時也確認在邊界內。"""
    p = base
    for part in parts:
        p = p / part
        for _ in range(2):  # 建立前、建立後各檢查一次
            if root_real is not None:
                inside(root_real, p)
            elif is_link(p):
                raise c.SyncError(f"拒絕處理 symlink / junction：{p}")
            if not p.exists():
                p.mkdir()
        if not p.is_dir():
            raise c.SyncError(f"不是目錄：{p}")
    return p


def write_file(root_real: str, p: Path, data: bytes) -> None:
    """同目錄排他建立唯一暫存檔，寫入後 os.replace；不原地截斷既有檔案。"""
    if real(p.parent) != root_real:
        inside(root_real, p.parent)
    fd, tmp = tempfile.mkstemp(dir=p.parent, prefix=".sync-", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        inside(root_real, Path(tmp))
        os.replace(tmp, inside(root_real, p))
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def push(t: Target, d: Diff) -> None:
    if is_link(t.home):
        raise c.SyncError(f"{t.label}: 拒絕處理 symlink / junction：{t.home}")
    root = make_dirs(t.home, t.parts)
    check_links(t)
    root_real = real(root)
    # 先刪檔、再由深到淺 rmdir 已清空的目錄；目錄型別衝突（目標是目錄、來源是檔案）一併處理
    for rel in [r for r in d.removed if not r.endswith("/")]:
        inside(root_real, root / rel).unlink()
    for rel in sorted((r.rstrip("/") for r in d.removed if r.endswith("/")), key=lambda r: -r.count("/")):
        inside(root_real, root / rel).rmdir()
    for rel in d.added + d.modified:
        parts = rel.split("/")
        parent = make_dirs(root, parts[:-1], root_real)
        write_file(root_real, parent / parts[-1], (SOURCE / rel).read_bytes())


def main(argv=None) -> int:
    c.configure_stdio()
    argv = sys.argv[1:] if argv is None else list(argv)
    try:
        a = parse_args(argv)
        if not (SOURCE / "SKILL.md").is_file():
            raise c.SyncError(f"找不到來源：{SOURCE / 'SKILL.md'}")
        src_files, src_dirs = walk(SOURCE)
        targets = build_targets(a, c.detect_platform())
        for t in targets:  # 任何寫入前先檢查全部目標
            check_links(t)
        diffs = [(t, diff(src_files, src_dirs, t.path)) for t in targets]
        dirty = False
        for t, d in diffs:
            status = "相同" if d.empty() else ("已更新" if a.push else "有差異")
            print(f"[{t.label}] {t.path}: {status}")
            for mark, items in (("+", d.added), ("~", d.modified), ("-", d.removed)):
                for rel in items:
                    print(f"  {mark} {rel}")
            if not d.empty():
                dirty = True
                if a.push:
                    push(t, d)
        return 1 if dirty and a.check else 0
    except c.SyncError as e:
        print(f"錯誤: {e}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"錯誤: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
