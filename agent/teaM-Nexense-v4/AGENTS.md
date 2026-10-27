# TEAM Nexense v4 — shared agent rules

- Team definition: root `TEAM-NEXENSE.md` (when present) defines membership; `.nexense/team.json` records model/effort preferences. Before planning, dispatching, reviewing or implementing, read the matching `roles/<role>.md`; builders also read `roles/implementer.md`.
- PM is the current parent agent: spec, member creation/pane naming, ticket assignment, progress and acceptance. Use `prompt` to reuse that session. TeamA (ShiFu/PRO/SLAVE) code is reviewed by QA; TeamB (PRO2/SLAVE2) code by QA2. QA reviews PM's plan for both teams. Secretary handles miscellaneous work/model research; every MissWu launch needs separate explicit human approval.
- Workflow authority: `python -m nexense` controls task state and approval gates; only human users run `approve`, `resolve`, `review`, or `verify` status actions. `dispatch ... misswu --human-approved` records human consent for that launch only; agents cannot self-authorize it.
- Agent collaboration: Herdr runs native Claude Code and Codex CLI. No Pi, paid API keys, or third-party OAuth workarounds.
- Plan → PM-QA review (at most **two rounds per group**) → Approval Gate → tickets → human tickets approval → worktree implementation → pinned-commit QA/QA2 review → PM acceptance → ready-to-merge. After two unresolved rounds, stop for human judgment; only human `resolve` permits another group. Consensus in either round proceeds to the Approval Gate.
- Approval Gate: human confirms plan and recommended roles/headcount/models/effort **before ticket content is written** (`approve ... plan`). Then use installed `to-tickets` subject to its invocation policy; if unavailable, ask the human how to proceed. Effort: low/medium/high, medium by default except role-specific settings. Quick skips mandatory independent plan review, **not** human approval; safety-sensitive work must be escalated to Standard/Deep by the user.
- One primary implementer + one primary reviewer per task. Do not concurrently edit the same worktree.
- Source of truth is `.nexense/tasks/<TASK-ID>/`. Terminal output is for visibility only, not proof of completion.
- No auto-merge. Do not run dangerous Git cleanup, change production infrastructure, or modify PLC control logic without user approval.
- Skills are optional engineering methods; follow actual installed versions and user/model invocation restrictions.
