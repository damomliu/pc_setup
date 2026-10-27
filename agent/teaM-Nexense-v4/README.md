# TEAM Nexense v4 — Herdr Native + Python Workflow Controller

**目標：不增加模型 API 計費，沿用原生 Claude Code / Codex CLI 與現有訂閱額度。**

這是 **v4.0 Skill + v4.1 Python Controller 的可執行範例**，不是已在 Windows / WSL2 / macOS 和 Herdr 實機驗證的正式產品。不包含 Pi。沒有自動將模型訂閱額度轉接到其他 SDK。

## Architecture

```text
Human ── approves plans/tickets ─── Python CLI (state JSON, approval gates)
                                       │
                                       └── Herdr (tabs, panes, native agents)
                                             ├── PM: current parent agent
                                             ├── QA: plans + TeamA code / QA2: TeamB code
                                             ├── TeamA: ShiFu, PRO, SLAVE
                                             ├── TeamB: PRO2, SLAVE2
                                             └── MissWu (human-approved) / secretary
Git worktree ── approved tickets ── commit SHA ── QA or QA2 + PM verification
```

- Python controller is **deterministic**: no model API calls.
- Herdr controls running native agent sessions; output is not automatically interpreted as evidence.
- Matt Pocock Skills remain optional and should be installed separately. The prompts respect user-invoked Skills restrictions.
- User approval and Review outcomes are recorded by CLI and are **not authenticated security controls**. Do not give Agent unattended write access to task state if human-only approvals matter.

## Team roles

Team definition: repository-root [TEAM-NEXENSE.md](../../TEAM-NEXENSE.md). The portable role policies live in `roles/`; CLI role IDs use lowercase, and `secretary` means 秘書.

| Role | Model / effort | Responsibility |
|---|---|---|
| PM | claude-opus-5-5 / medium **or** gpt-6.1-sol / high **or** gpt-6-astra / medium | Current parent agent; spec, create/rename members, assign tickets, track progress, PM-QA plan review, acceptance |
| MissWu (`misswu`) | gpt-6-astra / medium | Expensive Escalation Specialist for difficult or complex issues; separate human approval for every launch |
| TeamA QA | gpt-6.1-sol / high | Review PM's plan for both teams; review ShiFu/PRO/SLAVE code |
| TeamA ShiFu (`shifu`) | claude-opus-5-5 / medium default | Implement code; multiple members allowed |
| TeamA PRO | claude-sonnet-5-5 / medium default | Implement code; multiple members allowed |
| TeamA SLAVE | claude-haiku-5-5 / medium default | Implement code; multiple members allowed |
| TeamB QA2 | claude-opus-5-5 / medium default | Review PRO2/SLAVE2 code |
| TeamB PRO2 | gpt-6.1-sol / medium default | Implement code; multiple members allowed |
| TeamB SLAVE2 | gpt-6-luna / medium default | Implement code; multiple members allowed |
| 秘書 (`secretary`) | gpt-6.1-sol / medium | Miscellaneous work, including researching unclear GPT model characteristics |

Effort choices are low/medium/high; unspecified effort defaults to medium. PM recommends roles, headcount, models and effort for human confirmation **before writing ticket content**. After confirmation, use the installed `to-tickets` skill subject to its invocation policy; if unavailable or human invocation is required, ask the human how to proceed. Human tickets approval still precedes implementation.

The controller retains one primary builder per task/worktree. Use separate tasks/worktrees for multiple members; it does not schedule parallel tickets. Legacy `implementer` remains a TeamA PRO entry. PM reuses the parent session with `prompt`; `dispatch pm` remains available for an explicitly delegated PM session. PM names its own pane; controller dispatch names member panes with role and task ID.

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
5. Edit `.nexense/team.json` to map roles to `kind` (`claude` / `codex`) and **validated** native CLI `args`. The `model`, `effort` and PM `alternatives` fields record team preferences; they are **not** automatically passed as CLI flags. Set verified native arguments for the selected model/effort before dispatch, or confirm them in the reused session. PM defaults to the gpt-6.1-sol/high preference; choosing a Claude alternative also requires changing `kind`.

