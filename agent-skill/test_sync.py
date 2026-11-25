"""agent-skill/sync.py 的隔離測試（標準函式庫 unittest）。

以 --test-win-home / --test-wsl-root 指向暫存目錄，不碰真實 home、不呼叫真實 WSL。
YAML 欄位檢查需要 PyYAML，沒有則 skip。

用法：python agent-skill/test_sync.py
"""
import sys

sys.dont_write_bytecode = True

import contextlib  # noqa: E402
import io  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
from pathlib import Path  # noqa: E402
from unittest import mock  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import sync  # noqa: E402

WIN = sys.platform == "win32"
FOUR = ("Win-Claude", "Win-Codex", "WSL-Claude", "WSL-Codex")


def make_junction(link: Path, target: Path) -> None:
    subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)],
                   check=True, capture_output=True)


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.win = self.tmp / "win"
        self.wsl = self.tmp / "wsl"
        self.win.mkdir()
        self.wsl.mkdir()
        self.src_files = sorted(p.relative_to(sync.SOURCE).as_posix()
                                for p in sync.SOURCE.rglob("*") if p.is_file())
        patcher = mock.patch.object(sync.c, "detect_platform", return_value="windows")
        patcher.start()
        self.addCleanup(patcher.stop)

    def tearDown(self):
        # junction 先移除，避免 rmtree 走進 link 目標
        for dirpath, dirnames, _ in os.walk(self.tmp):
            for d in dirnames:
                p = Path(dirpath) / d
                if sync.is_link(p):
                    os.rmdir(p) if WIN else p.unlink()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_sync(self, *args, win_only=False):
        argv = list(args) + ["--test-win-home", str(self.win)]
        argv += ["--win-only"] if win_only else ["--test-wsl-root", str(self.wsl)]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = sync.main(argv)
        return rc, out.getvalue(), err.getvalue()

    def targets(self):
        return {
            "Win-Claude": self.win / ".claude/skills/team",
            "Win-Codex": self.win / ".agents/skills/team",
            "WSL-Claude": self.wsl / ".claude/skills/team",
            "WSL-Codex": self.wsl / ".agents/skills/team",
        }

    def assert_mirror(self, root: Path):
        got = sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
        self.assertEqual(got, self.src_files)
        for rel in got:
            self.assertEqual((root / rel).read_bytes(), (sync.SOURCE / rel).read_bytes())

    # --- check / push ---

    def test_check_empty_targets_reports_added_without_writing(self):
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 1)
        for label in FOUR:
            self.assertIn(f"[{label}]", out)
        self.assertIn("+ SKILL.md", out)
        self.assertEqual(list(self.win.iterdir()), [])
        self.assertEqual(list(self.wsl.iterdir()), [])

    def test_push_writes_all_four_targets_then_check_clean(self):
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        for root in self.targets().values():
            self.assert_mirror(root)
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 0)
        self.assertEqual(out.count("相同"), 4)

    def test_check_reports_modified_and_removed_then_push_mirrors(self):
        self.run_sync("--push")
        root = self.targets()["WSL-Codex"]
        (root / "SKILL.md").write_bytes(b"changed")
        (root / "extra.md").write_text("x")
        (root / "olddir").mkdir()
        (root / "olddir" / "f.md").write_text("x")
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 1)
        self.assertIn("~ SKILL.md", out)
        self.assertIn("- extra.md", out)
        self.assertIn("- olddir/f.md", out)
        self.assertIn("- olddir/", out)
        self.assertEqual((root / "SKILL.md").read_bytes(), b"changed")  # check 不寫入
        rc, _, _ = self.run_sync("--push")
        self.assertEqual(rc, 0)
        self.assert_mirror(root)

    def test_type_conflict_dir_where_file_expected(self):
        self.run_sync("--push")
        root = self.targets()["Win-Claude"]
        (root / "SKILL.md").unlink()
        (root / "SKILL.md").mkdir()
        (root / "SKILL.md" / "x").write_text("x")
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        self.assert_mirror(root)

    def test_win_only_skips_wsl(self):
        with mock.patch.object(sync.c, "query_wsl_home", side_effect=AssertionError("called WSL")):
            rc, out, err = self.run_sync("--push", win_only=True)
        self.assertEqual(rc, 0, err)
        self.assertNotIn("WSL", out)
        self.assertEqual(list(self.wsl.iterdir()), [])
        self.assert_mirror(self.targets()["Win-Codex"])

    def test_check_and_push_are_exclusive_and_required(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                sync.main(["--check", "--push"])
            with self.assertRaises(SystemExit):
                sync.main([])

    def test_non_windows_rejects_win_only(self):
        with mock.patch.object(sync.c, "detect_platform", return_value="wsl"):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(sync.main(["--check", "--win-only"]), 2)

    def test_wsl_platform_uses_single_home(self):
        with mock.patch.object(sync.c, "detect_platform", return_value="wsl"):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = sync.main(["--push", "--test-wsl-root", str(self.wsl)])
        self.assertEqual(rc, 0)
        self.assertEqual(out.getvalue().count("[WSL-"), 2)
        self.assertEqual(list(self.win.iterdir()), [])

    def test_check_writes_no_files_including_pycache(self):
        # 在無快取的隔離 repo 複本執行子程序，確認 --check 不寫任何檔（含 __pycache__）
        repo = self.tmp / "repo"
        shutil.copytree(sync.SOURCE, repo / "agent-skill" / "team")
        shutil.copy2(HERE / "sync.py", repo / "agent-skill" / "sync.py")
        (repo / "agent" / "src").mkdir(parents=True)
        shutil.copy2(HERE.parent / "agent" / "src" / "sync_common.py", repo / "agent" / "src")
        before = sorted(repo.rglob("*"))
        self.assertFalse([q for q in before if q.name == "__pycache__"])
        args = (["--test-win-home", str(self.win), "--win-only"] if WIN
                else ["--test-wsl-root", str(self.wsl)])
        env = {k: v for k, v in os.environ.items() if k != "PYTHONDONTWRITEBYTECODE"}
        r = subprocess.run([sys.executable, str(repo / "agent-skill" / "sync.py"), "--check", *args],
                           capture_output=True, env=env, cwd=self.tmp)
        self.assertEqual(r.returncode, 1, r.stderr.decode("utf-8", "replace"))
        self.assertEqual(sorted(repo.rglob("*")), before)
        self.assertEqual(list(self.win.iterdir()), [])
        self.assertEqual(list(self.wsl.iterdir()), [])

    def test_half_test_override_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(sync.main(["--push", "--test-win-home", str(self.win)]), 2)
            self.assertEqual(sync.main(["--push", "--test-wsl-root", str(self.wsl)]), 2)
            self.assertEqual(sync.main(["--push", "--win-only", "--test-win-home", str(self.win),
                                        "--test-wsl-root", str(self.wsl)]), 2)
        self.assertEqual(list(self.win.iterdir()), [])
        self.assertEqual(list(self.wsl.iterdir()), [])

    def test_blank_test_override_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(sync.main(["--push", "--test-win-home=", "--test-wsl-root", str(self.wsl)]), 2)
            self.assertEqual(sync.main(["--push", "--test-win-home", str(self.win), "--test-wsl-root= "]), 2)
            self.assertEqual(sync.main(["--push", "--win-only", "--test-win-home="]), 2)
        self.assertEqual(list(self.win.iterdir()), [])
        self.assertEqual(list(self.wsl.iterdir()), [])

    def test_source_file_named_like_temp_is_mirrored(self):
        # 暫存檔名唯一，不會與受管檔案同名而覆寫或移走
        name = ".SKILL.md.sync-tmp"
        (self.tmp / "src").mkdir()
        src = self.tmp / "src" / "team"
        shutil.copytree(sync.SOURCE, src)
        (src / name).write_text("keep")
        with mock.patch.object(sync, "SOURCE", src):
            self.src_files = sorted(q.relative_to(src).as_posix() for q in src.rglob("*") if q.is_file())
            rc, _, err = self.run_sync("--push")
            self.assertEqual(rc, 0, err)
            root = self.targets()["Win-Claude"]
            (root / "SKILL.md").write_bytes(b"changed")
            rc, _, err = self.run_sync("--push")
            self.assertEqual(rc, 0, err)
            got = sorted(q.relative_to(root).as_posix() for q in root.rglob("*") if q.is_file())
            self.assertEqual(got, self.src_files)
            self.assertEqual((root / name).read_text(), "keep")

    def test_scan_error_aborts_without_changes(self):
        self.run_sync("--push")
        root = self.targets()["WSL-Codex"]
        (root / "extra.md").write_text("x")
        snapshot = {q: q.read_bytes() for q in self.tmp.rglob("*") if q.is_file()}
        real_walk = os.walk

        def broken_walk(top, onerror=None, followlinks=False):
            if Path(top) == root and onerror:
                onerror(PermissionError(13, "denied", str(top)))
                return iter(())
            return real_walk(top, onerror=onerror, followlinks=followlinks)

        with mock.patch.object(sync.os, "walk", side_effect=broken_walk):
            rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("無法掃描", err)
        self.assertEqual({q: q.read_bytes() for q in self.tmp.rglob("*") if q.is_file()}, snapshot)

    def test_hard_link_target_does_not_modify_external_file(self):
        self.run_sync("--push")
        outside = self.tmp / "outside.md"
        outside.write_bytes(b"external")
        target = self.targets()["Win-Codex"] / "SKILL.md"
        target.unlink()
        os.link(outside, target)
        rc, out, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        self.assertIn("~ SKILL.md", out)
        self.assertEqual(outside.read_bytes(), b"external")
        self.assert_mirror(self.targets()["Win-Codex"])

    # --- link 防護 ---

    def link_dir(self, link: Path, target: Path):
        target.mkdir(parents=True, exist_ok=True)
        link.parent.mkdir(parents=True, exist_ok=True)
        if WIN:
            make_junction(link, target)
        else:
            link.symlink_to(target, target_is_directory=True)

    def assert_refused_without_writes(self, outside: Path):
        before = sorted(outside.rglob("*"))
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("symlink / junction", err)
        self.assertEqual(sorted(outside.rglob("*")), before)
        # 任何寫入前先檢查全部目標：其他目標也沒有被寫入
        self.assertFalse((self.win / ".claude/skills/team/SKILL.md").exists())

    def test_refuses_linked_ancestor(self):
        outside = self.tmp / "outside"
        self.link_dir(self.wsl / ".agents", outside)
        self.assert_refused_without_writes(outside)

    def test_refuses_linked_skills_dir(self):
        outside = self.tmp / "outside"
        self.link_dir(self.wsl / ".claude" / "skills", outside)
        self.assert_refused_without_writes(outside)

    def test_refuses_linked_team_dir(self):
        outside = self.tmp / "outside"
        (outside / "keep.md").parent.mkdir(parents=True)
        (outside / "keep.md").write_text("keep")
        self.link_dir(self.wsl / ".agents" / "skills" / "team", outside)
        self.assert_refused_without_writes(outside)
        self.assertTrue((outside / "keep.md").exists())

    def test_refuses_link_inside_team(self):
        self.run_sync("--push")
        outside = self.tmp / "outside"
        (outside / "keep.md").parent.mkdir(parents=True)
        (outside / "keep.md").write_text("keep")
        self.link_dir(self.targets()["WSL-Codex"] / "evil", outside)
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertTrue((outside / "keep.md").exists())

    def test_inside_rejects_escape(self):
        root = self.tmp / "root"
        root.mkdir()
        root_real = sync.real(root)
        with self.assertRaises(sync.c.SyncError):
            sync.inside(root_real, root / ".." / "x")
        with self.assertRaises(sync.c.SyncError):
            sync.inside(root_real, root)
        outside = self.tmp / "outside"
        self.link_dir(root / "evil", outside)
        with self.assertRaises(sync.c.SyncError):
            sync.inside(root_real, root / "evil")
        with self.assertRaises(sync.c.SyncError):
            sync.inside(root_real, root / "evil" / "f.md")


class SkillMetadataTest(unittest.TestCase):
    """解析原始 YAML，確認 manual-only 欄位型別正確。"""

    def setUp(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("需要 PyYAML")
        self.yaml = yaml

    def frontmatter(self):
        text = (sync.SOURCE / "SKILL.md").read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertTrue(text.startswith("---\n"))
        return self.yaml.safe_load(text.split("---\n", 2)[1])

    def test_claude_disable_model_invocation(self):
        fm = self.frontmatter()
        self.assertEqual(fm["name"], "team")
        self.assertIs(fm["disable-model-invocation"], True)
        desc = fm["description"]
        self.assertTrue(0 < len(desc) <= 1024)
        self.assertNotRegex(desc, r"<[^>]+>")

    def test_codex_allow_implicit_invocation_false(self):
        data = self.yaml.safe_load((sync.SOURCE / "agents" / "openai.yaml").read_text(encoding="utf-8"))
        self.assertIs(data["policy"]["allow_implicit_invocation"], False)


class SkillContentTest(unittest.TestCase):
    def test_relative_links_exist(self):
        import re
        for md in sync.SOURCE.rglob("*.md"):
            for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", md.read_text(encoding="utf-8")):
                if "://" in target:
                    continue
                self.assertTrue((md.parent / target).exists(), f"{md}: {target}")

    def test_skill_md_under_500_lines(self):
        lines = (sync.SOURCE / "SKILL.md").read_text(encoding="utf-8").splitlines()
        self.assertLess(len(lines), 500)


if __name__ == "__main__":
    unittest.main()
