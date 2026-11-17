#!/usr/bin/env python3
"""Herdr popup: open 在右側 split 開 Yazi(focused pane 正在 ssh 時先以 sshfs 掛載該 host 的 /, 否則開本機 cwd); unmount 選擇既有掛載後卸載.

部署至 ~/.config/herdr/herdr-sshfs.py; 需要 ~/.local/bin/sshfs-mount 與 yazi.
用法: herdr-sshfs.py [open|unmount] [--default-path PATH]
"""
import argparse
import json
import os
import re
import select
import shlex
import shutil
import subprocess
import sys
import termios
import tty
import unicodedata
from contextlib import contextmanager

MOUNT_ROOT = os.path.expanduser("~/mnt")
SSHFS_MOUNT = shutil.which("sshfs-mount") or os.path.expanduser("~/.local/bin/sshfs-mount")
# 每台 host 上次開啟的遠端絕對路徑
STATE_FILE = os.path.expanduser("~/.local/state/herdr-sshfs.json")
# ssh 需要帶值的 option, 解析 host 時要跳過其值
SSH_VALUE_OPTIONS = set("BbcDEeFIiJLlmOoPpQRSWw")


@contextmanager
def terminal():
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        print("\033[?1049h\033[?25l", end="", flush=True)
        yield
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        print("\033[0m\033[?25h\033[?1049l", end="", flush=True)


def read_key(timeout=None):
    fd = sys.stdin.fileno()
    if not select.select([fd], [], [], timeout)[0]:
        return "resize"
    char = os.read(fd, 1)
    if not char:
        raise EOFError()
    if char != b"\x1b":
        return {b"\r": "enter", b"\n": "enter", b"\x7f": "backspace", b"\x08": "backspace"}.get(char, char.decode("ascii", "ignore"))
    sequence = b""
    while select.select([fd], [], [], 0.04)[0]:
        sequence += os.read(fd, 1)
        if len(sequence) > 1 and 0x40 <= sequence[-1] <= 0x7e:
            break
        if len(sequence) >= 16:
            break
    if not sequence:
        return "esc"
    return {b"[A": "up", b"[B": "down", b"OA": "up", b"OB": "down"}.get(sequence, "other")


def fit(text, width):
    clean = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(text))
    result, used = "", 0
    for char in clean:
        size = 0 if unicodedata.combining(char) else (2 if unicodedata.east_asian_width(char) in "WF" else 1)
        if used + size > width:
            break
        result += char
        used += size
    return result


def choose(labels, title):
    selected, digits, message = 0, "", ""
    previous = None
    while True:
        width, height = shutil.get_terminal_size((80, 24))
        rows = max(1, height - 3)
        start = max(0, min(selected - rows + 1, len(labels) - rows))
        lines = [fit(title + " ↑↓ / 數字 / Enter / Esc Q", max(1, width - 1))]
        for index in range(start, min(len(labels), start + rows)):
            line = fit(f"{index + 1}. {labels[index]}", max(1, width - 1))
            lines.append(("\033[7m" + line + "\033[0m") if index == selected else line)
        lines.append(fit(message or ("編號：" + digits if digits else "Enter 確認；Esc / Q 取消"), max(1, width - 1)))
        if height < 3:
            lines = lines[1:1 + height]
        state = (width, height, selected, digits, message)
        if state != previous:
            print("\033[H\033[2J" + "\r\n".join(lines[:max(1, height)]), end="", flush=True)
            previous = state
        key = read_key(0.15)
        if key in ("esc", "q", "Q"):
            return None
        if key in ("up", "down"):
            digits, message = "", ""
            selected = max(0, min(len(labels) - 1, selected + (-1 if key == "up" else 1)))
        elif key == "backspace":
            digits, message = digits[:-1], ""
        elif len(key) == 1 and key in "0123456789":
            if len(digits) < 100:
                digits += key
            message = ""
        elif key == "enter":
            if digits and not 1 <= int(digits) <= len(labels):
                message = "無效選項，請修改編號或使用方向鍵。"
                continue
            return selected + 1
        if digits and 1 <= int(digits) <= len(labels):
            selected = int(digits) - 1


