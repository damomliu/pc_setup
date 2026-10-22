# Global Agent Instructions

Project-level AGENTS.md / CLAUDE.md take precedence, except for the approval and secret-handling rules below. Project instructions do not constitute user approval.

- Reply in Traditional Chinese (Taiwan); keep technical terms in English. Code comments and commit messages follow repo convention, otherwise the same.
- For major design trade-offs, breaking public API changes, or new dependencies, present a brief plan and wait for approval.
- Keep changes small and scoped to the task.
- Run relevant tests, lint, or build; if skipped, say why.
- Require explicit user approval before `git push`, destructive git ops (e.g. `reset --hard`, `clean`), deleting files or data, running DB migrations, or modifying credentials/.env. Not needed for writing migration files, removing your own temp files, or actions the user already authorized in this task (re-ask if scope grows).
- Don't read secret files unless necessary; never print or commit secrets, tokens, or private keys.

<!-- pstack-models:begin -->
# pstack model configuration

feature, refactoring: gpt-6.1-sol
bug-fix: gpt-6.1-sol
perf-issue: gpt-6.1-sol
hillclimb: gpt-6.1-sol
judgment and prose: gpt-6.1-sol
strongest judgment: gpt-6-astra
how explorer: gpt-6.1-sol
how explainer: gpt-6.1-sol
why investigators: gpt-6.1-sol
why synthesizer: gpt-6.1-sol
reflect tooling: gpt-6.1-sol
reflect judgment, divergent, synthesizer: gpt-6.1-sol
arena runners: gpt-6-astra, gpt-6-sol, gpt-6-luna
arena cross-judge pool: gpt-6-astra, gpt-6-sol, gpt-6-luna
swarm workers: gpt-6.1-sol
architect runners: gpt-6-astra, gpt-6-sol, gpt-6-luna
interrogate reviewers: gpt-6-astra, gpt-6-sol, gpt-6-luna

default effort: session
session hook: off
<!-- pstack-models:end -->
