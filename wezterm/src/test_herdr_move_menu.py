"""Exercise the real popup loop without a live Herdr session or terminal."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "move_menu", Path(__file__).with_name("herdr-move-pane.py"))
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)


class MenuTests(unittest.TestCase):
    labels = ["新增 workspace"] + [f"Workspace {i}: example" for i in range(2, 7)]

    def render(self, keys, heights=(7,), labels=None, current=None):
        frames = []

        def key(_):
            frames.append(output.getvalue().split("\033[H\033[2J")[-1])
            return next(events)

        events = iter(keys)
        sizes = iter(heights)
        height = heights[0]

        def size(*args):
            nonlocal height
            height = next(sizes, height)
            return os.terminal_size((60, height))

        output = io.StringIO()
        with patch.object(menu.shutil, "get_terminal_size", side_effect=size), \
                patch.object(menu, "read_key", side_effect=key), \
                contextlib.redirect_stdout(output):
            result = menu.choose(labels or self.labels, current)
        return result, frames

    def test_hidden_options_have_hint(self):
        result, frames = self.render(["esc"])
        self.assertIsNone(result)
        self.assertIn("(more)", frames[0])
        self.assertEqual(sum(label in frames[0] for label in self.labels), 2)

    def test_all_options_visible_without_hint(self):
        _, frames = self.render(["q"], (14,))
        self.assertNotIn("(more)", frames[0])
        self.assertTrue(all(label in frames[0] for label in self.labels))

    def test_scroll_and_numeric_jump_keep_selection_visible(self):
        result, frames = self.render(["down", "6", "enter"])
        self.assertEqual(result, 6)
        self.assertIn("\033[7m2. Workspace 2", frames[1])
        self.assertIn("\033[7m6. Workspace 6", frames[2])
        self.assertTrue(all("(more)" in frame for frame in frames))

    def test_resize_recalculates_hint(self):
        # Each frame reads size once for layout and once for the header.
        _, frames = self.render(["resize", "esc"], (7, 7, 14, 14))
        self.assertIn("(more)", frames[0])
        self.assertNotIn("(more)", frames[1])

    def test_workspace_order_and_current_row(self):
        workspaces = [
            dict(workspace_id=workspace_id, number=number, label=label, worktree=worktree)
            for number, (workspace_id, label, worktree) in enumerate([
                ("w9", "mtw4control", {"repo_key": "repo", "is_linked_worktree": False}),
                ("wA", "pc_setup", None),
                ("wD", "webaccess", None),
                ("wE", "LOKI 03 local-capture", {"repo_key": "repo", "is_linked_worktree": True}),
                ("wF", "ARES 04 connect-timing", {"repo_key": "repo", "is_linked_worktree": True}),
            ], 1)
        ]
        rows = menu.workspace_rows(workspaces, "wA")
        self.assertEqual([workspace_id for workspace_id, _ in rows], ["w9", "wE", "wF", "wA", "wD"])
        result, frames = self.render(["enter", "4", "2"], (14,), [label for _, label in rows], 3)
        self.assertEqual(result, 2)
        frame = frames[0].replace("\033[7m", "").replace("\033[0m", "")
        self.assertIn("1. mtw4control\r\n2. > LOKI 03 local-capture\r\n"
                      "3. > ARES 04 connect-timing\r\n4. (current)\r\n5. webaccess\r\n\r\n"
                      "↑↓ 選擇 / 數字或 Enter 確認 / Esc 或 Q 取消", frame)

    def test_workspace_numbers_and_scrolling(self):
        labels = [f"Example {number}" for number in range(1, 11)]
        for keys, expected in [(["1", "0"], 10), (["1", "enter"], 1), (["down", "enter"], 10),
                               (["1", "Q"], None)]:
            with self.subTest(keys=keys):
                result, frames = self.render(keys, labels=labels, current=8)
                self.assertEqual(result, expected)
                self.assertIn("(more)", frames[0])

    def test_workspace_move_resolves_active_tab_after_choice(self):
        commands = {
            ("workspace", "list"): {"workspaces": [
                {"workspace_id": "wA", "number": 1, "label": "Source"},
                {"workspace_id": "wB", "number": 2, "label": "Destination", "active_tab_id": "wB:t1"},
            ]},
            ("pane", "get", "wA:p1"): {"pane": {"pane_id": "wA:p1", "workspace_id": "wA", "tab_id": "wA:t1"}},
            ("tab", "list", "--workspace", "wA"): {"tabs": [{"tab_id": "wA:t1", "workspace_id": "wA"}]},
            ("workspace", "get", "wB"): {"workspace": {"active_tab_id": "wB:t2"}},
            ("tab", "get", "wB:t2"): {"tab": {"workspace_id": "wB"}},
            ("pane", "move", "wA:p1", "--tab", "wB:t2", "--split", "right", "--focus"): {"move_result": {"changed": True}},
        }
        env = dict(HERDR_BIN_PATH="herdr", HERDR_ACTIVE_PANE_ID="wA:p1",
                   HERDR_ACTIVE_WORKSPACE_ID="wA", HERDR_ACTIVE_TAB_ID="wA:t1")

        def cli(args, **kwargs):
            return menu.subprocess.CompletedProcess(args, 0, json.dumps({"result": commands[tuple(args[1:])]}))

        with patch.dict(os.environ, env), patch.object(menu.sys, "argv", ["menu", "workspace"]), \
                patch.object(menu, "choose", return_value=2) as choose, \
                patch.object(menu.subprocess, "run", side_effect=cli) as run:
            menu.main()
        choose.assert_called_once_with(["(current)", "Destination"], 0)
        self.assertEqual([tuple(call.args[0][1:]) for call in run.call_args_list], list(commands))


if __name__ == "__main__":
    unittest.main()
