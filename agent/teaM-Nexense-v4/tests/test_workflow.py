import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from nexense.controller import BUILDERS, Controller, ROLES, WorkflowError
from nexense.__main__ import parser

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

    def dispatch_mock(self, role, **kwargs):
        with patch.dict("os.environ", {"HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w1"}):
            with patch("nexense.controller.json_command", side_effect=[
                {"tab": {"tab_id": "w1:t8"}, "root_pane": {"pane_id": "w1:p9"}},
                {"agent": {"name": f"{role}-task-001"}},
            ]), patch("nexense.controller.run", return_value=""):
                return self.c.dispatch("TASK-001", role, **kwargs)

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
        with self.assertRaises(WorkflowError): self.c.submit_plan("TASK-001")
        self.assertIn("Wait for human resolution", self.c.prompt("TASK-001", "pm"))
        self.assertEqual(self.c.resolve("TASK-001")["review_rounds"], 0)
        # Human resolution opens another group, not plan approval.
        self.assertFalse(self.c.load("TASK-001")["approval"]["plan"])
        self.c.submit_plan("TASK-001")
        self.c.review("TASK-001", "revise")
        self.c.submit_plan("TASK-001")
        d = self.c.review("TASK-001", "pass")
        self.assertEqual(d["review_rounds"], 2)
        self.assertEqual(d["state"], "awaiting_plan_approval")
        self.assertEqual(self.c.approve("TASK-001", "plan")["state"], "tickets_draft")

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

    def test_all_modes_require_plan_review_and_approvals(self):
        for mode in ("quick", "standard", "deep"):
            task_id = f"TASK-{mode}"
            with self.subTest(mode=mode):
                self.c.start(task_id, mode)
                folder = self.c.path(task_id)
                (folder / "plan.md").write_text("Small UI text change\n")
                self.c.submit_plan(task_id)
                self.assertEqual(self.c.load(task_id)["state"], "plan_review")
                with self.assertRaises(WorkflowError): self.c.approve(task_id, "plan")
                (folder / "review.md").write_text("QA agrees\n")
                self.c.review(task_id, "pass")
                self.assertEqual(self.c.load(task_id)["review_rounds"], 1)
                self.assertEqual(self.c.approve(task_id, "plan")["state"], "tickets_draft")
                with self.assertRaises(WorkflowError): self.c.create_worktree(task_id)

    def test_pm_ticket_confirmation_prompt(self):
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        self.fill("review.md", "QA agrees\n")
        self.c.review("TASK-001", "pass")
        prompt = self.c.prompt("TASK-001", "pm")
        self.assertIn("roles, headcount, models and effort", prompt)
        self.assertIn("before writing ticket content", prompt)
        self.assertFalse(self.c.substantive("TASK-001", "tickets.md"))
        with self.assertRaises(WorkflowError): self.c.tickets_ready("TASK-001")
        self.c.approve("TASK-001", "plan")
        self.assertIn("Human confirmed plan and staffing", self.c.prompt("TASK-001", "pm"))

    def test_roles_do_not_launch_before_gates(self):
        for role in BUILDERS:
            with self.subTest(role=role):
                with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", role, dry_run=True)
                with self.assertRaises(WorkflowError): self.c.prompt("TASK-001", role)
        self.fill("plan.md")
        self.c.submit_plan("TASK-001")
        self.assertEqual(self.c.dispatch("TASK-001", "qa", dry_run=True)["commands"][0][1:3], ["tab", "create"])
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "pm", dry_run=True)
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "qa2", dry_run=True)

    def test_role_config_and_cli(self):
        roles = self.c.config["roles"]
        self.assertEqual(set(roles), set(ROLES))
        self.assertEqual(roles["pm"]["model"], "gpt-6.1-sol")
        self.assertEqual(roles["qa"]["effort"], "high")
        self.assertEqual(roles["misswu"]["model"], "gpt-6-astra")
        self.assertEqual(roles["slave2"]["model"], "gpt-6-luna")
        self.assertEqual({(x["model"], x["effort"]) for x in roles["pm"]["alternatives"]},
                         {("claude-opus-5-5", "medium"), ("gpt-6-astra", "medium")})
        for role in ROLES:
            with self.subTest(role=role):
                self.assertTrue((self.repo / "roles" / f"{role}.md").is_file())
                self.assertEqual(parser().parse_args(["dispatch", "TASK-001", role, "--dry-run"]).role, role)
                for command in ("send", "read", "prompt"):
                    self.assertEqual(parser().parse_args([command, "TASK-001", role]).role, role)
        self.assertEqual(parser().parse_args(["verify", "TASK-001", "qa2", "pass"]).role, "qa2")
        self.assertTrue(parser().parse_args(["dispatch", "TASK-001", "misswu", "--human-approved"]).human_approved)

    def test_builder_dispatch_previews_and_prompts(self):
        self.approve_tickets()
        self.c.create_worktree("TASK-001")
        for role in BUILDERS:
            with self.subTest(role=role):
                obj = self.c.dispatch("TASK-001", role, dry_run=True)
                self.assertEqual(obj["cwd"], self.c.load("TASK-001")["worktree"])
                self.assertEqual(obj["commands"][1][5], self.c.config["roles"][role]["kind"])
                self.assertNotIn("--", obj["commands"][1])  # Metadata is not a guessed native flag.
                self.assertIn("You may change code only", self.c.prompt("TASK-001", role))
        self.assertEqual(self.c.load("TASK-001")["agents"], {})
        self.dispatch_mock("shifu")
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "pro", dry_run=True)

    def test_support_roles_and_misswu_launch_consent(self):
        for role in ("secretary", "misswu"):
            self.assertEqual(self.c.dispatch("TASK-001", role, dry_run=True)["cwd"], str(self.repo))
            self.assertNotIn("Current instruction: Implement", self.c.prompt("TASK-001", role))
        self.dispatch_mock("secretary")
        with patch("nexense.controller.json_command") as commands:
            with self.assertRaisesRegex(WorkflowError, "explicit human approval"):
                self.c.dispatch("TASK-001", "misswu")
            commands.assert_not_called()
        d = self.dispatch_mock("misswu", human_approved=True)
        self.assertTrue(d["agents"]["misswu"]["started"])
        self.assertEqual(d["state"], "planning")
        self.assertFalse(d["approval"]["plan"])
        self.assertTrue(any(x["event"] == "Human approved this MissWu launch" for x in d["history"]))
        self.assertNotIn("human_approved", d)
        # Approval never carries over to another task/launch.
        self.c.start("TASK-002", "standard")
        with self.assertRaisesRegex(WorkflowError, "explicit human approval"):
            self.c.dispatch("TASK-002", "misswu")

    def test_teamb_requires_qa2_then_pm_and_rechecks_after_failure(self):
        self.approve_tickets()
        self.c.create_worktree("TASK-001")
        self.assertEqual(self.dispatch_mock("pro2")["code_reviewer"], "qa2")
        wt = Path(self.c.load("TASK-001")["worktree"])
        self.fill("implementation.md", "Manual integration test passed\n")
        sha = git("rev-parse", "HEAD", cwd=wt)
        self.c.finish("TASK-001", sha)
        self.assertIn("Review only the pinned commit", self.c.prompt("TASK-001", "qa2"))
        self.c.dispatch("TASK-001", "qa2", dry_run=True)
        with self.assertRaises(WorkflowError): self.c.dispatch("TASK-001", "qa", dry_run=True)
        with self.assertRaises(WorkflowError): self.c.prompt("TASK-001", "qa")
        with self.assertRaises(WorkflowError): self.c.verify("TASK-001", "qa", "pass")
        with self.assertRaises(WorkflowError): self.c.verify("TASK-001", "pm", "pass")
        self.fill("verification.md", "QA2 found regression\n")
        d = self.c.verify("TASK-001", "qa2", "fail")
        self.assertEqual(d["state"], "implementing")
        self.assertIsNone(d["commit"])
        self.assertEqual(d["checks"], {"qa2": None, "pm": None})
        self.c.finish("TASK-001", sha)
        self.fill("verification.md", "QA2 verified pinned commit\n")
        self.c.verify("TASK-001", "qa2", "pass")
        self.assertEqual(self.c.verify("TASK-001", "pm", "pass")["state"], "ready_to_merge")

    def test_slave2_routes_to_qa2(self):
        self.approve_tickets()
        self.c.create_worktree("TASK-001")
        self.assertEqual(self.dispatch_mock("slave2")["code_reviewer"], "qa2")

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
