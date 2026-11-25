"""Check usage parsing, bar rendering, time formats, layout, and view state."""
import datetime
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "herdr_usage", Path(__file__).with_name("herdr-usage.py"))
usage_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage_mod)

ANSI = re.compile(r"\033\[[0-9;?]*[A-Za-z]")
NOW = datetime.datetime(2026, 11, 25, 10, 0).timestamp()  # Wednesday
SAMPLE = json.dumps([
    {"provider": "claude", "accountLabel": "pro", "windows": [
        {"label": "5h", "remainingPercent": 96, "resetAt": NOW + 4 * 3600 + 42 * 60},
        {"label": "Wk", "remainingPercent": 44, "resetAt": NOW + 14 * 3600 + 2 * 60}]},
    {"provider": "codex", "accountLabel": "plus", "windows": [
        {"label": "5h", "remainingPercent": 92, "resetAt": NOW + 4 * 3600 + 4 * 60},
        {"label": "Wk", "remainingPercent": 15, "resetAt": NOW + 5 * 86400}]},
])
DEFAULT_VIEW = {"used": False, "absolute": False}


def plain(text):
    return ANSI.sub("", text)


class BarTests(unittest.TestCase):
    def test_bar_uses_eighth_cells_and_fixed_width(self):
        self.assertEqual(plain(usage_mod.bar(50, 10, usage_mod.GREEN)), "█████░░░░░")
        self.assertEqual(plain(usage_mod.bar(55, 10, usage_mod.GREEN)), "█████▌░░░░")
        self.assertEqual(plain(usage_mod.bar(100, 10, usage_mod.GREEN)), "█" * 10)
        self.assertEqual(plain(usage_mod.bar(0, 10, usage_mod.GREEN)), "░" * 10)
        for percent in range(0, 101, 3):
            self.assertEqual(len(plain(usage_mod.bar(percent, 17, usage_mod.GREEN))), 17)

    def test_level_color_follows_remaining_thresholds(self):
        self.assertEqual(usage_mod.level_color(50), usage_mod.GREEN)
        self.assertEqual(usage_mod.level_color(49), usage_mod.YELLOW)
        self.assertEqual(usage_mod.level_color(20), usage_mod.YELLOW)
        self.assertEqual(usage_mod.level_color(19), usage_mod.RED)


class TimeTests(unittest.TestCase):
    def test_relative_time(self):
        self.assertEqual(usage_mod.relative_time(NOW + 4 * 3600 + 42 * 60, NOW), "4h42m")
        self.assertEqual(usage_mod.relative_time(NOW + 14 * 3600 + 2 * 60, NOW), "14h02m")
        self.assertEqual(usage_mod.relative_time(NOW + 5 * 86400 + 59, NOW), "5d 0h")
        self.assertEqual(usage_mod.relative_time(NOW + 300, NOW), "5m")
        self.assertEqual(usage_mod.relative_time(NOW - 300, NOW), "0m")

    def test_absolute_time_uses_day_words(self):
        at = lambda days, hour: (datetime.datetime(2026, 11, 25, hour, 30)
                                 + datetime.timedelta(days=days)).timestamp()
        self.assertEqual(usage_mod.absolute_time(at(0, 18), NOW), "今天 18:30")
        self.assertEqual(usage_mod.absolute_time(at(1, 4), NOW), "明天 04:30")
        self.assertEqual(usage_mod.absolute_time(at(5, 9), NOW), "週一 09:30")
        self.assertEqual(usage_mod.absolute_time(at(7, 9), NOW), "12/02 09:30")


class RenderTests(unittest.TestCase):
    def setUp(self):
        self.usage = usage_mod.parse_usage(SAMPLE)

    def render(self, columns, view=DEFAULT_VIEW, usage="sample"):
        usage = self.usage if usage == "sample" else usage
        return [plain(line) for line in usage_mod.render(usage, view, columns, NOW, "更新 10:00")]

    def test_wide_popup_places_agents_side_by_side(self):
        lines = self.render(120)
        self.assertIn(" Claude  pro", lines[2])
        self.assertIn(" Codex  plus", lines[2])
        self.assertTrue(lines[3].lstrip().startswith("5h "))
        self.assertIn("96%", lines[3])
        self.assertIn("92%", lines[3])
        self.assertIn("5d 0h", lines[4])
        self.assertTrue(all(usage_mod.text_width(line) <= 119 for line in lines))

    def test_narrow_popup_stacks_agents(self):
        lines = self.render(60)
        self.assertIn("Claude", lines[2])
        self.assertIn("Codex", lines[5])
        self.assertEqual(len(lines), 10)

    def test_used_mode_inverts_percent_and_keeps_remaining_color(self):
        lines = usage_mod.render(self.usage, {"used": True, "absolute": False}, 120, NOW, "x")
        self.assertIn("已使用", plain(lines[0]))
        self.assertIn("85%", plain(lines[4]))
        self.assertIn(usage_mod.fg(usage_mod.RED), lines[4])

    def test_absolute_mode_shows_reset_time(self):
        lines = self.render(120, {"used": False, "absolute": True})
        self.assertIn("重置時間", lines[0])
        self.assertIn("今天 14:42", lines[3])

    def test_missing_provider_shows_na(self):
        usage = usage_mod.parse_usage(json.dumps([json.loads(SAMPLE)[0]]))
        lines = self.render(120, usage=usage)
        self.assertIn("Codex  N/A", lines[2])
        self.assertEqual(lines[3].count("N/A"), 1)

    def test_total_failure_shows_message(self):
        lines = self.render(120, usage=None)
        self.assertIn("quota-cli failed", lines[2])


class FetchTests(unittest.TestCase):
    def test_fetch_parses_stdout_and_ignores_stderr(self):
        done = subprocess.CompletedProcess([], 0, stdout=SAMPLE, stderr="cursor: no credentials")
        with patch.object(usage_mod.subprocess, "run", return_value=done):
            self.assertEqual(usage_mod.fetch_usage()["claude"]["plan"], "pro")

    def test_fetch_failure_returns_none(self):
        with patch.object(usage_mod.subprocess, "run", side_effect=FileNotFoundError):
            self.assertIsNone(usage_mod.fetch_usage())
        bad = subprocess.CompletedProcess([], 1, stdout="not json", stderr="")
        with patch.object(usage_mod.subprocess, "run", return_value=bad):
            self.assertIsNone(usage_mod.fetch_usage())


class ViewStateTests(unittest.TestCase):
    def test_view_round_trip_and_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp, "herdr", "usage-view.json"))
            self.assertEqual(usage_mod.load_view(path), DEFAULT_VIEW)
            usage_mod.save_view(path, {"used": True, "absolute": False})
            self.assertEqual(usage_mod.load_view(path), {"used": True, "absolute": False})
            Path(path).write_text("[]", encoding="utf-8")
            self.assertEqual(usage_mod.load_view(path), DEFAULT_VIEW)


if __name__ == "__main__":
    unittest.main()
