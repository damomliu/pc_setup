import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from nexense.controller import Controller, WorkflowError

BASE = Path(__file__).resolve().parents[1]


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, text=True, capture_output=True, check=True).stdout.strip()


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "demo"
        self.repo.mkdir()
        git("init", cwd=self.repo)
        git("config", "user.name", "Example", cwd=self.repo)
        git("config", "user.email", "example@example.test", cwd=self.repo)
        shutil.copytree(BASE / ".nexense", self.repo / ".nexense", ignore=shutil.ignore_patterns("tasks"))
        shutil.copytree(BASE / "roles", self.repo / "roles")
        (self.repo / "README.md").write_text("example\n")
        git("add", ".", cwd=self.repo)
        git("commit", "-m", "initial", cwd=self.repo)
        self.c = Controller(self.repo)
        self.c.start("TASK-001", "standard")
        self.folder = self.repo / ".nexense" / "tasks" / "TASK-001"

    def fill(self, name, text="Acceptance: service returns 200\n"):
        (self.folder / name).write_text(text)

    def approve_tickets(self):
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        self.fill("review.md", "QA checked acceptance\n")
        self.c.review("TASK-001", "pass")
        self.c.approve("TASK-001", "plan")
        self.fill("tickets.md", "TICKET-1: add health endpoint\n")
        self.c.tickets_ready("TASK-001")
        self.c.approve("TASK-001", "tickets")

    def test_plan_requires_content(self):
        with self.assertRaises(WorkflowError): self.c.submit_plan("TASK-001")

    def test_review_limit_blocks_second_revision(self):
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        self.fill("review.md", "Blocking risk\n")
        self.c.review("TASK-001", "revise")
        self.c.submit_plan("TASK-001")
        d = self.c.review("TASK-001", "revise")
        self.assertEqual(d["state"], "blocked")
        with self.assertRaises(WorkflowError): self.c.approve("TASK-001", "plan")
        self.assertEqual(self.c.resolve("TASK-001")["review_rounds"], 0)

    def test_approval_gate(self):
        with self.assertRaises(WorkflowError): self.c.create_worktree("TASK-001")
        self.approve_tickets()
        self.assertEqual(self.c.load("TASK-001")["state"], "tickets_approved")

    def test_worktree_finish_review(self):
        self.approve_tickets()
        d = self.c.create_worktree("TASK-001")
        wt = Path(d["worktree"])
        self.assertTrue(wt.exists())
        # Test the dispatch gate without running Herdr.
        obj = self.c.dispatch("TASK-001", "implementer", dry_run=True)
        self.assertEqual(obj["commands"][1][3], "implementer-task-001")
        self.assertEqual(self.c.load("TASK-001")["state"], "tickets_approved")
        # Simulate successful start for the rest of the sample workflow.
        d["state"] = "implementing"
        self.c.save(d)
        (wt / "feature.py").write_text("def health(): return 200\n")
        git("add", "feature.py", cwd=wt)
        git("commit", "-m", "health", cwd=wt)
        self.fill("implementation.md", "python -m unittest: 8 passed\n")
        sha = git("rev-parse", "HEAD", cwd=wt)
        self.c.finish("TASK-001", sha)
        with self.assertRaises(WorkflowError): self.c.verify("TASK-001", "pm", "pass")
        self.fill("verification.md", "QA verified changed method and tests\n")
        self.c.verify("TASK-001", "qa", "pass")
        self.c.verify("TASK-001", "pm", "pass")
        self.assertEqual(self.c.load("TASK-001")["state"], "ready_to_merge")

    def test_quick_skips_plan_review_not_approvals(self):
        self.c.start("TASK-002", "quick")
        p = self.repo / ".nexense/tasks/TASK-002/plan.md"
        p.write_text("Small UI text change\n")
        self.c.submit_plan("TASK-002")
        self.assertEqual(self.c.load("TASK-002")["state"], "awaiting_plan_approval")
        self.c.approve("TASK-002", "plan")
        self.assertEqual(self.c.load("TASK-002")["state"], "tickets_draft")

    def test_roles_do_not_launch_before_gates(self):
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "implementer", dry_run=True)
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        self.assertEqual(self.c.dispatch("TASK-001", "qa", dry_run=True)["commands"][0][1:3], ["tab", "create"])
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "pm", dry_run=True)

    def test_bad_task_id(self):
        with self.assertRaises(WorkflowError): self.c.start("../escape", "standard")

    def test_dispatch_herdr_json_mock(self):
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        from nexense import controller
        with patch.dict("os.environ", {"HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w1"}):
            with patch.object(controller, "json_command", side_effect=[
                {"tab": {"tab_id": "w1:t8"}, "root_pane": {"pane_id": "w1:p9"}},
                {"agent": {"name": "qa-task-001"}},
            ]) as commands, patch.object(controller, "run", return_value=""):
                d = self.c.dispatch("TASK-001", "qa")
                self.assertEqual(d["agents"]["qa"]["pane"], "w1:p9")
                self.assertTrue(d["agents"]["qa"]["started"])
                self.assertEqual(commands.call_count, 2)
                self.assertEqual(commands.call_args_list[1].args[:5],
                                 ("herdr", "agent", "start", "qa-task-001", "--kind"))
        self.assertEqual(self.c.load("TASK-001")["state"], "plan_review")
        with self.assertRaises(WorkflowError):
            self.c.dispatch("TASK-001", "qa", dry_run=True)

    def test_dispatch_requires_herdr_environment(self):
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        with patch.dict("os.environ", {"HERDR_ENV": "", "HERDR_WORKSPACE_ID": ""}):
            with self.assertRaises(WorkflowError):
                self.c.dispatch("TASK-001", "qa")

    def test_fail_verification_returns_to_implementation(self):
        self.approve_tickets()
        d = self.c.create_worktree("TASK-001")
        d["state"] = "implementing"
        self.c.save(d)
        wt = Path(d["worktree"])
        self.fill("implementation.md", "Manual integration test passed\n")
        self.c.finish("TASK-001", git("rev-parse", "HEAD", cwd=wt))
        self.fill("verification.md", "QA found regression in edge case\n")
        rejected = self.c.verify("TASK-001", "qa", "fail")
        self.assertEqual(rejected["state"], "implementing")
        self.assertIsNone(rejected["commit"])

if __name__ == "__main__":
    unittest.main()
