"""同步 repo `ssh/config/` 與 Windows/WSL 的 `~/.ssh`.

只管理 config,ipc.conf,with-identity.conf,不讀取或管理金鑰,known_hosts,authorized_keys.

檔案對應:
  config/config                 <-> ~/.ssh/config(共用入口)
  config/ipc.conf               <-> ~/.ssh/ipc.conf(共用)
  config/with-identity.win.conf <-> Windows ~/.ssh/with-identity.conf
  config/with-identity.wsl.conf <-> WSL ~/.ssh/with-identity.conf
有 IdentityFile 的 Host 整段放各端 with-identity 檔(只有路徑).

用法(從 repo 根目錄,Python 3.10+,無需套件):
  Windows:
        py -3 ssh/sync.py --check | --push | --pull [--win-only | --wsl-only] [--distro NAME]

    --check 比對 Win + WSL
    --push repo → 本機
    --pull 本機 → repo

  WSL 內:
        python3 ssh/sync.py --check | --push | --pull

    僅處理目前使用者,不接受 --win-only,--wsl-only,--distro

行為重點:
  - --check,--push,--pull 三選一且必填;exit 0 一致,1 有差異,2 錯誤
  - CRLF 與 LF 視為相同,寫入一律 LF
  - 寫入前先讀完並檢查來源缺失;內容相同的檔案略過
  - pull 兩端時共用檔(config,ipc.conf)需一致,否則整批中止,
    可用 --win-only 或 --wsl-only 指定來源
  - 逐檔原子替換(非 transaction);Windows 保留 ACL,
    WSL 保留 mode,新檔 0600;拒絕 symbolic link

測試:py -3 -m unittest discover -s ssh/src -p "test_*.py" -v
(WSL 用 python3 另驗 Linux 權限與 helper protocol)
"""
from __future__ import annotations

import argparse
import base64
import ctypes
import inspect
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import sys
import tempfile

CONFIG = Path(__file__).resolve().parent / "config"
FILES = ("config", "ipc.conf", "with-identity.conf")


