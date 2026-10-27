# TEAM Nexense v4 — shared agent rules

- Workflow authority: `python -m nexense` controls task state and approval gates; only human users run `approve`, `resolve`, or `verify` status actions.
- Agent collaboration: Herdr runs native Claude Code and Codex CLI. No Pi, paid API keys, or third-party OAuth workarounds.
- Plan → independent QA review (maximum **two reviews total**) → human plan approval → tickets draft → human tickets approval → worktree implementation → pinned-commit QA review → PM acceptance → ready-to-merge.
- Quick mode skips mandatory independent plan review, **not** human approval. Safety-sensitive work must be escalated to Standard/Deep by the user.
- One primary implementer + one primary reviewer per task. Do not concurrently edit the same worktree.
- Source of truth is `.nexense/tasks/<TASK-ID>/`. Terminal output is for visibility only, not proof of completion.
- No auto-merge. Do not run dangerous Git cleanup, change production infrastructure, or modify PLC control logic without user approval.
- Skills are optional engineering methods; follow actual installed versions and user/model invocation restrictions.