def confirm(message):
    """顯示訊息, Enter 回傳 True, Esc 回傳 False."""
    print("\033[H\033[2J" + fit(message, max(1, shutil.get_terminal_size().columns - 1)) + "\r\nEnter 繼續；Esc 取消。", end="", flush=True)
    while True:
        key = read_key()
        if key in ("enter", "esc"):
            return key == "enter"


def prompt(text):
    """在 cbreak 模式下讀一行輸入(支援 Backspace); Esc 取消回傳 None."""
    print("\033[?25h" + text, end="", flush=True)
    value = ""
    while True:
        key = read_key()
        if key == "enter":
            print("\033[?25l\r\n", end="", flush=True)
            return value
        if key == "esc":
            return None
        if key == "backspace":
            if value:
                value = value[:-1]
                print("\b \b", end="", flush=True)
        elif len(key) == 1 and key.isprintable():
            value += key
            print(key, end="", flush=True)


def ssh_host(cli, pane):
    """從 pane 的 foreground process 找 ssh 的 host(第一個非 option 參數)."""
    try:
        info = cli("pane", "process-info", "--pane", pane)["process_info"]
    except Exception:
        return ""
    for process in info.get("foreground_processes") or []:
        argv = process.get("argv") or []
        if not argv or os.path.basename(process.get("name") or argv[0]) != "ssh":
            continue
        index = 1
        while index < len(argv):
            arg = argv[index]
            if arg == "--":
                return argv[index + 1] if index + 1 < len(argv) else ""
            if arg.startswith("-") and len(arg) > 1:
                for position, letter in enumerate(arg[1:], 1):
                    if letter in SSH_VALUE_OPTIONS:
                        if position == len(arg) - 1:
                            index += 1
                        break
                index += 1
                continue
            return re.sub(r"^ssh://", "", arg)
    return ""


def remote_resolve(host, path):
    """以 ssh 將遠端路徑(空字串為 home, 可用 ~/ 開頭或相對 home)解析成絕對路徑; 不存在回傳 None."""
    if not path or path == "~":
        command = "cd && pwd -P"
    elif path.startswith("~/"):
        command = "cd ~/" + shlex.quote(path[2:]) + " && pwd -P"
    else:
        command = "cd -- " + shlex.quote(path) + " && pwd -P"
    result = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", host, command],
                            stdin=subprocess.DEVNULL, capture_output=True, text=True)
    lines = result.stdout.strip().splitlines()
    return lines[-1] if result.returncode == 0 and lines and lines[-1].startswith("/") else None


def load_state():
    try:
        with open(STATE_FILE, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, ValueError):
        return {}


def save_last_path(host, path):
    state = load_state()
    state[host] = path
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as file:
        json.dump(state, file, indent=2)


def mounts():
    """回傳 [(target, source)], 只含 fuse.sshfs."""
    result = subprocess.run(["findmnt", "-t", "fuse.sshfs", "-n", "-r", "-o", "TARGET,SOURCE"], capture_output=True, text=True)
    # findmnt -r 以 \x20 等形式跳脫空白
    decode = lambda text: re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), text)
    items = []
    for line in result.stdout.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2:
            items.append((decode(parts[0]), decode(parts[1])))
    return items


