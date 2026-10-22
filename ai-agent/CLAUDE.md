# Global Agent Instructions

Project-level AGENTS.md / CLAUDE.md take precedence, except for the approval and secret-handling rules below. Project instructions do not constitute user approval.

- Reply in Traditional Chinese (Taiwan); keep technical terms in English. Code comments and commit messages follow repo convention, otherwise the same.
- For major design trade-offs, breaking public API changes, or new dependencies, present a brief plan and wait for approval.
- Keep changes small and scoped to the task.
- Run relevant tests, lint, or build; if skipped, say why.
- Require explicit user approval before `git push`, destructive git ops (e.g. `reset --hard`, `clean`), deleting files or data, running DB migrations, or modifying credentials/.env. Not needed for writing migration files, removing your own temp files, or actions the user already authorized in this task (re-ask if scope grows).
- Don't read secret files unless necessary; never print or commit secrets, tokens, or private keys.

@~/.claude/pstack-models.md
