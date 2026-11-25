#!/usr/bin/env python3
"""Show Claude/Codex quota-cli usage as colored progress bars in a Herdr popup."""
import datetime
import json
import os
import shutil
import subprocess
import sys
import time
import unicodedata

RESET = "\033[0m"
BOLD = "\033[1m"
TITLE = "Agent 用量"
TITLE_STYLE = "\033[1;96m"
GREEN, YELLOW, RED = "#98C379", "#E5C07B", "#E06C75"
DIM = "#5C6370"
AGENTS = (
    # provider, label, label fg, label bg
    ("claude", "Claude", "#FFFFFF", "#D97757"),
    ("codex", "Codex", "#282C34", "#61AFEF"),
)
WINDOWS = ("5h", "Wk")
PARTIAL = " ▏▎▍▌▋▊▉"
EMPTY = "░"
WEEKDAYS = "一二三四五六日"
CLOSE_KEYS = {" ", "\r", "\n", "\x1b", "\x03"}
GAP = 4
TIME_WIDTH = 11  # Widest reset text, e.g. "12/02 09:30"; keeps bars stable across modes.
FIXED_WIDTH = 3 + 5 + 2 + TIME_WIDTH  # "5h " + " 100%" + "  " + time
MIN_BAR, MAX_BAR = 10, 40


def fg(color):
    return "\033[38;2;%d;%d;%dm" % tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def bg(color):
    return "\033[48;2;%d;%d;%dm" % tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def text_width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def pad(text, width, right=False):
    space = " " * max(0, width - text_width(text))
    return space + text if right else text + space


def level_color(remaining):
    return GREEN if remaining >= 50 else YELLOW if remaining >= 20 else RED


def bar(percent, width, color):
    """Render percent (0-100) as width cells with 1/8-cell precision."""
    eighths = round(max(0, min(100, percent)) / 100 * width * 8)
    full, part = divmod(eighths, 8)
    cells = "█" * full + (PARTIAL[part] if part else "")
    return fg(color) + cells + fg(DIM) + EMPTY * (width - text_width(cells)) + RESET


def relative_time(reset_at, now):
    minutes = max(0, int(reset_at - now)) // 60
    days, minutes = divmod(minutes, 1440)
    hours, minutes = divmod(minutes, 60)
    if days:
        return "%dd %dh" % (days, hours)
    if hours:
        return "%dh%02dm" % (hours, minutes)
    return "%dm" % minutes


def absolute_time(reset_at, now):
    reset = datetime.datetime.fromtimestamp(reset_at)
    days = (reset.date() - datetime.datetime.fromtimestamp(now).date()).days
    if days <= 0:
        day = "今天"
    elif days == 1:
        day = "明天"
    elif days < 7:
        day = "週" + WEEKDAYS[reset.weekday()]
    else:
        day = reset.strftime("%m/%d")
    return "%s %s" % (day, reset.strftime("%H:%M"))


def parse_usage(stdout):
    """Map provider -> {window label: window} from `quota-cli usage --json`."""
    usage = {}
    for entry in json.loads(stdout):
        windows = {w.get("label"): w for w in entry.get("windows") or []}
        usage[entry.get("provider")] = {"plan": entry.get("accountLabel") or "", "windows": windows}
    return usage


def quota_cli_path():
    override = os.environ.get("QUOTA_CLI")
    if override:
        return override
    name = "quota-cli.exe" if sys.platform == "win32" else "quota-cli"
    return os.path.join(os.path.expanduser("~"), ".cargo", "bin", name)


def fetch_usage():
    """Return parsed usage, or None when quota-cli fails entirely."""
    try:
        result = subprocess.run([quota_cli_path(), "usage", "--json"], capture_output=True,
                                text=True, encoding="utf-8", timeout=60)
        return parse_usage(result.stdout) if result.stdout.strip() else None
    except (OSError, ValueError, subprocess.SubprocessError, AttributeError, TypeError):
        return None


def state_path():
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(base, "herdr", "usage-view.json")
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "herdr", "usage-view.json")