def read_file(path: Path) -> bytes | None:
    if path.is_symlink():
        raise OSError(f"不支援 symbolic link：{path}")
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def atomic_write(path: Path, data: bytes) -> None:
    """逐檔原子替換；Windows ReplaceFileW 保留既有 ACL。"""
    if path.is_symlink():
        raise OSError(f"不支援 symbolic link：{path}")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=".ssh-sync-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        if os.name == "nt" and path.exists():
            replace = ctypes.WinDLL("kernel32", use_last_error=True).ReplaceFileW
            replace.argtypes = (ctypes.c_wchar_p, ctypes.c_wchar_p, ctypes.c_wchar_p,
                                ctypes.c_uint32, ctypes.c_void_p, ctypes.c_void_p)
            replace.restype = ctypes.c_int
            if not replace(str(path), temporary, None, 0, None, None):
                raise ctypes.WinError(ctypes.get_last_error())
        else:
            os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def normalized(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n")


# 在 WSL 內執行的 helper；原始碼取自本檔函式，須在 read_file、atomic_write 定義之後組裝。
REMOTE_SCRIPT = (
    "import base64, ctypes, json, os, stat, sys, tempfile\nfrom pathlib import Path\n"
    + inspect.getsource(read_file) + "\n" + inspect.getsource(atomic_write)
    + "\ntry:\n"
      "    request = json.load(sys.stdin)\n"
      "    root = Path.home() / '.ssh'\n"
      "    if request['operation'] == 'home':\n"
      "        result = str(root)\n"
      "    elif request['operation'] == 'read':\n"
      "        result = {}\n"
      "        for name in request['names']:\n"
      "            data = read_file(root / name)\n"
      "            result[name] = None if data is None else base64.b64encode(data).decode('ascii')\n"
      "    else:\n"
      "        atomic_write(root / request['name'], base64.b64decode(request['data']))\n"
      "        result = None\n"
      "    print(json.dumps({'result': result}))\n"
      "except Exception as error:\n"
      "    print(json.dumps({'error': str(error)}))\n"
)


def stderr_tail(raw: bytes | None, lines: int = 5) -> str:
    """取 stderr 最後幾行（無法解碼的字元以 replace 處理），無內容回傳空字串。"""
    text = (raw or b"").decode("utf-8", errors="replace").strip()
    return "\n".join(text.splitlines()[-lines:])


class LocalStore:
    def __init__(self, root: Path):
        self.root = root.resolve()

    def read(self, names: tuple[str, ...]) -> dict[str, bytes | None]:
        return {name: read_file(self.root / name) for name in names}

    def write(self, name: str, data: bytes) -> None:
        atomic_write(self.root / name, normalized(data))

    def path(self, name: str) -> str:
        return str(self.root / name)


class WslStore:
    """透過 WSL 內的 Python 存取檔案，避免 UNC 寫入遺失 Linux 權限。"""
    def __init__(self, distro: str):
        self.distro = distro
        self.root = self.call("home")

    def call(self, operation: str, **payload):
        result = None
        try:
            result = subprocess.run(
                ["wsl.exe", "-d", self.distro, "--", "python3", "-c", REMOTE_SCRIPT],
                input=json.dumps({"operation": operation, **payload}).encode("utf-8"),
                capture_output=True, timeout=60,
            )
            if result.returncode:
                detail = stderr_tail(result.stderr)
                raise OSError(f"WSL ({self.distro}) Python 執行失敗，exit {result.returncode}"
                              + (f"：\n{detail}" if detail else ""))
            response = json.loads(result.stdout.decode("utf-8"))
            if "error" in response:
                raise OSError(response["error"])
            return response["result"]
        except (subprocess.SubprocessError, UnicodeError, ValueError, KeyError) as error:
            detail = stderr_tail(getattr(result, "stderr", None) or getattr(error, "stderr", None))
            raise OSError(f"無法存取 WSL ({self.distro})：{type(error).__name__}"
                          + (f"：\n{detail}" if detail else "")) from None

    def read(self, names: tuple[str, ...]) -> dict[str, bytes | None]:
        return {name: None if data is None else base64.b64decode(data)
                for name, data in self.call("read", names=names).items()}

    def write(self, name: str, data: bytes) -> None:
        self.call("write", name=name, data=base64.b64encode(normalized(data)).decode("ascii"))

    def path(self, name: str) -> str:
        return f"{self.distro}:{self.root}/{name}"


def repo_name(name: str, kind: str) -> str:
    return f"with-identity.{kind}.conf" if name == "with-identity.conf" else name


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    for flag, help_text in (("check", "唯讀比對"), ("pull", "本機 → repo"), ("push", "repo → 本機")):
        mode.add_argument(f"--{flag}", action="store_true", help=help_text)
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--win-only", action="store_true", help="僅 Windows")
    target.add_argument("--wsl-only", action="store_true", help="僅 WSL")
    parser.add_argument("--distro", default=None, help="WSL distro（預設 Ubuntu-24.04）")
    args = parser.parse_args(argv)
    is_wsl = sys.platform.startswith("linux") and (
        os.environ.get("WSL_DISTRO_NAME") or "microsoft" in platform.release().lower())
    if sys.platform != "win32" and not is_wsl:
        parser.error("僅支援 Windows 與 WSL")
    if is_wsl and (args.win_only or args.wsl_only or args.distro is not None):
        parser.error("WSL 執行只處理目前使用者，不接受 --win-only、--wsl-only 或 --distro")
    args.local_wsl = bool(is_wsl)
    return args


def sync(mode: str, repo: LocalStore, targets: list[tuple[str, object]]) -> int:
    """所有讀取、來源檢查與 pull 衝突檢查完成後才開始寫入。"""
    names = tuple(dict.fromkeys(repo_name(name, kind) for kind, _ in targets for name in FILES))
    saved = repo.read(names)
    live = [(kind, store, store.read(FILES)) for kind, store in targets]
    pending = {}
    differs = False
    for kind, store, data in live:
        for name in FILES:
            key = repo_name(name, kind)
            expected, actual = saved[key], data[name]
            status = ("missing" if expected is None or actual is None else
                      "same" if normalized(expected) == normalized(actual) else "differs")
            print(f"{status:7} {kind:3} {store.path(name)} <-> {repo.path(key)}")
            differs |= status != "same"
            if mode == "check":
                continue
            if mode == "pull":
                source, origin = actual, store.path(name)
                destination, dest_name, previous = repo, key, expected
            else:
                source, origin = expected, repo.path(key)
                destination, dest_name, previous = store, name, actual
            if source is None:
                raise OSError(f"來源缺失，未寫入任何檔案：{origin}")
            slot = (id(destination), dest_name)
            if slot in pending and normalized(pending[slot][2]) != normalized(source):
                raise OSError(f"共用檔來源衝突，未寫入任何檔案：{key}；請使用單端選項指定來源")
            pending[slot] = (destination, dest_name, source, previous)
    if mode == "check":
        return int(differs)
    writes = [(store, name, source) for store, name, source, previous in pending.values()
              if previous is None or normalized(source) != normalized(previous)]
    for index, (store, name, source) in enumerate(writes):
        try:
            store.write(name, source)
        except OSError:
            print(f"寫入中止；已完成 {index}，以下未完成：", file=sys.stderr)
            for remaining, filename, _ in writes[index:]:
                print(f"  {remaining.path(filename)}", file=sys.stderr)
            raise
        print(f"written {store.path(name)}")
    return 0


def main(argv=None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    args = parse_args(argv)
    try:
        if args.local_wsl:
            targets = [("wsl", LocalStore(Path.home() / ".ssh"))]
        else:
            targets = []
            if not args.wsl_only:
                targets.append(("win", LocalStore(Path.home() / ".ssh")))
            if not args.win_only:
                targets.append(("wsl", WslStore(args.distro or "Ubuntu-24.04")))
        return sync("check" if args.check else "pull" if args.pull else "push", LocalStore(CONFIG), targets)
    except OSError as error:
        print(f"錯誤：{error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
