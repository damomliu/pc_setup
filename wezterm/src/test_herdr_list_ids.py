"""Check overview navigation, rendering, and platform clipboard payloads."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "pane_ids", Path(__file__).with_name("herdr-list-ids.py"))
pane_ids = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pane_ids)


class ClipboardTests(unittest.TestCase):
    def test_wsl_sends_unambiguous_unicode_without_newline(self):
        for pane_id in ("w1:p1", "w1B:p1", "w12345:pABC", "w9:t1"):
            with self.subTest(pane_id=pane_id), \
                    patch.object(pane_ids.sys, "platform", "linux"), \
                    patch.object(pane_ids.shutil, "which", return_value="/windows/clip.exe"), \
                    patch.object(pane_ids.subprocess, "run") as run:
                self.assertTrue(pane_ids.copy_to_clipboard(pane_id))
                payload = run.call_args.kwargs["input"]
                self.assertTrue(payload.startswith(b"\xff\xfe"))
                self.assertEqual(payload[2:].decode("utf-16-le"), pane_id)
                self.assertEqual(run.call_args.args[0], ["/windows/clip.exe"])
                self.assertTrue(run.call_args.kwargs["check"])

    def test_wsl_uses_absolute_fallback_when_interop_path_is_missing(self):
        with patch.object(pane_ids.sys, "platform", "linux"), \
                patch.object(pane_ids.shutil, "which", return_value=None), \
                patch.object(pane_ids.subprocess, "run") as run:
            self.assertTrue(pane_ids.copy_to_clipboard("w1B:p1"))
            self.assertEqual(run.call_args.args[0], ["/mnt/c/Windows/System32/clip.exe"])

    def test_macos_sends_utf8_to_pbcopy(self):
        with patch.object(pane_ids.sys, "platform", "darwin"), \
                patch.object(pane_ids.subprocess, "run") as run:
            self.assertTrue(pane_ids.copy_to_clipboard("w1B:p1"))
            self.assertEqual(run.call_args.args[0], ["pbcopy"])
            self.assertEqual(run.call_args.kwargs["input"], b"w1B:p1")

    def test_copy_failures_return_false(self):
        for error in (FileNotFoundError("clip.exe"),
                      subprocess.CalledProcessError(1, ["clip.exe"])):
            with self.subTest(error=type(error).__name__), \
                    patch.object(pane_ids.sys, "platform", "linux"), \
                    patch.object(pane_ids.subprocess, "run", side_effect=error):
                self.assertFalse(pane_ids.copy_to_clipboard("w1B:p1"))


class OverviewTests(unittest.TestCase):
    layout = {
        "tab_id": "w9:t1",
        "area": dict(x=0, y=0, width=120, height=40),
        "panes": [
            dict(pane_id="w9:p4", rect=dict(x=0, y=0, width=60, height=40)),
            dict(pane_id="w9:p1", rect=dict(x=60, y=0, width=60, height=20)),
            dict(pane_id="w9:p6", rect=dict(x=60, y=20, width=60, height=20)),
        ],
    }

    def test_arrow_sequences_and_close(self):
        for payload, expected in (
            (b"\x1b[A", "up"), (b"\x1b[B", "down"), (b"\x1bOC", "right"),
            (b"\x1b[D", "left"), (b"\x1b", "close"), (b"q", "close"),
        ):
            with self.subTest(payload=payload):
                fd, write_fd = os.pipe()
                try:
                    os.write(write_fd, payload)
                    with patch.object(pane_ids.sys.stdin, "fileno", return_value=fd):
                        self.assertEqual(pane_ids.read_key(), expected)
                finally:
                    os.close(write_fd)
                    os.close(fd)

    def test_navigation_copies_only_when_selection_changes(self):
        def herdr(*args):
            if args[1] == "layout":
                return {"layout": self.layout}
            self.assertEqual(args[:5], ("pane", "neighbor", "--pane", "w9:p4", "--direction"))
            result = {"layout": self.layout}
            if args[5] == "right":
                result["neighbor_pane_id"] = "w9:p1"
            return {"neighbor": result}

        env = {"HERDR_BIN_PATH": "herdr", "HERDR_ACTIVE_PANE_ID": "w9:p4"}
        keys = ["left", "up", "right", "down", "right", "resize", "close"]
        sizes = [os.terminal_size((80, 24))] * 10 + [os.terminal_size((28, 12))] * 8
        output = io.StringIO()
        with patch.dict(os.environ, env), patch.object(pane_ids, "herdr", side_effect=herdr) as cli, \
                patch.object(pane_ids, "read_key", side_effect=keys), \
                patch.object(pane_ids.shutil, "get_terminal_size", side_effect=sizes), \
                patch.object(pane_ids, "copy_to_clipboard", side_effect=[True, True, True, False]) as copy, \
                contextlib.redirect_stdout(output):
            pane_ids.main()
        self.assertEqual([call.args[0] for call in copy.call_args_list], ["w9:p4", "w9:t1", "w9:p4", "w9:p1"])
        self.assertEqual(cli.call_count, 4)
        self.assertIn("Tab: w9:t1\033[1;93m(已複製)\033[0m", output.getvalue())
        self.assertIn("w9:p1(複製失敗)", output.getvalue())

    def test_copy_status_falls_back_to_footer_in_narrow_pane(self):
        lines = pane_ids.render_layout(self.layout, 26, 12, "w9:p1", pane_ids.COPIED)
        self.assertEqual(lines[-1], "w9:p1\033[1;93m(已複製)\033[0m")
        self.assertNotIn("\033[", "".join(lines[:-1]))
        self.assertIn("w9:p4", "".join(lines[:-1]))


if __name__ == "__main__":
    unittest.main()
