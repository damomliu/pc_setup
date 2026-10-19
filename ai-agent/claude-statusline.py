#!/usr/bin/env python3
# Claude Code status line：Model · Workspace · 5h · weekly · Context · cost，格式對齊 Codex 的 tui.status_line
import json
import os
import sys

CYAN, GREEN, MAGENTA, YELLOW, RED, DIM, RESET = (f"\033[{c}m" for c in (36, 32, 35, 33, 31, 90, 0))


def paint(text, color):
    return f"{color}{text}{RESET}"


def level_color(base, left):
    # 剩餘 <=10% 紅、<=25% 黃，其餘用 base
    if left <= 10:
        return RED
    if left <= 25:
        return YELLOW
    return base


def pct(v):
    return None if v is None else max(0, min(100, round(v)))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    try:
        d = json.load(sys.stdin)
    except ValueError:
        return
    segs = []

    model = (d.get("model") or {}).get("display_name")
    if model:
        effort = (d.get("effort") or {}).get("level")
        segs.append(paint(f"{model} {effort}" if effort else model, CYAN))

    ws = d.get("workspace") or {}
    path = ws.get("project_dir") or ws.get("current_dir") or d.get("cwd")
    if path:
        name = os.path.basename(path.replace("\\", "/").rstrip("/")) or path
        segs.append(paint(name, GREEN))

    limits = d.get("rate_limits") or {}
    for key, label in (("five_hour", "5h"), ("seven_day", "weekly")):
        used = pct((limits.get(key) or {}).get("used_percentage"))
        if used is not None:
            left = 100 - used
            segs.append(paint(f"{label} {left}% left", level_color(MAGENTA, left)))

    used = pct((d.get("context_window") or {}).get("used_percentage"))
    if used is not None:
        segs.append(paint(f"Context {used}% used", level_color(DIM, 100 - used)))

    cost = (d.get("cost") or {}).get("total_cost_usd")
    if cost:
        segs.append(f"${cost:.1f}")

    print(paint(" · ", DIM).join(segs))


if __name__ == "__main__":
    main()
