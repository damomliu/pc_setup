"""在 repo 的 vscode/ 與 %APPDATA%\\Code\\User 之間同步 VS Code 設定。

用法：
    python vscode/sync_vscode.py [選項]

選項：
    預設              repo -> VS Code（settings.json、keybindings.json、mcp.json）。
                      VS Code 執行中也可以跑，會自動重載。
    --pull            VS Code -> repo，在 VS Code UI 改過設定後用來收回 repo。
    --check           唯讀。比對設定檔（same / differ / missing）與各 profile 的 extension
                      （與 extensions.json 比對；缺少或多出都算差異）。有差異 exit 1。
                      JSON 依語意比對，忽略 key 順序、註解與格式。
    --check-verbose   隱含 --check；另印出差異檔案的 unified diff，以及各 profile 缺少／多出的 extension。
    --extensions      依 extensions.json 補裝各 profile 缺少的 extension。
    --prune           搭配 --extensions，另外移除 extensions.json 沒列的 extension。

--check / --check-verbose 不能與 --pull、--extensions 並用；--prune 必須搭配 --extensions。
"""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
import difflib
import json
import os
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent
USER = Path(os.environ.get("APPDATA", "")) / "Code" / "User"
CODE = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Microsoft VS Code" / "bin" / "code.cmd"
FILES = ("settings.json", "keybindings.json", "mcp.json")


def configure_stdio() -> None:
    """stdout／stderr 設為 UTF-8，避免非 UTF-8 的 Windows terminal 無法輸出繁體中文與箭頭。"""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure:
            reconfigure(encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="同步 repo 的 vscode/ 與 VS Code 使用者設定。", allow_abbrev=False
    )
    parser.add_argument("--pull", action="store_true", help="VS Code -> repo")
    parser.add_argument("--check", action="store_true", help="唯讀比對設定檔與 extension")
    parser.add_argument("--check-verbose", action="store_true", help="--check 並列出 diff 與 extension 明細")
    parser.add_argument("--extensions", action="store_true", help="補裝缺少的 extension")
    parser.add_argument("--prune", action="store_true", help="搭配 --extensions，移除清單外的 extension")
    args = parser.parse_args(argv)
    checking = args.check or args.check_verbose
    if checking and (args.pull or args.extensions):
        parser.error("--check / --check-verbose 不能與 --pull、--extensions 並用")
    if args.prune and not args.extensions:
        parser.error("--prune 必須搭配 --extensions")
    args.check = checking
    return args


def profile_args(name: str) -> list[str]:
    """Default profile 不帶 --profile。"""
    return [] if name == "Default" else ["--profile", name]


def run_code(*args: str) -> str:
    """執行 code.cmd 並回傳 stdout；失敗時丟出 RuntimeError。"""
    proc = subprocess.run(
        [str(CODE), *args], capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if proc.returncode != 0:
        raise RuntimeError(f"code {' '.join(args)} 失敗 (exit {proc.returncode}): {proc.stderr.strip()}")
    return proc.stdout


def installed_extensions(profile: str) -> list[str]:
    out = run_code(*profile_args(profile), "--list-extensions")
    return [line.strip().lower() for line in out.splitlines() if line.strip()]


def ext_diff(profile: str, wanted: list[str]) -> tuple[list[str], list[str]]:
    """回傳 (missing, extra)：清單有但未安裝、已安裝但清單沒列；id 一律小寫比對。"""
    installed = installed_extensions(profile)
    want = [w.lower() for w in wanted]
    missing = [w for w in want if w not in installed]
    extra = [i for i in installed if i not in want]
    return missing, extra


def load_wanted() -> dict[str, list[str]]:
    return json.loads((REPO / "extensions.json").read_text(encoding="utf-8"))


def load_jsonc(path: Path) -> object:
    """讀取 JSONC：剝除字串外的 // 與 /* */ 註解及 trailing comma 後以 json.loads 解析。"""
    text = path.read_text(encoding="utf-8-sig")
    # 第一段：剝除註解（字串內的 // 不處理）
    out: list[str] = []
    i, n, in_str = 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 1
            out.append(" ")
        else:
            out.append(c)
        i += 1
    # 第二段：剝除 } 或 ] 之前的 trailing comma
    clean = "".join(out)
    res: list[str] = []
    i, n, in_str = 0, len(clean), False
    while i < n:
        c = clean[i]
        if in_str:
            res.append(c)
            if c == "\\" and i + 1 < n:
                res.append(clean[i + 1])
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            res.append(c)
        elif c == ",":
            j = i + 1
            while j < n and clean[j].isspace():
                j += 1
            if j >= n or clean[j] not in "}]":
                res.append(c)
        else:
            res.append(c)
        i += 1
    return json.loads("".join(res))


def normalized(obj: object) -> list[str]:
    """排序 key 後的縮排 JSON 文字，供 diff 使用。"""
    return (json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n").splitlines(keepends=True)


def check(verbose: bool) -> int:
    diff = 0
    for f in FILES:
        a, b = REPO / f, USER / f
        ja = jb = None
        if not b.exists():
            state = "missing"
        else:
            ja, jb = load_jsonc(a), load_jsonc(b)
            state = "differ" if ja != jb else "same"
        if state != "same":
            diff += 1
        print(f"{state:<8} {f}")
        if verbose and state == "differ":
            sys.stdout.writelines(difflib.unified_diff(normalized(ja), normalized(jb), str(a), str(b)))
            print()
    for profile, wanted in load_wanted().items():
        missing, extra = ext_diff(profile, wanted)
        if missing or extra:
            diff += 1
            print(f"[{profile}] missing {len(missing)}, extra {len(extra)}")
            if verbose:
                for i in missing:
                    print(f"  missing {i}")
                for i in extra:
                    print(f"  extra   {i}")
        else:
            print(f"[{profile}] same")
    return 1 if diff else 0


def copy_files(pull: bool) -> None:
    for f in FILES:
        src, dst = (USER / f, REPO / f) if pull else (REPO / f, USER / f)
        shutil.copyfile(src, dst)
        print(f"{src} -> {dst}")


def install_extensions(prune: bool) -> None:
    for profile, wanted in load_wanted().items():
        missing, extra = ext_diff(profile, wanted)
        for i in missing:
            print(f"[{profile}] install {i}")
            run_code(*profile_args(profile), "--install-extension", i)
        if prune:
            for i in extra:
                print(f"[{profile}] uninstall {i}")
                run_code(*profile_args(profile), "--uninstall-extension", i)


def main(argv: list[str] | None = None) -> int:
    configure_stdio()
    args = parse_args(argv)
    try:
        if args.check:
            return check(args.check_verbose)
        copy_files(args.pull)
        if args.extensions:
            install_extensions(args.prune)
    except (OSError, RuntimeError, json.JSONDecodeError) as e:
        print(f"錯誤: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
