# TEAM Nexense v4 — Herdr Native + Python Workflow Controller

**目標：不增加模型 API 計費，沿用原生 Claude Code / Codex CLI 與現有訂閱額度。**

這是 **v4.0 Skill + v4.1 Python Controller 的可執行範例**，不是已在 Windows / WSL2 / macOS 和 Herdr 實機驗證的正式產品。不包含 Pi。沒有自動將模型訂閱額度轉接到其他 SDK。

## Architecture

```text
Human ── approves plans/tickets ─── Python CLI (state JSON, approval gates)
                                       │
                                       └── Herdr (tabs, panes, native agents)
                                             ├── PM: Claude Code
                                             ├── QA: Codex CLI
                                             └── Implementer: Claude Code or Codex CLI
Git worktree ── approved tickets ── commit SHA ── QA + PM verification
```

- Python controller is **deterministic**: no model API calls.
- Herdr controls running native agent sessions; output is not automatically interpreted as evidence.
- Matt Pocock Skills remain optional and should be installed separately. The prompts respect user-invoked Skills restrictions.
- User approval and Review outcomes are recorded by CLI and are **not authenticated security controls**. Do not give Agent unattended write access to task state if human-only approvals matter.

## Installation

Requirements: Python **3.11+**, `git`, `herdr`, `claude`, `codex`, shell. Python controller uses only stdlib. The CLI samples use Bash, zsh, Git Bash or WSL2. Execute from **a Herdr Pane**, on the same OS where the repo and CLIs exist. Use `python` or `python3` depending on OS.

1. Copy `nexense/`, `.nexense/team.json`, `roles/`, `.agents/skills/nexense-workflow/`, and the guidance in `AGENTS.md` into the target Git repo. Merge any existing `AGENTS.md` rather than overwriting it.
2. On Claude Code / Codex, install Herdr Skill (optional but useful):
   ```bash
   npx skills add herdrdev/herdr --skill herdr -g
   ```
3. Install your preferred Matt Pocock Skills separately, following their current installation and user/model invocation rules.
4. Test CLIs in your active Herdr environment:
   ```bash
   herdr --version
   herdr agent
   herdr tab
   claude --version
   codex --version
   printf '%s %s\n' "$HERDR_ENV" "$HERDR_WORKSPACE_ID"
   ```
5. Edit `.nexense/team.json` to map roles to `kind` (`claude` / `codex`) and **validated** native CLI `args`. Defaults intentionally omit hardcoded model aliases. Additional model hints are *not* CLI args.

### Step-by-step: Standard workflow

Start from repository root:

```bash
python -m nexense start TASK-001 --mode standard
python -m nexense status TASK-001
python -m nexense dispatch TASK-001 pm --dry-run
python -m nexense dispatch TASK-001 pm
python -m nexense send TASK-001 pm
python -m nexense read TASK-001 pm
```

**Operator** checks `requirements.md` and `plan.md` inside `.nexense/tasks/TASK-001/`, then submits for review:

```bash
python -m nexense submit-plan TASK-001
python -m nexense dispatch TASK-001 qa
python -m nexense send TASK-001 qa
python -m nexense read TASK-001 qa
# Inspect review.md (written by QA) and record the result:
python -m nexense review TASK-001 pass   # or revise
```

If QA says `revise`, PM edits plan, re-submits, and QA reviews again. **A second revise outcome blocks the task**. Human resolves by inspecting the disagreement and running `resolve` to start a new review budget. `resolve` requires human judgment; it doesn't auto-select an answer.

With approved plan:

```bash
python -m nexense approve TASK-001 plan
python -m nexense send TASK-001 pm  # Same PM pane creates draft tickets
# Inspect tickets.md carefully
python -m nexense tickets-ready TASK-001
python -m nexense approve TASK-001 tickets
python -m nexense worktree TASK-001
python -m nexense dispatch TASK-001 implementer
python -m nexense send TASK-001 implementer
python -m nexense read TASK-001 implementer
```

The Implementer commits to the new worktree (sibling folder `<repo>-wt-task-001`) and writes `implementation.md` **in the original repo's `.nexense/tasks/TASK-001/` directory**. Operator copies the full HEAD SHA:

```bash
python -m nexense finish TASK-001 <FULL-COMMIT-SHA>
python -m nexense send TASK-001 qa
# Inspect verification.md and real QA evidence
python -m nexense verify TASK-001 qa pass
python -m nexense send TASK-001 pm
# Inspect PM acceptance evidence
python -m nexense verify TASK-001 pm pass
python -m nexense status TASK-001
```

State ends in `ready_to_merge`. **This sample never merges automatically.** QA and PM output goes to one `verification.md` file: they should append separate headings to avoid overwriting one another.

### Quick and Deep

```bash
python -m nexense start TASK-002 --mode quick
python -m nexense start TASK-003 --mode deep
```

- Quick bypasses mandatory *plan review*, but still requires human plan/tickets approval in this conservative MVP. It is not intended for high-risk production or device-control changes.
- Standard requires QA review and human approvals.
- Deep currently uses the same enforcement gates as Standard; deeper grilling, additional design alternatives, staged verification and risk controls are **prompt-level requirements**, not fully implemented automatic policies.

## Files

```text
AGENTS.md                                  shared policies
.nexense/team.json                         role-to-CLI mapping
.nexense/tasks/<TASK-ID>/*                 runtime docs and state (gitignored)
roles/{pm,qa,implementer,pro2}.md          agent prompts
.agents/skills/nexense-workflow/SKILL.md   reusable Skill
nexense/controller.py                      state machine + Herdr/Git adapter
nexense/__main__.py                         CLI entrypoint
tests/test_workflow.py                     offline tests (no Herdr required)
```

## Test

```bash
python -m unittest discover -s tests -v
```

Tests simulate the workflow using real temporary Git repos/worktrees. The Herdr dispatch needs an **interactive Herdr pane**, real supported Claude/Codex installations, authorization and compatible CLI versions. Offline tests cannot prove this integration.

## Limitations / roadmap

1. No database/concurrent writers, no scheduler, no auto-recovery. Do not run multiple controllers modifying one task at once.
2. No machine-based remote routing (Windows ↔ WSL ↔ macOS). Run the controller where the specific Herdr server and working directory live.
3. Only `pm`, `qa`, `implementer`, `pro2` dispatch paths are implemented. Extend to ShiFu, QA2, secretary, MissWu once role mappings are verified.
4. Agent names are unique only within one Herdr server and limited to 32 chars; validate collisions manually.
5. A failed `herdr agent start` may leave a tab recorded in `state.json`, requiring operator inspection. Do **not** blindly retry dispatch and create duplicate agents.
6. Controller does not read QA files and infer `pass` or `fail`; these are recorded by the human.
7. The QA/PM prompt can write to a shared `verification.md`; use headings and preserve previous results.
8. Only one worktree per task. Multi-ticket parallel scheduling intentionally deferred.
9. `--model` / effort flags are intentionally not guessed; put only verified arguments in `team.json`.

## References checked 2026-10-27

- [Herdr CLI reference](https://herdr.dev/docs/cli-reference/)
- [Herdr agent automation](https://herdr.dev/docs/agent-automation/)
- [Herdr official Skill](https://github.com/herdrdev/herdr/blob/master/skills/herdr/SKILL.md)
- [Matt Pocock Skills](https://github.com/mattpocock/skills)
