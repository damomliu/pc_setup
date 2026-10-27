---
name: nexense-workflow
description: Coordinate TEAM Nexense tasks through the native Herdr + Python controller. Use when explicitly asked to run TEAM Nexense workflow.
---

# TEAM Nexense workflow (v4)

1. Confirm `HERDR_ENV=1` before controlling Herdr. Read `herdr --help` and `herdr agent` for local version.
2. Read repo `AGENTS.md` and role policies; inspect `.nexense/tasks/<TASK-ID>/state.json`.
3. Only use `python -m nexense` commands matching the current state. Never fabricate approvals or record test results not executed.
4. PM and QA use **at most two review rounds total**. On a second revision, return the task to the human.
5. After human plan approval, prepare draft tickets. Human must approve tickets before a worktree can be created.
6. Implementation occurs only in a dedicated worktree; verification is against a fixed commit, not a moving branch.
7. Matt Pocock `grill-with-docs`, `to-spec`, `to-tickets`, `implement`, `tdd` and `code-review` are optional. User-invoked skills must be invoked by the human; the controller does not auto-call them.
8. If work is safety-critical or irreversible, stop and obtain explicit human review irrespective of task-size label.

Use `python -m nexense --help` for command examples. Agents should **not** call `approve`, `resolve`, `review`, `verify` to self-certify; the human operator must inspect written evidence and record gate outcomes.
