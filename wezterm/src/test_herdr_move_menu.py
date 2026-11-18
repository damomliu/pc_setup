"""Exercise the real popup loop without a live Herdr session or terminal."""
import contextlib
import importlib.util
import io
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

    def render(self, keys, heights=(7,)):
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
            result = menu.choose(self.labels)
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


if __name__ == "__main__":
    unittest.main()
