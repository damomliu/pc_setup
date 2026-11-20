#!/usr/bin/env python3
"""Use arrow keys to copy a tab or pane ID from the Herdr layout."""
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

RESET = "\033[0m"
COPIED = "(已複製)"
COPY_FAILED = "(複製失敗)"
FOOTER = "方向鍵選取並複製 / 其他鍵關閉"
ARROWS = dict(zip(b"ABCD", ("up", "down", "right", "left")))


POPUP_TITLE = "Pane 總覽"


def clear_popup():
    width = max(1, shutil.get_terminal_size().columns - 1)
    return "\033[H\033[2J" + "\033[1;96m" + fit(POPUP_TITLE, width) + "\033[0m\r\n\r\n"


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
        return "close"
    if not select.select([fd], [], [], 0.04)[0] or os.read(fd, 1) not in (b"[", b"O"):
        return "close"
    if not select.select([fd], [], [], 0.04)[0]:
        return "close"
    char = os.read(fd, 1)
    return ARROWS.get(char[0], "close") if char else "close"


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
    # macOS uses pbcopy; WSL uses Windows clip.exe via interop (/etc/wsl.conf may disable PATH appending).
    if sys.platform == "darwin":
        command = ["pbcopy"]
        payload = text.encode("utf-8")
    else:
        command = [shutil.which("clip.exe") or "/mnt/c/Windows/System32/clip.exe"]
        # A BOM makes clip.exe interpret the ID as UTF-16.
        payload = b"\xff\xfe" + text.encode("utf-16-le")
    try:
        subprocess.run(command, input=payload, check=True, capture_output=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def format_note(note):
    return "\033[1;93m" + note + RESET if note == COPIED else note


def render_layout(layout, width, height, selected, note="", message=""):
    """Draw the tab and pane IDs, styling only the selected ID's copy result."""
    cols, rows = max(1, width - 1), max(1, height - 6)
    area = layout["area"]
    area_w, area_h = max(1, area["width"]), max(1, area["height"])
    chars = [[" "] * cols for _ in range(rows)]
    tab_id = layout["tab_id"]
    status_in_footer = False
    tab_label = "Tab: " + tab_id
    tab = fit(tab_label, cols)
    if selected == tab_id:
        if fit(tab_label + note, cols) == tab_label + note:
            tab += format_note(note)
        else:
            status_in_footer = True
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
        pane_id = entry["pane_id"]
        text = fit(pane_id, avail)
        suffix = ""
        if pane_id == selected and note:
            if fit(pane_id + note, avail) == pane_id + note:
                suffix = note
            else:
                status_in_footer = True
        cells = []
        for char in text + suffix:
            cells.append(char)
            if char_width(char) == 2:
                cells.append("")
        if suffix == COPIED:
            start = sum(map(char_width, text))
            cells[start] = "\033[1;93m" + cells[start]
            cells[-1] += RESET
        start = label_x + (avail - len(cells)) // 2
        for index, cell in enumerate(cells):
            chars[label_row][start + index] = cell
    footer = fit(message or FOOTER, cols)
    if status_in_footer and not message:
        footer = fit(selected, cols)
        if fit(selected + note, cols) == selected + note:
            footer += format_note(note)
    return [tab, "", *map("".join, chars), "", footer]


def main():
    if not os.environ.get("HERDR_BIN_PATH") or not os.environ.get("HERDR_ACTIVE_PANE_ID"):
        raise RuntimeError("Missing Herdr popup context.")
    pane = os.environ["HERDR_ACTIVE_PANE_ID"]
    layout = herdr("pane", "layout", "--pane", pane)["layout"]
    tab = layout["tab_id"]
    selected = last_pane = pane
    note = COPIED if copy_to_clipboard(pane) else COPY_FAILED
    message = ""
    previous = None
    while True:
        width, height = shutil.get_terminal_size((80, 24))
        frame = (width, height, selected, note, message)
        if frame != previous:
            lines = render_layout(layout, width, height, selected, note, message)
            print(clear_popup() + "\r\n".join(lines[:max(0, height - 2)]), end="", flush=True)
            previous = frame
        key = read_key(0.15)
        if key == "close":
            return
        if key == "resize":
            continue
        target = selected
        message = ""
        if selected == tab:
            if key == "down":
                target = last_pane
        else:
            try:
                neighbor = herdr("pane", "neighbor", "--pane", selected, "--direction", key)["neighbor"]
                if neighbor["layout"]["tab_id"] != tab:
                    raise RuntimeError("The selected pane moved to another tab.")
            except (OSError, RuntimeError, ValueError, KeyError):
                message = "無法讀取相鄰 pane"
                continue
            layout = neighbor["layout"]
            previous = None
            target = neighbor.get("neighbor_pane_id") or (tab if key == "up" else selected)
        if target != selected:
            if target != tab:
                last_pane = target
            selected = target
            note = COPIED if copy_to_clipboard(selected) else COPY_FAILED


if __name__ == "__main__":
    with terminal():
        try:
            main()
        except KeyboardInterrupt:
            pass
        except Exception as error:
            print(clear_popup() + fit(f"讀取失敗： {error}", max(1, shutil.get_terminal_size().columns - 1)) + "\r\n按任意鍵關閉。", end="", flush=True)
            try:
                read_key()
            except (EOFError, KeyboardInterrupt):
                pass
            raise SystemExit(1)
