#!/usr/bin/env python3
"""Popup menu: move the original pane within its original workspace."""
import json
import os
import re
import subprocess
import select
import shutil
import sys
import termios
import tty
import unicodedata
from contextlib import contextmanager


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
    # A lone Escape must close immediately; give an arrow sequence a short
    # inter-byte window. Read from the fd throughout (no buffered stdin).
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


def choose(labels):
    selected, digits, message = 0, "", ""
    previous = None
    while True:
        width, height = shutil.get_terminal_size((80, 24))
        rows = max(1, height - 3)
        start = max(0, min(selected - rows + 1, len(labels) - rows))
        lines = [fit("移動 pane 至 tab ↑↓ / 數字 / Enter / Esc Q", max(1, width - 1))]
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


def main():
    binary = os.environ["HERDR_BIN_PATH"]
    pane = os.environ["HERDR_ACTIVE_PANE_ID"]
    workspace = os.environ["HERDR_ACTIVE_WORKSPACE_ID"]
    tab = os.environ["HERDR_ACTIVE_TAB_ID"]

    def cli(*args):
        result = subprocess.run([binary, *args], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        data = json.loads(result.stdout)
        if "error" in data:
            raise RuntimeError(str(data["error"]))
        result = data["result"]
        if "move_result" in result and not result["move_result"].get("changed"):
            raise RuntimeError("Pane was not moved: " + str(result["move_result"].get("reason", "unknown")))
        return result

    def tabs():
        return cli("tab", "list", "--workspace", workspace)["tabs"]

    destinations = sorted((t for t in tabs() if t["tab_id"] != tab
                           and t["workspace_id"] == workspace), key=lambda t: t["number"])
    choice = choose(["新增 tab"] + [f"Tab {t['number']}: {t['label']}" for t in destinations])
    if choice is None:
        return
    source = cli("pane", "get", pane)["pane"]
    if (source["pane_id"], source["workspace_id"], source["tab_id"]) != (pane, workspace, tab):
        raise RuntimeError("Source pane moved or no longer exists; reopen the menu.")
    live = tabs()
    if not any(t["tab_id"] == tab and t["workspace_id"] == workspace for t in live):
        raise RuntimeError("Source tab no longer exists; reopen the menu.")
    if int(choice) == 1:
        cli("pane", "move", pane, "--new-tab", "--focus")
    else:
        target = destinations[int(choice) - 2]["tab_id"]
        if not any(t["tab_id"] == target and t["workspace_id"] == workspace for t in live):
            raise RuntimeError("Destination tab no longer exists; reopen the menu.")
        cli("pane", "move", pane, "--tab", target, "--split", "right", "--focus")


if __name__ == "__main__":
    with terminal():
        try:
            main()
        except (Exception, KeyboardInterrupt) as error:
            print("\033[H\033[2J" + fit(f"移動失敗： {error}", max(1, shutil.get_terminal_size().columns - 1)) + "\r\n按 Esc 或 Enter 關閉。", end="", flush=True)
            try:
                while read_key() not in ("esc", "enter"):
                    pass
            except (EOFError, KeyboardInterrupt):
                pass
            raise SystemExit(1)
