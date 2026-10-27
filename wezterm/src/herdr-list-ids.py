#!/usr/bin/env python3
"""Popup: show the current tab ID and draw its panes by layout; the active pane is highlighted and its ID copied."""
import json
import math
import os
import re
import select
import shutil
import subprocess
import sys
import termios
import tty
import unicodedata
from contextlib import contextmanager

# Highlight for the active pane: one-dark selection style, bold white on light gray #3e4451; change colours here.
HIGHLIGHT = "\033[1;38;2;255;255;255;48;2;62;68;81m"
FOOTER = "按任意鍵關閉..."


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
    return "key"


def char_width(char):
    return 0 if unicodedata.combining(char) else (2 if unicodedata.east_asian_width(char) in "WF" else 1)


def fit(text, width):
    clean = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(text))
    result, used = "", 0
    for char in clean:
        size = char_width(char)
        if used + size > width:
            break
        result += char
        used += size
    return result


def herdr(*args):
    result = subprocess.run([os.environ["HERDR_BIN_PATH"], *args], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError((result.stdout + result.stderr).strip())
    data = json.loads(result.stdout)
    if data.get("error"):
        raise RuntimeError(json.dumps(data["error"], ensure_ascii=False))
    return data["result"]


def copy_to_clipboard(text):
    # Windows clipboard via clip.exe (WSL interop); /etc/wsl.conf may disable PATH appending.
    try:
        subprocess.run([shutil.which("clip.exe") or "/mnt/c/Windows/System32/clip.exe"], input=text.encode("ascii"), check=True, capture_output=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def render_layout(layout, width, height, active, note=""):
    """Return screen lines: title, blank, (width-1)x(height-4) layout, blank, footer.

    Borders are Unicode box-drawing characters; the whole rectangle of the active
    pane, border included, is wrapped in the HIGHLIGHT colours. Each cell holds one
    string; a wide (CJK) character takes two cells, the second one empty.
    """
    cols, rows = max(1, width - 1), max(1, height - 4)
    area = layout["area"]
    area_w, area_h = max(1, area["width"]), max(1, area["height"])
    chars = [[" "] * cols for _ in range(rows)]
    flags = [[False] * cols for _ in range(rows)]
    for entry in layout["panes"]:
        rect = entry["rect"]
        # Scale both edges with the same formula so neighbouring borders line up.
        x0 = math.floor((rect["x"] - area["x"]) * cols / area_w + 0.5)
        x1 = math.floor((rect["x"] - area["x"] + rect["width"]) * cols / area_w + 0.5)
        y0 = math.floor((rect["y"] - area["y"]) * rows / area_h + 0.5)
        y1 = math.floor((rect["y"] - area["y"] + rect["height"]) * rows / area_h + 0.5)
        x0, x1 = max(0, min(cols - 1, x0)), max(1, min(cols, x1))
        y0, y1 = max(0, min(rows - 1, y0)), max(1, min(rows, y1))
        x1, y1 = max(x1, x0 + 1), max(y1, y0 + 1)
        box_w, box_h = x1 - x0, y1 - y0
        is_active = entry["pane_id"] == active
        for y in range(y0, y1):
            for x in range(x0, x1):
                flags[y][x] = is_active
        if box_w >= 3 and box_h >= 3:
            # Room for an interior: draw the border, ID centred inside.
            for x in range(x0, x1):
                chars[y0][x] = chars[y1 - 1][x] = "─"
            for y in range(y0, y1):
                chars[y][x0] = chars[y][x1 - 1] = "│"
            chars[y0][x0], chars[y0][x1 - 1] = "┌", "┐"
            chars[y1 - 1][x0], chars[y1 - 1][x1 - 1] = "└", "┘"
            avail, label_row, label_x = box_w - 2, y0 + box_h // 2, x0 + 1
        else:
            # Too small for a border: ID only.
            avail, label_row, label_x = box_w, y0 + (box_h - 1) // 2, x0
        text = str(entry["pane_id"])
        if is_active and note:
            text += " " + note
        cells = []
        for char in text:
            size = char_width(char)
            if len(cells) + size > avail:
                break
            cells.append(char)
            if size == 2:
                cells.append("")
        start = label_x + (avail - len(cells)) // 2
        for index, cell in enumerate(cells):
            chars[label_row][start + index] = cell
    lines = ["Tab: " + str(layout["tab_id"]), ""]
    for y in range(rows):
        parts, in_run = [], False
        for x in range(cols):
            if flags[y][x] != in_run:
                parts.append(HIGHLIGHT if flags[y][x] else "\033[0m")
                in_run = flags[y][x]
            parts.append(chars[y][x])
        lines.append("".join(parts))
    lines += ["", fit(FOOTER, cols)]
    return [line + "\033[0m" for line in lines]


def main():
    if not os.environ.get("HERDR_BIN_PATH") or not os.environ.get("HERDR_ACTIVE_PANE_ID"):
        raise RuntimeError("Missing Herdr popup context.")
    pane = os.environ["HERDR_ACTIVE_PANE_ID"]
    layout = herdr("pane", "layout", "--pane", pane)["layout"]
    note = "(已複製)" if copy_to_clipboard(pane) else "(複製失敗)"
    previous = None
    while True:
        width, height = shutil.get_terminal_size((80, 24))
        if (width, height) != previous:
            lines = render_layout(layout, width, height, pane, note)
            print("\033[H\033[2J" + "\r\n".join(lines[:max(1, height)]), end="", flush=True)
            previous = (width, height)
        if read_key(0.15) != "resize":
            return


if __name__ == "__main__":
    with terminal():
        try:
            main()
        except KeyboardInterrupt:
            pass
        except Exception as error:
            print("\033[H\033[2J" + fit(f"讀取失敗： {error}", max(1, shutil.get_terminal_size().columns - 1)) + "\r\n按任意鍵關閉。", end="", flush=True)
            try:
                read_key()
            except (EOFError, KeyboardInterrupt):
                pass
            raise SystemExit(1)
