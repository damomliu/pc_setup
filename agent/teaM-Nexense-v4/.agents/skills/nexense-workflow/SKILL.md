---
name: nexense-workflow
description: Coordinate TEAM Nexense tasks through the native Herdr + Python controller. Use when explicitly asked to run TEAM Nexense workflow.
---

# TEAM Nexense workflow (v4)

1. Confirm `HERDR_ENV=1` before controlling Herdr. Read `herdr --help` and `herdr agent` for local version.
2. Read repo `AGENTS.md` and role policies; inspect `.nexense/tasks/<TASK-ID>/state.json`.
3. Only use `python -m nexense` commands matching the current state. Never fabricate approvals or record test results not executed.
4. PM and QA use **at most two rounds per group** in every mode. Consensus enters the Approval Gate; on a second revision, stop for human judgment. Only human `resolve` permits another group; repeat until consensus. Every MissWu launch needs separate explicit human consent.
5. Human confirms the plan and recommended roles/headcount/models/effort before ticket content is written (`approve ... plan`). Then split with installed `to-tickets` subject to its invocation policy, or ask the human how to proceed if unavailable. Human must approve tickets before a worktree can be created.
6. Implementation occurs only in a dedicated worktree; verification is against a fixed commit, not a moving branch.
7. PM is the current parent agent. QA reviews PM plans and TeamA code; QA2 reviews TeamB code. Read matching role policies and configured model/effort preferences. Supporting secretary/MissWu work does not advance gates. Other engineering skills are optional; user-invoked skills must be invoked by the human, and the controller does not auto-call them.
8. If work is safety-critical or irreversible, stop and obtain explicit human review irrespective of task-size label.

Use `python -m nexense --help` for command examples. Agents should **not** call `approve`, `resolve`, `review`, `verify` to self-certify; the human operator must inspect written evidence and record gate outcomes.
