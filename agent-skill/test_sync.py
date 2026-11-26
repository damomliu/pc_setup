"""agent-skill/sync.py 的隔離測試（team、review-pal 兩個 skill）（標準函式庫 unittest）。

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
SKILLS = sync.SKILLS
N = len(FOUR) * len(SKILLS)  # 目標總數


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
        self.src_files = {sk: self.list_files(sync.SOURCE_ROOT / sk) for sk in SKILLS}
        patcher = mock.patch.object(sync.c, "detect_platform", return_value="windows")
        patcher.start()
        self.addCleanup(patcher.stop)

    @staticmethod
    def list_files(root: Path):
        return sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())

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

    def targets(self, skill="team"):
        return {
            "Win-Claude": self.win / ".claude/skills" / skill,
            "Win-Codex": self.win / ".agents/skills" / skill,
            "WSL-Claude": self.wsl / ".claude/skills" / skill,
            "WSL-Codex": self.wsl / ".agents/skills" / skill,
        }

    def snapshot(self):
        return {q: q.read_bytes() for q in self.tmp.rglob("*") if q.is_file()}

    def assert_mirror(self, root: Path, skill="team"):
        got = self.list_files(root)
        self.assertEqual(got, self.src_files[skill])
        for rel in got:
            self.assertEqual((root / rel).read_bytes(), (sync.SOURCE_ROOT / skill / rel).read_bytes())

    # --- check / push ---

    def test_check_empty_targets_reports_added_without_writing(self):
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 1)
        for label in FOUR:
            for sk in SKILLS:
                self.assertIn(f"[{label}/{sk}]", out)
        self.assertIn("+ SKILL.md", out)
        self.assertEqual(list(self.win.iterdir()), [])
        self.assertEqual(list(self.wsl.iterdir()), [])

    def test_push_writes_all_targets_then_check_clean(self):
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        for sk in SKILLS:
            for root in self.targets(sk).values():
                self.assert_mirror(root, sk)
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 0)
        self.assertEqual(out.count("相同"), N)

    def test_check_reports_modified_and_removed_then_push_mirrors(self):
        for sk in SKILLS:
            with self.subTest(skill=sk):
                self.run_sync("--push")
                root = self.targets(sk)["WSL-Codex"]
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
                self.assert_mirror(root, sk)

    def test_type_conflict_dir_where_file_expected(self):
        for sk in SKILLS:
            with self.subTest(skill=sk):
                self.run_sync("--push")
                root = self.targets(sk)["Win-Claude"]
                (root / "SKILL.md").unlink()
                (root / "SKILL.md").mkdir()
                (root / "SKILL.md" / "x").write_text("x")
                rc, _, err = self.run_sync("--push")
                self.assertEqual(rc, 0, err)
                self.assert_mirror(root, sk)

    def test_win_only_skips_wsl(self):
        with mock.patch.object(sync.c, "query_wsl_home", side_effect=AssertionError("called WSL")):
            rc, out, err = self.run_sync("--push", win_only=True)
        self.assertEqual(rc, 0, err)
        self.assertNotIn("WSL", out)
        self.assertEqual(list(self.wsl.iterdir()), [])
        for sk in SKILLS:
            self.assert_mirror(self.targets(sk)["Win-Codex"], sk)

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
        self.assertEqual(out.getvalue().count("[WSL-"), 2 * len(SKILLS))
        self.assertEqual(list(self.win.iterdir()), [])

    def test_check_writes_no_files_including_pycache(self):
        # 在無快取的隔離 repo 複本執行子程序，確認 --check 不寫任何檔（含 __pycache__）
        repo = self.tmp / "repo"
        for sk in SKILLS:
            shutil.copytree(sync.SOURCE_ROOT / sk, repo / "agent-skill" / sk)
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
        src_root = self.tmp / "src"
        for sk in SKILLS:
            shutil.copytree(sync.SOURCE_ROOT / sk, src_root / sk)
        (src_root / "team" / name).write_text("keep")
        with mock.patch.object(sync, "SOURCE_ROOT", src_root):
            self.src_files = {sk: self.list_files(src_root / sk) for sk in SKILLS}
            rc, _, err = self.run_sync("--push")
            self.assertEqual(rc, 0, err)
            root = self.targets()["Win-Claude"]
            (root / "SKILL.md").write_bytes(b"changed")
            rc, _, err = self.run_sync("--push")
            self.assertEqual(rc, 0, err)
            self.assertEqual(self.list_files(root), self.src_files["team"])
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

    def check_hard_link_target(self, skill):
        self.run_sync("--push")
        outside = self.tmp / "outside.md"
        outside.write_bytes(b"external")
        target = self.targets(skill)["Win-Codex"] / "SKILL.md"
        target.unlink()
        os.link(outside, target)
        rc, out, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        self.assertIn("~ SKILL.md", out)
        self.assertEqual(outside.read_bytes(), b"external")
        for sk in SKILLS:
            self.assert_mirror(self.targets(sk)["Win-Codex"], sk)

    def test_hard_link_target_does_not_modify_external_file_team(self):
        self.check_hard_link_target("team")

    def test_hard_link_target_does_not_modify_external_file_review_pal(self):
        self.check_hard_link_target("review-pal")

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

    def check_linked_skill_dir(self, skill):
        outside = self.tmp / "outside"
        (outside / "keep.md").parent.mkdir(parents=True)
        (outside / "keep.md").write_text("keep")
        self.link_dir(self.wsl / ".agents" / "skills" / skill, outside)
        self.assert_refused_without_writes(outside)
        self.assertTrue((outside / "keep.md").exists())

    def test_refuses_linked_team_dir(self):
        self.check_linked_skill_dir("team")

    def test_refuses_linked_review_pal_dir(self):
        self.check_linked_skill_dir("review-pal")

    def check_link_inside_skill(self, skill):
        self.run_sync("--push")
        outside = self.tmp / "outside"
        (outside / "keep.md").parent.mkdir(parents=True)
        (outside / "keep.md").write_text("keep")
        self.link_dir(self.targets(skill)["WSL-Codex"] / "evil", outside)
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("symlink / junction", err)
        self.assertTrue((outside / "keep.md").exists())
        self.assertEqual(sorted(p.name for p in outside.iterdir()), ["keep.md"])

    def test_refuses_link_inside_team(self):
        self.check_link_inside_skill("team")

    def test_refuses_link_inside_review_pal(self):
        self.check_link_inside_skill("review-pal")

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

    # --- 跨 skill：任何預檢失敗，所有 skill 的所有目標都不寫入 ---

    def make_team_dirty(self):
        """先 push 乾淨，再讓 team 有待更新內容，回傳其目標與快照基準。"""
        self.run_sync("--push")
        team = self.targets("team")["Win-Claude"]
        (team / "SKILL.md").write_bytes(b"dirty")
        return team

    def test_missing_second_skill_source_aborts_all(self):
        src_root = self.tmp / "src"
        for sk in SKILLS:
            shutil.copytree(sync.SOURCE_ROOT / sk, src_root / sk)
        team = self.make_team_dirty()
        (src_root / "review-pal" / "SKILL.md").unlink()
        before = self.snapshot()
        with mock.patch.object(sync, "SOURCE_ROOT", src_root):
            rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("找不到來源", err)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((team / "SKILL.md").read_bytes(), b"dirty")

    def test_second_skill_source_scan_error_aborts_all(self):
        team = self.make_team_dirty()
        before = self.snapshot()
        real_walk = os.walk
        bad = sync.SOURCE_ROOT / "review-pal"

        def broken_walk(top, onerror=None, followlinks=False):
            if Path(top) == bad and onerror:
                onerror(PermissionError(13, "denied", str(top)))
                return iter(())
            return real_walk(top, onerror=onerror, followlinks=followlinks)

        with mock.patch.object(sync.os, "walk", side_effect=broken_walk):
            rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("無法掃描", err)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((team / "SKILL.md").read_bytes(), b"dirty")

    def test_second_skill_target_junction_aborts_all(self):
        self.run_sync("--push")
        team = self.targets("team")["Win-Claude"]
        (team / "SKILL.md").write_bytes(b"dirty")
        outside = self.tmp / "outside"
        outside.mkdir()
        (outside / "keep.md").write_text("keep")
        pal = self.targets("review-pal")["WSL-Codex"]
        shutil.rmtree(pal)
        self.link_dir(pal, outside)
        before_outside = sorted(outside.rglob("*"))
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("symlink / junction", err)
        self.assertEqual((team / "SKILL.md").read_bytes(), b"dirty")
        self.assertEqual(sorted(outside.rglob("*")), before_outside)

    def test_second_skill_target_scan_error_aborts_all(self):
        team = self.make_team_dirty()
        pal = self.targets("review-pal")["WSL-Codex"]
        (pal / "extra.md").write_text("x")
        before = self.snapshot()
        real_walk = os.walk

        def broken_walk(top, onerror=None, followlinks=False):
            if Path(top) == pal and onerror:
                onerror(PermissionError(13, "denied", str(top)))
                return iter(())
            return real_walk(top, onerror=onerror, followlinks=followlinks)

        with mock.patch.object(sync.os, "walk", side_effect=broken_walk):
            rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 2)
        self.assertIn("無法掃描", err)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((team / "SKILL.md").read_bytes(), b"dirty")

    def test_push_fixing_review_pal_leaves_team_bytes_unchanged(self):
        self.run_sync("--push")
        pal = self.targets("review-pal")["Win-Codex"]
        (pal / "SKILL.md").write_bytes(b"changed")
        (pal / "extra.md").write_text("x")
        team_before = {q: q.read_bytes() for sk_root in self.targets("team").values()
                       for q in sk_root.rglob("*") if q.is_file()}
        rc, _, err = self.run_sync("--push")
        self.assertEqual(rc, 0, err)
        self.assert_mirror(pal, "review-pal")
        team_after = {q: q.read_bytes() for sk_root in self.targets("team").values()
                      for q in sk_root.rglob("*") if q.is_file()}
        self.assertEqual(team_after, team_before)

    def test_only_review_pal_differs_team_reported_same(self):
        self.run_sync("--push")
        (self.targets("review-pal")["WSL-Claude"] / "SKILL.md").write_bytes(b"changed")
        rc, out, _ = self.run_sync("--check")
        self.assertEqual(rc, 1)
        self.assertEqual(out.count("相同"), N - 1)
        for label in FOUR:
            self.assertIn(f"[{label}/team]", out)
            line = next(l for l in out.splitlines() if l.startswith(f"[{label}/team]"))
            self.assertTrue(line.endswith("相同"), line)
        line = next(l for l in out.splitlines() if l.startswith("[WSL-Claude/review-pal]"))
        self.assertTrue(line.endswith("有差異"), line)


class SkillMetadataTest(unittest.TestCase):
    """解析原始 YAML，確認 manual-only 欄位型別正確。"""

    def setUp(self):
        try:
            import yaml
        except ImportError:
            self.skipTest("需要 PyYAML")
        self.yaml = yaml

    def frontmatter(self, skill):
        text = (sync.SOURCE_ROOT / skill / "SKILL.md").read_text(encoding="utf-8").replace("\r\n", "\n")
        self.assertTrue(text.startswith("---\n"))
        return self.yaml.safe_load(text.split("---\n", 2)[1])

    def test_claude_disable_model_invocation(self):
        for sk in SKILLS:
            with self.subTest(skill=sk):
                fm = self.frontmatter(sk)
                self.assertEqual(fm["name"], sk)
                self.assertIs(fm["disable-model-invocation"], True)
                desc = fm["description"]
                self.assertTrue(0 < len(desc) <= 1024)
                self.assertNotRegex(desc, r"<[^>]+>")

    def test_codex_allow_implicit_invocation_false(self):
        for sk in SKILLS:
            with self.subTest(skill=sk):
                data = self.yaml.safe_load(
                    (sync.SOURCE_ROOT / sk / "agents" / "openai.yaml").read_text(encoding="utf-8"))
                self.assertIs(data["policy"]["allow_implicit_invocation"], False)


class ReviewPalModelsTest(unittest.TestCase):
    """review-pal/models.json 的結構檢查 (SKILL.md 依賴這些欄位)。"""

    def setUp(self):
        import json
        self.data = json.loads((sync.SOURCE_ROOT / "review-pal" / "models.json").read_text(encoding="utf-8"))

    def test_reviewers_fields(self):
        reviewers = self.data["reviewers"]
        self.assertTrue(reviewers)
        for key, r in reviewers.items():
            with self.subTest(key=key):
                self.assertRegex(key, r"^[a-z][a-z0-9_-]{0,31}$")  # 同時是 Herdr alias
                self.assertIn(r["agent"], ("codex", "claude"))
                self.assertIsInstance(r["model"], str)
                self.assertTrue(r["model"])
                self.assertTrue(r["effort"] is None or (isinstance(r["effort"], str) and r["effort"]))

    def test_default_reviewer_covers_both_agents_and_exists(self):
        default = self.data["default_reviewer"]
        self.assertEqual(set(default), {"claude", "codex"})
        for engineer, key in default.items():
            with self.subTest(engineer=engineer):
                self.assertIn(key, self.data["reviewers"])
                # 預設是跨廠牌：Reviewer 的 agent 不同於 Engineer
                self.assertNotEqual(self.data["reviewers"][key]["agent"], engineer)


class TeamModelsTest(unittest.TestCase):
    """team/models.json 的結構檢查，以及與 teams/team-*.md 的一致性 (SKILL.md 依賴這些欄位)。"""

    TEAMS = ("nexense", "claude", "gpt")
    FUNCTIONS = ("Reviewer", "Worker", "Helper", "Grant-Helper")

    def setUp(self):
        import json
        self.root = sync.SOURCE_ROOT / "team"
        self.data = json.loads((self.root / "models.json").read_text(encoding="utf-8"))

    def _check_effort(self, effort):
        self.assertTrue(effort is None or (isinstance(effort, str) and effort))

    def test_team_keys(self):
        self.assertEqual(set(self.data["teams"]), set(self.TEAMS))

    def test_members_fields(self):
        for team, spec in self.data["teams"].items():
            self.assertTrue(spec["members"], team)
            for key, m in spec["members"].items():
                with self.subTest(team=team, key=key):
                    self.assertRegex(key, r"^[a-z][a-z0-9_-]{0,31}$")  # 同時是 Herdr alias 基底
                    self.assertIn(m["function"], self.FUNCTIONS)
                    self.assertIn(m["agent"], ("codex", "claude"))
                    self.assertIsInstance(m["model"], str)
                    self.assertTrue(m["model"])
                    self._check_effort(m["effort"])

    def test_pm_fields(self):
        for team, spec in self.data["teams"].items():
            pm = spec.get("pm", {})
            self.assertLessEqual(set(pm), {"claude", "codex"}, team)
            for agent, options in pm.items():
                with self.subTest(team=team, agent=agent):
                    self.assertTrue(options)
                    for o in options:
                        self.assertIsInstance(o["model"], str)
                        self.assertTrue(o["model"])
                        self._check_effort(o["effort"])

    def test_team_files_match_json(self):
        import re
        for team in self.TEAMS:
            with self.subTest(team=team):
                text = (self.root / "teams" / f"team-{team}.md").read_text(encoding="utf-8")
                self.assertNotRegex(text, r"\b(?:claude|gpt)-[0-9a-z.-]+")  # 模型只寫在 models.json
                in_md = {(n.lower(), f) for n, f in re.findall(r"`(\w+) \(([\w-]+)\)`", text) if f != "PM"}
                in_json = {(k, m["function"]) for k, m in self.data["teams"][team]["members"].items()}
                self.assertEqual(in_md, in_json)

    def test_model_guide_roles_exist(self):
        """model-guide-detail.md 第 4 節表格的角色名須是現行成員或 PM (避免殘留舊角色名)。"""
        import re
        text = (self.root / "references" / "model-guide-detail.md").read_text(encoding="utf-8")
        section = re.search(r"^## 4\..*?(?=^## )", text, re.S | re.M).group(0)
        allowed = {k for t in self.data["teams"].values() for k in t["members"]}
        for team in self.TEAMS:
            md = (self.root / "teams" / f"team-{team}.md").read_text(encoding="utf-8")
            allowed |= {n.lower() for n in re.findall(r"`(\w+) \(PM\)`", md)}
        checked = 0
        for line in section.splitlines():
            if not line.startswith("|"):
                continue
            first = line.split("|")[1].strip()
            if first == "角色" or set(first) <= set("-:") or "非既有角色" in first:
                continue
            for name in first.split(" / "):
                name = re.sub(r"\s*[（(].*$", "", name).strip().lower()
                with self.subTest(name=name):
                    self.assertIn(name, allowed)
                checked += 1
        self.assertGreater(checked, 0)


class SkillContentTest(unittest.TestCase):
    def test_relative_links_exist(self):
        import re
        for sk in SKILLS:
            for md in (sync.SOURCE_ROOT / sk).rglob("*.md"):
                for target in re.findall(r"\]\(([^)#]+)(?:#[^)]*)?\)", md.read_text(encoding="utf-8")):
                    if "://" in target:
                        continue
                    self.assertTrue((md.parent / target).exists(), f"{md}: {target}")

    def test_skill_md_under_500_lines(self):
        for sk in SKILLS:
            with self.subTest(skill=sk):
                lines = (sync.SOURCE_ROOT / sk / "SKILL.md").read_text(encoding="utf-8").splitlines()
                self.assertLess(len(lines), 500)


if __name__ == "__main__":
    unittest.main()
