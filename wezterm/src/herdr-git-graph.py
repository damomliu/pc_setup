#!/usr/bin/env python3
"""Herdr popup: 以 focused pane 所在的 git repo, 在目前 workspace 新 tab 開 git-graph-tui (ggt) 並 focus 該 tab.

部署至 ~/.config/herdr/herdr-git-graph.py; 需要官方 plugin allient/git-graph-tui/integrations/herdr (提供 graph pane) 與 ggt.
不直接綁 plugin action git-graph-tui.open: 它開的 tab 不會成為 active tab, 因此改由此 helper 開 pane 後明確 focus.
"""
import json
import os
import shutil
import subprocess
import sys
import termios
import tty

TITLE = "Git Graph"


def cli(*args):
    result = subprocess.run([os.environ["HERDR_BIN_PATH"], *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    data = json.loads(result.stdout)
    if "error" in data:
        raise RuntimeError(str(data["error"]))
    return data["result"]


def repo_root(pane):
    cwd = next((p.get("cwd") for p in cli("pane", "list")["panes"] if p["pane_id"] == pane), None)
    if not cwd:
        raise RuntimeError("無法取得目前 pane 的目錄")
    result = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        raise RuntimeError(f"不在 git repo 內: {cwd}")
    return result.stdout.strip()


def main():
    pane = os.environ.get("HERDR_ACTIVE_PANE_ID")
    if not os.environ.get("HERDR_BIN_PATH") or not pane:
        raise RuntimeError("Missing Herdr popup context.")
    args = ["plugin", "pane", "open", "--plugin", "git-graph-tui", "--entrypoint", "graph",
            "--focus", "--env", f"TGG_TARGET_DIR={repo_root(pane)}"]
    if os.environ.get("HERDR_ACTIVE_WORKSPACE_ID"):
        args += ["--workspace", os.environ["HERDR_ACTIVE_WORKSPACE_ID"]]
    opened = cli(*args)["plugin_pane"]["pane"]
    cli("tab", "focus", opened["tab_id"])


def show_error(error):
    width = max(1, shutil.get_terminal_size().columns - 1)
    print(f"\033[H\033[2J\033[1;96m{TITLE}\033[0m\r\n\r\n" + f"失敗： {error}"[:width] + "\r\n按 Esc 或 Enter 關閉。", end="", flush=True)
    fd = sys.stdin.fileno()
    while os.read(fd, 1) not in (b"\x1b", b"\r", b"\n", b""):
        pass


if __name__ == "__main__":
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        print("\033[?1049h\033[?25l", end="", flush=True)
        main()
    except KeyboardInterrupt:
        pass
    except Exception as error:
        show_error(error)
        raise SystemExit(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        print("\033[0m\033[?25h\033[?1049l", end="", flush=True)
