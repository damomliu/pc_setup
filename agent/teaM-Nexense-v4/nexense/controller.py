"""Deterministic task workflow backed by JSON, Herdr CLI and Git.

This is a single-operator example, not a concurrency-safe scheduler.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


class WorkflowError(Exception):
    pass


ID_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{1,39}$")
MODES = {"quick", "standard", "deep"}
MAX_REVIEW_ROUNDS = 2


def run(*args: str, cwd: Path | None = None, timeout: int = 90) -> str:
    try:
        result = subprocess.run(
            list(args), cwd=cwd, capture_output=True, text=True, encoding="utf-8", timeout=timeout,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        raise WorkflowError(f"Command failed: {args[0]}: {exc}") from exc
    if result.returncode:
        raise WorkflowError(f"Command failed ({result.returncode}): {' '.join(args[:3])}\n{result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def json_command(*args: str, timeout: int = 90) -> dict[str, Any]:
    stdout = run(*args, timeout=timeout)
    try:
        data = json.loads(stdout)
        if not isinstance(data, dict) or "result" not in data:
            raise ValueError("missing result")
        return data["result"]
    except (ValueError, TypeError) as exc:
        raise WorkflowError(f"Unexpected JSON from {' '.join(args[:2])}: {stdout[:400]}") from exc


def atomic_write(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as f:
        temp = Path(f.name)
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(temp, path)


class Controller:
    def __init__(self, repo: Path):
        self.repo = repo.resolve()
        if not (self.repo / ".git").exists():
            raise WorkflowError(f"Run in the Git repository root: {self.repo}")
        self.base = self.repo / ".nexense"
        self.config = json.loads((self.base / "team.json").read_text(encoding="utf-8"))

    def path(self, task_id: str) -> Path:
        if not ID_PATTERN.fullmatch(task_id):
            raise WorkflowError("Task ID must match [A-Za-z][A-Za-z0-9_-]{1,39}")
        return self.base / "tasks" / task_id

    def load(self, task_id: str) -> dict[str, Any]:
        path = self.path(task_id) / "state.json"
        if not path.exists():
            raise WorkflowError(f"Unknown task {task_id}; run 'start' first")
        return json.loads(path.read_text(encoding="utf-8"))

    def save(self, data: dict[str, Any]) -> None:
        data["updated_at"] = datetime.now(timezone.utc).isoformat()
        atomic_write(self.path(data["id"]) / "state.json", data)

    def require(self, data: dict[str, Any], *states: str) -> None:
        if data["state"] not in states:
            raise WorkflowError(f"Invalid state '{data['state']}'. Expected: {', '.join(states)}")

    def start(self, task_id: str, mode: str) -> dict[str, Any]:
        if mode not in MODES:
            raise WorkflowError(f"Mode must be one of: {', '.join(sorted(MODES))}")
        directory = self.path(task_id)
        if (directory / "state.json").exists():
            raise WorkflowError("Task already exists; will not overwrite")
        directory.mkdir(parents=True, exist_ok=True)
        for fname, title in [
            ("requirements.md", "Requirements"), ("plan.md", "Plan"),
            ("review.md", "Review"), ("tickets.md", "Tickets"),
            ("implementation.md", "Implementation"), ("verification.md", "Verification"),
        ]:
            f = directory / fname
            if not f.exists():
                f.write_text(f"# {title}: {task_id}\n\n<!-- Fill in before advancing. -->\n", encoding="utf-8")
        data = {
            "id": task_id, "mode": mode, "state": "planning", "review_rounds": 0,
            "max_review_rounds": MAX_REVIEW_ROUNDS, "approval": {"plan": False, "tickets": False},
            "agents": {}, "worktree": None, "branch": None, "commit": None,
            "checks": {"qa": None, "pm": None}, "history": [],
        }
        self.event(data, "Task created")
        self.save(data)
        return data

    @staticmethod
    def event(data: dict[str, Any], description: str) -> None:
        data["history"].append({"at": datetime.now(timezone.utc).isoformat(), "event": description})

    def substantive(self, task_id: str, file: str) -> bool:
        text = (self.path(task_id) / file).read_text(encoding="utf-8")
        lines = [x.strip() for x in text.splitlines() if x.strip() and not x.startswith("#") and not x.startswith("<!--")]
        return bool(lines)

    def submit_plan(self, task_id: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "planning")
        if not self.substantive(task_id, "plan.md"):
            raise WorkflowError("Fill in plan.md before submitting")
        d["state"] = "plan_review" if d["mode"] != "quick" else "awaiting_plan_approval"
        self.event(d, "Plan submitted")
        self.save(d)
        return d

    def review(self, task_id: str, outcome: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "plan_review")
        if outcome not in ("pass", "revise"):
            raise WorkflowError("Review outcome: pass or revise")
        if not self.substantive(task_id, "review.md"):
            raise WorkflowError("Fill in review.md with QA findings first")
        d["review_rounds"] += 1
        if outcome == "pass":
            d["state"] = "awaiting_plan_approval"
        elif d["review_rounds"] >= MAX_REVIEW_ROUNDS:
            d["state"] = "blocked"
        else:
            d["state"] = "planning"
        self.event(d, f"Plan review #{d['review_rounds']}: {outcome}")
        self.save(d)
        return d

    def resolve(self, task_id: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "blocked")
        d["state"] = "planning"
        d["review_rounds"] = 0
        self.event(d, "Human resolved disagreement; restarted plan-review budget")
        self.save(d)
        return d

    def approve(self, task_id: str, stage: str) -> dict[str, Any]:
        d = self.load(task_id)
        if stage == "plan":
            self.require(d, "awaiting_plan_approval")
            d["approval"]["plan"] = True
            d["state"] = "tickets_draft"
        elif stage == "tickets":
            self.require(d, "awaiting_tickets_approval")
            d["approval"]["tickets"] = True
            d["state"] = "tickets_approved"
        else:
            raise WorkflowError("Stage must be plan or tickets")
        self.event(d, f"Human approved {stage}")
        self.save(d)
        return d

    def tickets_ready(self, task_id: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "tickets_draft")
        if not self.substantive(task_id, "tickets.md"):
            raise WorkflowError("Fill in tickets.md before approval")
        d["state"] = "awaiting_tickets_approval"
        self.event(d, "Tickets proposed for human approval")
        self.save(d)
        return d

    def create_worktree(self, task_id: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "tickets_approved")
        if d["worktree"]:
            raise WorkflowError("Worktree already exists in task state")
        # Never infer main/master. HEAD is the approved starting point in this MVP.
        branch = f"agent/{task_id.lower()}"
        location = self.repo.parent / f"{self.repo.name}-wt-{task_id.lower()}"
        if location.exists():
            raise WorkflowError(f"Worktree directory exists: {location}")
        run("git", "worktree", "add", "-b", branch, str(location), "HEAD", cwd=self.repo)
        d["worktree"] = str(location)
        d["branch"] = branch
        self.event(d, f"Created worktree: {location}")
        self.save(d)
        return d

    def finish(self, task_id: str, commit: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "implementing")
        if not d["worktree"]:
            raise WorkflowError("No worktree")
        wt = Path(d["worktree"])
        head = run("git", "rev-parse", "HEAD", cwd=wt)
        full = run("git", "rev-parse", "--verify", f"{commit}^{{commit}}", cwd=wt)
        if full != head:
            raise WorkflowError("Commit must equal the worktree HEAD")
        if run("git", "status", "--porcelain", cwd=wt):
            raise WorkflowError("Worktree is dirty; commit or clean changes before handoff")
        if not self.substantive(task_id, "implementation.md"):
            raise WorkflowError("Write an implementation report before finishing")
        d["commit"] = full
        d["checks"] = {"qa": None, "pm": None}
        d["state"] = "verifying"
        self.event(d, f"Implementation submitted: {full}")
        self.save(d)
        return d

    def verify(self, task_id: str, role: str, outcome: str) -> dict[str, Any]:
        d = self.load(task_id)
        self.require(d, "verifying")
        if role not in ("qa", "pm") or outcome not in ("pass", "fail"):
            raise WorkflowError("Usage: verify <task> qa|pm pass|fail")
        if role == "pm" and d["checks"]["qa"] != "pass":
            raise WorkflowError("QA must pass before PM acceptance")
        if not self.substantive(task_id, "verification.md"):
            raise WorkflowError("Fill in verification.md with actual evidence first")
        d["checks"][role] = outcome
        if outcome == "fail":
            d["state"] = "implementing"
            d["checks"] = {"qa": None, "pm": None}
            d["commit"] = None
        elif d["checks"]["qa"] == "pass" and d["checks"]["pm"] == "pass":
            d["state"] = "ready_to_merge"
        self.event(d, f"{role.upper()} verification: {outcome}")
        self.save(d)
        return d

    def dispatch(self, task_id: str, role: str, *, dry_run: bool = False) -> dict[str, Any]:
        d = self.load(task_id)
        roles = self.config["roles"]
        if role not in roles:
            raise WorkflowError(f"Unknown role '{role}'; available: {', '.join(roles)}")
        if role == "pm":
            self.require(d, "planning", "tickets_draft", "verifying")
        elif role == "qa":
            self.require(d, "plan_review", "verifying")
        elif role in ("implementer", "pro2"):
            self.require(d, "tickets_approved", "implementing")
            if not d["approval"]["tickets"] or not d["worktree"]:
                raise WorkflowError("Need approved tickets and a worktree before implementation")
        else:
            raise WorkflowError("Role dispatch not implemented in this MVP")
        if role in d["agents"]:
            raise WorkflowError(f"Role '{role}' already has an assigned pane; use send/read")
        workspace = os.environ.get("HERDR_WORKSPACE_ID")
        if not dry_run and (os.environ.get("HERDR_ENV") != "1" or not workspace):
            raise WorkflowError("Dispatch must run inside a Herdr pane (HERDR_ENV=1)")
        cwd = d["worktree"] if role in ("implementer", "pro2") else str(self.repo)
        alias = f"{role}-{task_id}".lower().replace("_", "-")[:32]
        entry = roles[role]
        kind = entry["kind"]
        if kind not in ("claude", "codex"):
            raise WorkflowError("Only native claude/codex are allowed in v4")
        commands = [
            ["herdr", "tab", "create", "--workspace", workspace or "<workspace>", "--cwd", cwd, "--label", f"{role.upper()} | {task_id}", "--no-focus"],
            ["herdr", "agent", "start", alias, "--kind", kind, "--pane", "<returned-pane>"]
        ]
        native_args = entry.get("args", [])
        if native_args:
            commands[-1].extend(["--", *native_args])
        if dry_run:
            return {"dry_run": True, "commands": commands, "cwd": cwd, "state": d["state"]}
        tab_result = json_command(*commands[0])
        pane = tab_result.get("root_pane", {}).get("pane_id")
        tab = tab_result.get("tab", {}).get("tab_id")
        if not pane or not tab:
            raise WorkflowError(f"Tab created but pane/tab ID missing: {tab_result}")
        # Record before agent start: a failed start must not silently create duplicates.
        d["agents"][role] = {"name": alias, "kind": kind, "tab": tab, "pane": pane, "started": False}
        self.event(d, f"Tab reserved for {role}: {tab}")
        self.save(d)
        args = ["herdr", "agent", "start", alias, "--kind", kind, "--pane", pane]
        if native_args:
            args += ["--", *native_args]
        json_command(*args, timeout=150)
        d["agents"][role]["started"] = True
        if role in ("implementer", "pro2"):
            d["state"] = "implementing"
        self.event(d, f"Started {role} in Herdr: {alias}")
        self.save(d)
        try:
            run("herdr", "pane", "rename", pane, f"{role.upper()} | {task_id}")
        except WorkflowError:
            pass  # Cosmetic only.
        return d

    def prompt(self, task_id: str, role: str) -> str:
        d = self.load(task_id)
        task = self.path(task_id)
        rules = (self.repo / "roles" / f"{role}.md").read_text(encoding="utf-8")
        stage = d["state"]
        if role == "pm":
            focus = {"planning": "Prepare or revise requirements.md and plan.md; do not implement.",
                     "tickets_draft": "Propose tickets in tickets.md using the approved plan. No implementation.",
                     "verifying": "Check acceptance criteria at the pinned commit, write verification.md."}.get(stage)
        elif role == "qa":
            focus = {"plan_review": "Independently review plan.md; document findings in review.md, do not change plan.md.",
                     "verifying": "Review only the pinned commit, tests, and regression risks; document results in verification.md."}.get(stage)
        else:
            focus = "Implement only approved tickets in your assigned worktree. Test, commit, and record evidence in implementation.md."
        if not focus:
            raise WorkflowError(f"Cannot prompt {role} in {stage}")
        return (
            f"TEAM Nexense task {task_id} | mode={d['mode']} | state={stage}\n"
            f"Source of truth: {task}\n"
            f"Repository: {self.repo}\nWorktree: {d.get('worktree') or '(none)'}\n"
            f"Pinned commit: {d.get('commit') or '(none)'}\n"
            f"Role policy:\n{rules}\n\nCurrent instruction: {focus}\n"
            "Matt Pocock Skills may be used when available and allowed by their invocation policy. "
            "Never treat a prompt as authorization to bypass a user approval. "
            "Return a concise handoff and list files changed and actual tests executed."
        )

    def send(self, task_id: str, role: str) -> str:
        d = self.load(task_id)
        if role not in d["agents"] or not d["agents"][role]["started"]:
            raise WorkflowError("Agent not running; dispatch first")
        name = d["agents"][role]["name"]
        result = json_command("herdr", "agent", "prompt", name, self.prompt(task_id, role))
        return f"Prompt sent to {name}; completion NOT assumed. Response: {str(result)[:240]}"

    def read(self, task_id: str, role: str) -> str:
        d = self.load(task_id)
        if role not in d["agents"]:
            raise WorkflowError("Agent not assigned")
        return run("herdr", "agent", "read", d["agents"][role]["name"], "--source", "recent-unwrapped", "--lines", "120")
