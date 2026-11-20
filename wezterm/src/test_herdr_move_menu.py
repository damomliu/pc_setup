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

    def render(self, keys, heights=(7,), labels=None, current=0, *, new_tab=False):
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
            result = menu.choose(labels or self.labels, current, new_tab=new_tab)
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
        result, frames = self.render(["down", "6"])
        self.assertEqual(result, 6)
        self.assertIn("\033[7m2. Workspace 2", frames[1])
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

    def test_tab_menu_layout_and_keys(self):
        labels = ["(current)", menu.tab_label("2 · ◉ ctsp-d ACD 進版")]
        for keys, expected in [(["up", "enter", "1", "2"], 2), (["enter"], 2),
                               (["down", "enter"], 3), (["N"], 3), (["n"], 3), (["Q"], None)]:
            with self.subTest(keys=keys):
                result, frames = self.render(keys, (14,), labels, new_tab=True)
                self.assertEqual(result, expected)
                frame = frames[0].replace("\033[7m", "").replace("\033[0m", "")
                self.assertIn("1. (current)\r\n2. ctsp-d ACD 進版\r\nN. 新增 tab\r\n\r\n"
                              "↑↓ 選擇 / 數字, N, Enter 確認 / Esc 或 Q 取消", frame)
                self.assertNotIn("(more)", frame)
                self.assertIn("\033[7m2. ctsp-d ACD 進版", frames[0])
        self.assertEqual(menu.tab_label("Release 2 · notes"), "Release 2 · notes")
        self.assertEqual(menu.tab_label("2 · dashboard"), "dashboard")

    def test_last_tab_defaults_to_new_tab(self):
        for labels in [["(current)"], ["Earlier tab", "(current)"]]:
            with self.subTest(labels=labels):
                result, frames = self.render(["enter"], (14,), labels, len(labels) - 1, new_tab=True)
                self.assertEqual(result, len(labels) + 1)
                self.assertIn("\033[7mN. 新增 tab", frames[0])

    def test_tab_menu_keeps_new_tab_visible_during_resize_and_scroll(self):
        labels = ["(current)"] + [f"Example {number}" for number in range(2, 11)]
        result, frames = self.render(["resize", "1", "0"], (16, 16, 6, 6), labels, new_tab=True)
        self.assertEqual(result, 10)
        self.assertNotIn("(more)", frames[0])
        self.assertIn("(more)", frames[1])
        self.assertTrue(all("N. 新增 tab" in frame for frame in frames))

    def test_tab_move_uses_tab_ids_and_new_tab_command(self):
        source = {"pane_id": "w1W:p1", "workspace_id": "w1W", "tab_id": "w1W:t1"}
        tabs = [dict(workspace_id="w1W", tab_id="w1W:t3", number=3, label="2 · ◉ ctsp-d ACD 進版"),
                dict(workspace_id="w1W", tab_id="w1W:t1", number=1, label="Source")]
        env = dict(HERDR_BIN_PATH="herdr", HERDR_ACTIVE_PANE_ID=source["pane_id"],
                   HERDR_ACTIVE_WORKSPACE_ID=source["workspace_id"], HERDR_ACTIVE_TAB_ID=source["tab_id"])
        for choice, destination in [(2, ["--tab", "w1W:t3", "--split", "right"]),
                                    (3, ["--new-tab", "--workspace", "w1W"])]:
            with self.subTest(choice=choice):
                replies = [{"tabs": tabs}, {"pane": source}, {"tabs": tabs}, {"move_result": {"changed": True}}]
                responses = [menu.subprocess.CompletedProcess([], 0, json.dumps({"result": reply}))
                             for reply in replies]
                with patch.dict(os.environ, env), patch.object(menu.sys, "argv", ["menu"]), \
                        patch.object(menu, "choose", return_value=choice) as choose, \
                        patch.object(menu.subprocess, "run", side_effect=responses) as run:
                    menu.main()
                choose.assert_called_once_with(["(current)", "ctsp-d ACD 進版"], 0, new_tab=True)
                self.assertEqual(run.call_args.args[0],
                                 ["herdr", "pane", "move", "w1W:p1", *destination, "--focus"])

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