### Step-by-step: Standard workflow

Start from repository root:

```bash
python -m nexense start TASK-001 --mode standard
python -m nexense status TASK-001
python -m nexense prompt TASK-001 pm  # Use in the current parent session
# PM names its own pane using its actual pane ID:
herdr pane rename <PM-PANE-ID> "PM | TASK-001 spec"
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

If QA says `revise`, PM edits the plan, re-submits, and QA reviews again. Each PM-QA group has **at most two rounds**. Consensus in either round reaches the Approval Gate. **A second revise outcome blocks the task**: PM reports unresolved issues and stops for human judgment. Human `resolve` starts another two-round group; repeat until consensus. PM may propose MissWu assistance, with separate human launch approval. `resolve` does not itself approve a plan or select an answer.

At the Approval Gate, PM presents the plan and staffing recommendation. The human checks and confirms them before allowing ticket content to be written (the initial empty `tickets.md` is only scaffolding):

```bash
python -m nexense prompt TASK-001 pm  # Present plan + roles/headcount/models/effort
# Human confirms plan AND staffing, authorizing ticket drafting:
python -m nexense approve TASK-001 plan
python -m nexense prompt TASK-001 pm  # Use to-tickets after confirmation
# Inspect tickets.md carefully
python -m nexense tickets-ready TASK-001
python -m nexense approve TASK-001 tickets
python -m nexense worktree TASK-001
python -m nexense dispatch TASK-001 pro
python -m nexense send TASK-001 pro
python -m nexense read TASK-001 pro
```

The Implementer commits to the new worktree (sibling folder `<repo>-wt-task-001`) and writes `implementation.md` **in the original repo's `.nexense/tasks/TASK-001/` directory**. Operator copies the full HEAD SHA:

```bash
python -m nexense finish TASK-001 <FULL-COMMIT-SHA>
python -m nexense send TASK-001 qa
# Inspect verification.md and real QA evidence
python -m nexense verify TASK-001 qa pass
python -m nexense prompt TASK-001 pm
# Inspect PM acceptance evidence
python -m nexense verify TASK-001 pm pass
python -m nexense status TASK-001
```

State ends in `ready_to_merge`. **This sample never merges automatically.** QA/QA2 and PM output goes to one `verification.md` file: they should append separate headings to avoid overwriting one another.

For TeamB, dispatch `pro2` or `slave2` instead of `pro`. The successful builder dispatch assigns QA2 code review: after `finish`, dispatch/send `qa2` and record `verify TASK-001 qa2 pass`, then PM acceptance. `qa` cannot sign off TeamB code; `qa2` cannot replace QA in PM plan review.

Secretary and MissWu provide advice without advancing task state:

```bash
python -m nexense dispatch TASK-001 secretary
python -m nexense send TASK-001 secretary
python -m nexense dispatch TASK-001 misswu --dry-run  # Preview; no launch consent
# Only the human, after approving this specific launch:
python -m nexense dispatch TASK-001 misswu --human-approved
python -m nexense send TASK-001 misswu
```

The flag records consent for this dispatch only. Plan/tickets approval and previous launches do not authorize another MissWu launch. Agents must not pass it to self-approve.

### Quick and Deep

```bash
python -m nexense start TASK-002 --mode quick
python -m nexense start TASK-003 --mode deep
```

- Quick uses a smaller planning scope; it retains the same PM-QA review and human plan/staffing/tickets approvals. It is not intended for high-risk production or device-control changes. Existing Quick tasks already awaiting plan approval should be restarted if they skipped QA review.
- Standard requires QA review and human approvals.
- Deep currently uses the same enforcement gates as Standard; deeper grilling, additional design alternatives, staged verification and risk controls are **prompt-level requirements**, not fully implemented automatic policies.

## Files

```text
AGENTS.md                                  shared policies
.nexense/team.json                         role-to-CLI mapping
.nexense/tasks/<TASK-ID>/*                 runtime docs and state (gitignored)
roles/*.md                               full team role policies + shared builder rules
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
3. All listed role paths are supported; real native model/effort arguments must be validated locally. Metadata alone does not select a runtime model.
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