def load_view(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return {"used": bool(data.get("used")), "absolute": bool(data.get("absolute"))}
    except (OSError, ValueError, AttributeError):
        return {"used": False, "absolute": False}


def save_view(path, view):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(view, f)
    except OSError:
        pass


def agent_panel(agent, usage, view, bar_width, now):
    """Return the label line and two bar lines for one agent (each panel-width wide)."""
    provider, label, label_fg, label_bg = agent
    data = (usage or {}).get(provider)
    panel_width = FIXED_WIDTH + bar_width
    plan = data["plan"] if data else "N/A"
    head = BOLD + fg(label_fg) + bg(label_bg) + " %s " % label + RESET + " " + fg(DIM) + plan + RESET
    lines = [head + " " * max(0, panel_width - len(label) - 3 - text_width(plan))]
    for name in WINDOWS:
        window = data["windows"].get(name) if data else None
        remaining = window.get("remainingPercent") if window else None
        if not isinstance(remaining, (int, float)):
            lines.append(fg(DIM) + name + " " + EMPTY * bar_width + pad("N/A", 5, True)
                         + " " * (2 + TIME_WIDTH) + RESET)
            continue
        color = level_color(remaining)
        shown = 100 - remaining if view["used"] else remaining
        reset_at = window.get("resetAt")
        when = ""
        if isinstance(reset_at, (int, float)):
            when = (absolute_time if view["absolute"] else relative_time)(reset_at, now)
        lines.append(name + " " + bar(shown, bar_width, color) + fg(color)
                     + pad("%d%%" % round(shown), 5, True) + RESET + "  "
                     + fg(DIM) + pad(when, TIME_WIDTH) + RESET)
    return lines


def footer():
    keys = (("u", "剩餘/已使用"), ("t", "相對/重置時間"), ("r", "重新整理"), ("Space", "關閉"))
    sep = fg(DIM) + " · " + RESET
    return " " + sep.join(BOLD + k + RESET + " " + fg(DIM) + d + RESET for k, d in keys)


def render(usage, view, columns, now, status):
    """Return the popup lines. status is the right-hand title text (update time or loading)."""
    width = max(20, columns - 1)
    mode = ("已使用" if view["used"] else "剩餘") + " · " + ("重置時間" if view["absolute"] else "相對時間")
    right = mode + " · " + status
    gap = max(2, width - 1 - text_width(TITLE) - text_width(right))
    lines = [" " + TITLE_STYLE + TITLE + RESET + " " * gap + fg(DIM) + right + RESET, ""]
    if usage is None and status != "查詢中…":
        lines += [" " + fg(RED) + "quota-cli failed" + RESET, ""]
    elif usage is not None:
        side_bar = min(MAX_BAR, (width - 1 - GAP) // 2 - FIXED_WIDTH)
        panels_bar = side_bar if side_bar >= MIN_BAR else max(MIN_BAR, min(MAX_BAR, width - 1 - FIXED_WIDTH))
        panels = [agent_panel(agent, usage, view, panels_bar, now) for agent in AGENTS]
        if side_bar >= MIN_BAR:
            lines += [" " + left + " " * GAP + right for left, right in zip(*panels)]
        else:
            lines += [" " + line for panel in panels for line in panel]
        lines.append("")
    lines.append(footer())
    return lines


def draw(lines):
    sys.stdout.write("\033[H" + "".join(line + "\033[K\r\n" for line in lines[:-1])
                     + lines[-1] + "\033[K\033[J")
    sys.stdout.flush()


if sys.platform == "win32":
    import msvcrt

    class KeyReader:
        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        def read(self):
            key = msvcrt.getwch()
            if key in ("\x00", "\xe0"):  # Arrow/function keys send a second code.
                msvcrt.getwch()
                return ""
            return key
else:
    import select
    import termios
    import tty

    class KeyReader:
        def __enter__(self):
            self.fd = sys.stdin.fileno()
            self.saved = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
            return self

        def __exit__(self, *exc):
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
            return False

        def read(self):
            key = os.read(self.fd, 1)
            if key == b"\x1b":
                # A lone Esc closes; escape sequences (arrows etc.) arrive within 50ms.
                if not select.select([self.fd], [], [], 0.05)[0]:
                    return "\x1b"
                while select.select([self.fd], [], [], 0.05)[0]:
                    os.read(self.fd, 16)
                return ""
            return key.decode("utf-8", "ignore")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    path = state_path()
    view = load_view(path)
    columns = lambda: shutil.get_terminal_size().columns
    sys.stdout.write("\033[?25l\033[H\033[2J")
    usage = None
    try:
        with KeyReader() as keys:
            key = "r"
            while key not in CLOSE_KEYS:
                if key == "r":
                    draw(render(usage, view, columns(), time.time(), "查詢中…"))
                    usage = fetch_usage()
                    updated = "更新 " + time.strftime("%H:%M")
                elif key in ("u", "t"):
                    view["used" if key == "u" else "absolute"] ^= True
                    save_view(path, view)
                draw(render(usage, view, columns(), time.time(), updated))
                key = keys.read().lower()
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(RESET + "\033[?25h")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