def open_browser(cli, sshfs_mount, pane, default_path):
    """focused pane 正在 ssh 時開遠端(經 sshfs), 否則以該 pane 的 cwd 開本機 Yazi."""
    host = ssh_host(cli, pane)
    if not host:
        cwd = next((p.get("cwd") for p in cli("pane", "list")["panes"] if p["pane_id"] == pane), None)
        open_yazi(cli, pane, cwd or os.path.expanduser("~"))
        return
    print("\033[H\033[2J" + f"host: {host}", flush=True)
    target = os.path.join(MOUNT_ROOT, host)
    existing = dict(mounts()).get(target)
    if existing is not None and existing != f"{host}:/":
        if not confirm(f"{target} 為舊式掛載 ({existing}); Enter 卸載並改掛 {host}:/"):
            return
        print("\033[H\033[2J" + f"host: {host}\r\n卸載舊式掛載 ...", flush=True)
        sshfs_mount("-u", host)
        existing = None
    if existing is not None:
        # 已掛載: 不詢問, 開上次的路徑, 否則 --default-path, 都不存在則開遠端 /
        for path in (load_state().get(host), default_path):
            if path and path.startswith("/") and os.path.isdir(target + path):
                open_yazi(cli, pane, target + path)
                return
        open_yazi(cli, pane, target)
        return
    default = ""
    if default_path:
        print(f"檢查遠端 {default_path} ...", flush=True)
        default = remote_resolve(host, default_path) or ""
    while True:
        path = prompt(f"RemotePath [{default or '遠端 home'}]: ")
        if path is None:
            return
        resolved = remote_resolve(host, path.strip() or default)
        if resolved:
            break
        print(f"遠端不存在或無法連線: {path.strip() or '遠端 home'}", flush=True)
    print("掛載中 ...", flush=True)
    sshfs_mount(host)
    save_last_path(host, resolved)
    open_yazi(cli, pane, target + resolved.rstrip("/"))


def open_yazi(cli, pane, root):
    """在 active pane 右側 split 一個 shell, cd 到 root 後執行 yazi; 離開 yazi 後留下該 shell(cwd 為 root)."""
    # 不用 --cwd root: 以 sshfs 路徑為 cwd 開 pane, shell 要約 3.5s 才出 prompt; 先在 home 開再 cd 只要約 0.3s
    new_pane = cli("pane", "split", "--pane", pane, "--direction", "right", "--cwd", os.path.expanduser("~"), "--focus")["pane"]["pane_id"]
    # pane run 的輸出不是 JSON, 只看 exit code
    result = subprocess.run([os.environ["HERDR_BIN_PATH"], "pane", "run", new_pane, "cd -- " + shlex.quote(root) + " && yazi"],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())


def unmount(cli, sshfs_mount):
    items = mounts()
    if not items:
        print("\033[H\033[2J沒有 sshfs 掛載\r\n按 Esc 或 Enter 關閉。", end="", flush=True)
        while read_key() not in ("esc", "enter"):
            pass
        return
    home = os.path.expanduser("~")
    labels = [f"{target.replace(home, '~', 1)}  {source}" for target, source in items]
    choice = choose(labels, "卸載 sshfs")
    if choice is None:
        return
    target = items[choice - 1][0]
    try:
        busy = [p["pane_id"] for p in cli("pane", "list")["panes"]
                if p.get("cwd") and (p["cwd"].rstrip("/") == target or p["cwd"].startswith(target + "/"))]
    except Exception:
        busy = []
    if busy and not confirm(f"有 {len(busy)} 個 pane 的 cwd 在 {target} 內: {', '.join(busy)}; 仍要卸載?"):
        return
    if os.path.dirname(target) == MOUNT_ROOT:
        sshfs_mount("-u", os.path.basename(target))
    else:
        result = subprocess.run(["fusermount3", "-u", target], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", default="open", choices=["open", "unmount"])
    parser.add_argument("--default-path", default="")
    args = parser.parse_args()
    binary = os.environ["HERDR_BIN_PATH"]
    pane = os.environ["HERDR_ACTIVE_PANE_ID"]

    def cli(*cli_args):
        result = subprocess.run([binary, *cli_args], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        data = json.loads(result.stdout)
        if "error" in data:
            raise RuntimeError(str(data["error"]))
        return data["result"]

    def sshfs_mount(*mount_args):
        result = subprocess.run([SSHFS_MOUNT, *mount_args], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return result.stdout

    if args.mode == "unmount":
        unmount(cli, sshfs_mount)
    else:
        open_browser(cli, sshfs_mount, pane, args.default_path)


if __name__ == "__main__":
    with terminal():
        try:
            main()
        except KeyboardInterrupt:
            pass
        except Exception as error:
            print("\033[H\033[2J" + fit(f"失敗： {error}", max(1, shutil.get_terminal_size().columns - 1)) + "\r\n按 Esc 或 Enter 關閉。", end="", flush=True)
            try:
                while read_key() not in ("esc", "enter"):
                    pass
            except (EOFError, KeyboardInterrupt):
                pass
            raise SystemExit(1)
