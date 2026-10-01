# Agentic Development Workflow

## Overview

This document defines the end-to-end workflow for 100% agentic software development using Claude (web interface and Claude Code), GitHub Projects, and a **mode-switching orchestrator** (`orchestrate-v6`, relaunched by a dumb loop) running a PR-based pipeline with review gates. The workflow covers everything from initial brainstorming through deployed, tested, reviewed code. Every skill works under [engineering-discipline.md](../standards/engineering-discipline.md) (ED-1..ED-5: confirm against source, adversarially self-review, cold-read the saved ticket).

The core philosophy: separate concerns between human-driven discovery, AI-assisted specification, and fully orchestrated development — with clean context boundaries at each transition to prevent drift, and milestone-based review gates to ensure human validation at meaningful intervals. Development can run as **several orchestrators at once** against one repo — each in its own clone, each working its own batch of tickets — with no coordination layer between them beyond what GitHub already shows (§4.10).

---

## Phase 1: Discovery & Capture

**Tool:** Otter.ai
**Participants:** Developer + stakeholders/clients
**Output:** Raw transcript (.txt)

Record a freeform discussion using Otter.ai for live transcription. There is no required structure — the goal is to get every idea, requirement, concern, and tangential thought captured. Participants throw out everything they're thinking about in whatever order it comes.

Export the full transcript as a text file. This is the primary input artifact for the next phase.

---

## Phase 2: PRD Refinement

**Tool:** Claude Web Interface
**Input:** Transcript file
**Output:** PRD (Markdown) + Screen Inventory (Markdown) + Decisions Log (Markdown)

### 2.1 Initial Synthesis

Upload the transcript to Claude in the web interface. Prompt Claude to read the entire transcript, make sense of the discussion, and produce a first-pass PRD in Markdown format.

### 2.2 Convergence Loop

Enter an iterative refinement cycle:

1. Ask Claude: "Do you have any questions, or am I missing anything?"
2. Claude identifies gaps, asks clarifying questions, raises items not yet considered.
3. Answer the questions and refine scope.
4. When Claude indicates readiness to produce the PRD, ask: "What other items should I be thinking about?"
5. Repeat. Claude's suggestions will move from highly pertinent to increasingly marginal — this diminishing return is the exit signal.

### 2.3 Engineering Scoping

During the convergence loop (or as a dedicated step), define:

- **Tech stack** — languages, frameworks, databases, infrastructure
- **Compilable components** — APIs, clients, worker processes, background services. Define what each binary/deployable unit is and what it does. This prevents Claude Code from making assumptions about service boundaries during development.
- **Architectural constraints** — patterns to follow, patterns to avoid, dependency rules

### 2.4 Screen Inventory

After functional requirements and engineering scope are largely settled, walk through the application's UI screen by screen. This is conversational — describe what each screen does, what the user sees and can do, and where they can navigate from there. Claude organizes this into a structured Screen Inventory document.

The Screen Inventory defines:

- **Every screen/view** with its purpose, key content, and available user actions
- **Modals and overlays** with their triggers, fields, and validation rules
- **Navigation flow** — a text-based map showing how screens connect
- **Data dependencies** — which API endpoints each screen needs
- **Key states** — empty, loading, and error states for each screen
- **Shared components** — UI elements that appear across multiple screens, defined once to prevent duplication

This gives Claude Code explicit screen boundaries during development, just as component definitions give it explicit service boundaries.

A reusable Screen Inventory template is available at `workflow/screen-inventory-template.md`.

### 2.5 Final PRD Review

Claude produces the complete PRD. Review it in one more cycle of reading and pointing things out until satisfied.

### 2.6 Decisions Log

Before closing the Claude Web session, ask Claude to produce a **Decisions Log** as a companion artifact:

- Key decisions made during the PRD process
- Alternatives that were considered and why they were rejected
- Assumptions that were made and their rationale
- Open questions that were deferred

Format: Short entries, each following the pattern: "**Decision:** [what was decided]. **Alternatives considered:** [what else was on the table]. **Rationale:** [why this choice was made]."

The Decisions Log gives Claude Code the *reasoning* behind the PRD, not just the requirements.

---

## Phase 3: Project Bootstrap

**Tool:** Claude Code
**Input:** PRD + Screen Inventory + Decisions Log
**Output:** Initialized repo with milestoned backlog

### 3.1 Repository Setup

Create the project folder, GitHub repo, and project board. The project board uses a Kanban layout with columns defined in `standards/project-tracking.md`: Inbox → Up Next → In Progress → Waiting/Blocked → Done.

Two types of items live on the board:

- **Development stories** (`story` label) — code-producing tickets following vertical slice principles
- **Operational tasks** (`task` label) — non-code items tracked for accountability

Enable the **Auto-add to project** workflow so new issues automatically land on the board.

### 3.2 Standards Integration

The project pulls from the shared TI-Engineering-Standards repository. On session start:

1. If the standards repo exists locally: `git pull --ff-only`
2. If not: `git clone` the repo
3. Read `CLAUDE.md` from the standards repo and every file it references
4. Sync skills from the standards repo into the project's `.claude/skills/` (skipping `archive/` and local overrides)

This is defined in each project's `CLAUDE.md` using the project template at `templates/CLAUDE-project.md`.

### 3.3 Backlog Generation (prd-to-backlog-v6)

Use the `prd-to-backlog-v6` skill to decompose the PRD into a milestoned backlog. The skill:

1. Reads the PRD, Screen Inventory, Decisions Log, and ARCHITECTURE.md
2. Identifies foundation work (kept minimal — only what can't be part of a vertical slice)
3. Groups screens and capabilities into milestones per `standards/story-writing-standards.md`
4. Decomposes into vertical-slice stories sized by entity lifecycle
5. Presents the full plan for human review before creating any issues
6. Creates GitHub issues with proper labels, custom fields, and milestone markers

Stories follow the conventions in `standards/story-writing-standards.md`: vertical slices preferred, entity lifecycle grouping (create + list + view + delete = one story), capability-based splitting for larger features.

Every ticket gets a **`## Dependencies`** section — written by `prd-to-backlog-v6`, `add-story-v6`, `refine-story-v6`, `triage-v6`, and the pipeline itself for the follow-up tickets it creates. It lists one `- #N — reason` line per blocker, or `None`. It is what `plan-batches-v6` reads to keep dependent tickets in the same batch (§4.10).

### 3.4 Backlog Review

After the skill generates stories, review them:

- Do story titles map back to PRD requirements?
- Is the decomposition at the right granularity?
- Are there gaps — PRD requirements with no corresponding story?
- Are milestone groupings sensible?

### 3.5 Incremental Story Additions (add-story-v6)

When adding stories mid-project (not during initial PRD decomposition), use `add-story-v6`. The skill:

1. Reviews the existing backlog and codebase
2. Works conversationally to understand what you want to add
3. Proposes stories following the same standards
4. Determines milestone placement
5. Creates issues after human approval

### 3.6 PRD Reconciliation (reconcile-backlog-v6)

When a PRD is revised mid-project (scope changes, new decisions, stakeholder feedback), use `reconcile-backlog-v6` to reconcile the changes against the existing backlog and codebase. The skill:

1. Diffs the old and new PRDs section by section, identifying material changes
2. Fetches the full backlog (open and closed issues) and scans the codebase to understand what's already built
3. Classifies each change as: **CREATE** (new ticket), **UPDATE** (modify existing open ticket), **FLAG** (closed ticket needs rework — creates a delta ticket), or **SKIP** (cosmetic/doc-only)
4. Writes a checklist file to `docs/` for state tracking and recovery
5. Presents the full reconciliation plan for human approval before touching GitHub
6. Executes approved actions using `add-story-v6` (for new tickets) and `refine-story-v6` (to re-refine updated tickets)

This keeps the backlog in sync with the PRD as a living document, rather than requiring a full re-decomposition.

### 3.7 Local Development Setup

After the repo and backlog exist, verify the project runs locally before development begins.

**Prerequisites:**
- .NET SDK installed
- Docker running (required for Testcontainers)
- Git hooks configured:
  ```bash
  git config --local core.hooksPath .githooks
  ```

**Run the application locally:**
1. Set `Authentication:UseDevBypass` to `true` in `appsettings.Development.json` if you want to skip Azure AD locally — or configure Azure AD credentials if you prefer to run against real auth
2. Start the application and verify it loads
3. Run unit tests: `dotnet test` — all should pass on a fresh repo
4. Run integration tests: `dotnet test tests/{Project}.Integration.Tests/` — requires Docker running

If any tests fail on a fresh clone, stop and fix before proceeding. A clean baseline is required before development begins. See `standards/environments.md` for full local environment details.

---

## Phase 4: Orchestrated Development

**Tool:** Claude Code with orchestrate-v6
**Input:** Backlog tickets (refined automatically by the orchestrator as Stage 1)
**Output:** Implemented, reviewed, tested, merged code

### 4.1 Architecture: PR-Based Pipeline with Review Gates

The pipeline uses pull requests as the unit of work with automated engineering and security review gates. The orchestrator spawns fresh sub-agents for each stage, preventing context drift. It is itself **stateless and relaunched** by a dumb loop: on each launch it self-selects **WORKING** (process up to N ready tickets, then checkpoint and exit) or **CLEANUP** (end-of-run oversight) from durable state on a per-run tracking issue — so a crash mid-run just relaunches and recovers state, and no single session accumulates context rot. The test work follows the four-tier model (Unit + Contract = fast tier, no Docker; Integration = real infra; UI = journey-scoped on the self-hosted runner); see [standards/testing.md](../standards/testing.md).

```
Per Ticket:
1.  REFINE ──────────── refine-story-v6 (enriches issue spec)
2.  IMPLEMENT ───────── implement-ticket-v6 (creates PR #1)
3.  ENGINEERING REVIEW ─ engineering-review-v6 (standards check)
    └─ Loop: reviewer ↔ implementer fix mode (max 3 iterations)
4.  SECURITY REVIEW ──── security-review-v6 (OWASP Top 10 + infrastructure)
    └─ Loop: reviewer ↔ implementer fix mode (max 2 iterations)
    └─ On pass → merge gate → merge PR #1
    └─ ci-fix-v6 WATCH (background) ─── monitors CI/CD for the merge
5.  INTEGRATION TESTS ── integration-test-v6 (creates PR #2)
6.  ENGINEERING REVIEW ─ engineering-review-v6 (integration test quality)
    └─ Loop: reviewer ↔ test-writer fix mode (max 3 iterations)
    └─ On approve → merge gate → merge PR #2
    └─ ci-fix-v6 WATCH (background) ─── monitors CI/CD for the merge
7.  UI TESTS ─── ui-test-v6 (creates PR #3)
8.  ENGINEERING REVIEW ─ engineering-review-v6 (ui test quality)
    └─ Loop: reviewer ↔ test-writer fix mode (max 3 iterations)
    └─ On approve → merge gate → merge PR #3
    └─ ci-fix-v6 WATCH (background) ─── monitors CI/CD for the merge
9.  CLOSE ───────────── drain CI watchers, check acceptance criteria, close issue

    Background CI/CD side-channel:
    ┌─ ci-fix-v6 WATCH reports failure
    └─ ci-fix-v6 FIX (background) ─── diagnoses logs, creates fix PR, merges
       └─ If FIX blocked → circuit breaker halts orchestrator

    Merge gate (before every merge):
    ├─ PR checks green against the CURRENT main — if main moved, bring the PR
    │  up to date and re-test first
    ├─ PR red while main is red → not this ticket's fault: wait for the single
    │  CI fixer, then update and re-test
    └─ Merge conflict → one automatic resolve attempt, then halt
```

### 4.2 Milestone Gates

When the orchestrator encounters an issue with the `milestone` label, it stops regardless of operating mode (supervised or autonomous):

1. Runs the smoke test checklist from the milestone issue body
2. Reports results and lists stories completed in this milestone
3. Waits for human approval before continuing — approve through the run's operator-message slot, then resume with `--run`

This ensures the developer can launch the application, interact with it, and verify it matches expectations before more work proceeds. Milestones map to screen inventory groupings — each milestone delivers a coherent set of user-visible functionality.

### 4.3 Operating Modes and Launching

The orchestrator self-selects a **run mode** from durable state on each relaunch:
- **WORKING**: tickets in this run's scope are in "Up Next" — process up to N of them, in scope order, checkpoint to the tracking issue, and exit (the loop relaunches it).
- **CLEANUP**: none of the run's tickets are left in "Up Next" — run end-of-batch oversight (full UI dispatch, pyramid-ratio + drift check, TR gate-audit, inject fixes), then close the run.

Orthogonally, a **human-oversight mode** controls cadence:
- **Supervised**: hard stop between each ticket (`orchestrate-v6 supervised #<issue>`). Used when iterating on skills, early in a project, or when close oversight is desired.
- **Autonomous**: the dumb loop relaunches the orchestrator continuously, stopping only at milestones, circuit breakers, or completion. An operator can steer a headless run between loops via the operator-message slot on the tracking issue.

**Launching.** A run is always named explicitly — the orchestrator never goes looking at the board for work:
- `./scripts/orchestrate-v6.sh --tickets "#7,#8"` **starts a new run** for exactly those tickets (issue numbers, in processing order). The loop creates the run's tracking issue and refuses tickets another open run already owns.
- `./scripts/orchestrate-v6.sh --run 123` **continues run #123** — also how you resume after Ctrl-C, a crash, a milestone pause, or the relaunch cap.
- Neither, or both → it refuses and says why.
- `./scripts/orchestrate-v6.sh --status [123]` lists every open run, or shows one in detail. `monitor-v6 [123]` narrates the same way.
- Interactively: `orchestrate-v6 supervised #7,#8` (new run) or `orchestrate-v6 supervised --run 123` (continue).
- **Usage limit:** if a session dies on the Claude usage/rate limit, the loop marks the run `LIMIT_WAIT`, waits for the reset, and carries on — the wait doesn't count toward the relaunch cap.
- **Session endings:** after every session the loop records why it ended — `⏱ timed out`, `⏸ hit the usage limit`, `✖ crashed (rc=N)` or `■ ended cleanly` — in its log and as a comment on the run's tracking issue, and tells the next session (`ORCHESTRATE_PREVIOUS_SESSION_END`). So a 90-minute hang-guard timeout is never mistaken for a crash.

### 4.4 Circuit Breakers

Even in autonomous mode, the orchestrator halts entirely if:

- 3 consecutive tickets are Blocked or Partial — something systemic is wrong
- A merge conflict can't be resolved automatically — the orchestrator makes one attempt (merge `main` into the branch, resolve, re-run build and tests, back through the merge gate) before asking for human judgment
- 3 review iterations exhausted on 2 consecutive tickets — pattern problem
- A CI/CD fix agent reports Blocked — a pipeline failure that cannot be auto-fixed means main is broken and deployments are stuck

A red `main` is **not** a halt by itself: with several runs merging, it's an expected event. It goes to a single CI fixer (§4.5) while the run waits to merge; the halt only comes if that fix is Blocked. On any halt, fix the cause and resume with `--run`.

### 4.5 Background CI/CD Health Watching

After every PR merge, the orchestrator spawns **ci-fix-v6** in WATCH mode as a background agent. This runs in parallel with the next pipeline stage — the orchestrator does not block on it.

- **If CI/CD passes:** The watcher reports success and the orchestrator logs it. No action needed.
- **If CI/CD fails:** The watcher reports the failure. The orchestrator spawns **ci-fix-v6** in FIX mode — also in the background. The fix agent downloads failure logs, diagnoses the root cause, creates a fix branch, pushes a repair PR, and merges it. All of this happens on its own branch, parallel to whatever ticket is currently in progress.
- **If the fix cannot be applied:** The fix agent reports Blocked, which triggers a circuit breaker — the orchestrator halts after the current stage completes.

This eliminates the blind spot where CI/CD breaks silently and multiple tickets pile up without deploying. The orchestrator discovers failures within minutes of the merge that caused them, and in most cases fixes them automatically without interrupting the current ticket's pipeline.

The ci-fix-v6 skill can also be invoked standalone (`/ci-fix-v6`) to diagnose and repair CI/CD issues outside of the orchestrator pipeline.

**One fixer at a time.** Several runs share one `main`, so they could all notice the same breakage:
- **"Who's fixing" is simply an open `fix/ci-*` PR.** Before starting, and again before pushing, `ci-fix-v6` checks for one; if it exists it waits for it instead of making a second fix. A fix PR idle for ~30 min (no commits, comments, or queued/running checks) counts as abandoned and is taken over.
- **The merge gate checks `main` first.** A PR that is red while `main` is red isn't at fault — the run waits for `main` to go green instead of patching someone else's breakage inside its ticket. If nobody is fixing `main`, the orchestrator starts the fix itself.
- **Re-test before merge.** If `main` moved since a PR's checks ran, the orchestrator brings the PR up to date with `main` and waits for the checks again before merging.
- **Tests also run on every push to `main`** (template workflows), which is what makes a red `main` visible at all.

### 4.6 Rollback Safety

Before any work begins on a ticket, the orchestrator tags main (`pre-{STORY_ID}`). If a merge corrupts main, the tag provides a clean rollback point. Tags are deleted after successful completion.

### 4.7 Ticket Readiness Gate

Before spawning agents for a ticket, the orchestrator verifies the issue has acceptance criteria and a non-empty description. Tickets that aren't ready are skipped and logged.

### 4.8 Observability

The orchestrator captures per-ticket metrics from each sub-agent:

- **Model per stage** — every sub-agent reports which model it ran on (e.g., `Opus 4.7`, `Sonnet 4.6`) via the `MODEL:` line in its STATUS block. The orchestrator also reports its own model. This enables per-phase cost analysis since different models have different token costs.
- Token usage per stage (refine, implement, review, security, integration test, Playwright)
- Duration per stage
- Number of review iterations
- Test counts

Per-ticket observability comments use a `Phase | Model | Tokens | Duration` table so cost variance by model is visible at a glance. The session summary uses a condensed `{model} / {tokens}` format per cell.

These are reported in the session summary for cost tracking and identifying stories that consumed disproportionate resources (indicating poor scoping or ambiguity).

### 4.9 PRD Amendment Tracking

When developer CONCERNS or integration tester NOTES reveal something that contradicts or is missing from the PRD, the orchestrator captures it in a PRD amendments log. This is reported in the session summary so the PRD remains a living document.

### 4.10 Running Several Orchestrators at Once

Several orchestrators can work one repo at the same time. There is **no coordination layer** between them: each run owns its own tickets, and they share only GitHub (the repo, `main`, the board, the issues) and the CI runner.

**Setup:**
- **One orchestrator per clone.** Each needs its own checkout of the repo — normally one per machine. Several orchestrators for *different* repos on one machine or container is fine, as before.
- The repo's `fast-tests.yml` / `integration-tests.yml` must run on push to `main` as well as on PRs (the template workflows do), so a broken `main` is visible.

**Steps:**
1. **Split the tickets into batches.** Run `plan-batches-v6 #1,#2,…,#15 [N]` (N = number of orchestrators, default 2). It reads every ticket, keeps each dependency chain in one batch (a dependency can never cross runs — nothing orders work between machines), places milestones after their stories, groups tickets that touch the same files, balances by rough size, and prints one launch line per batch. If one round would be lopsided — typically because a few "hub" tickets pull most of the list into one batch — it plans in **rounds**: Round 1 clears the hubs on one machine while the others take independent work, and Round 2 splits the rest evenly (their blockers are closed by then). Start Round 2 only after every Round 1 run has finished; re-run `plan-batches-v6` on the remaining tickets to confirm it. It never writes to GitHub; you review the plan.
2. **Launch one batch per clone:** `./scripts/orchestrate-v6.sh --tickets "#1,#4,#7"`.
3. **Watch:** `./scripts/orchestrate-v6.sh --status` (all runs) or `monitor-v6 <run>`.
4. **Resume** any stopped run with `--run <number>` from the same clone.

**Rules:**
- **A ticket belongs to at most one open run.** The loop and the skill refuse overlapping tickets, including tickets added mid-run through the operator slot.
- **One driver per run** — don't `--run 123` from two places at once.

**What the orchestrator handles for you:** re-testing a PR against the latest `main` before merging, one CI fixer at a time, one automatic merge-conflict attempt, waiting (not halting) when the runner is busy with the other run's jobs, and waiting out the Claude usage limit. **Runners:** one self-hosted runner per repo works — the runs' jobs take turns. Extra runners must be on other machines (the UI tier uses fixed ports); see [self-hosted-runner-setup.md](../developer-tools/self-hosted-runner-setup.md).

Design and decisions: [notes/multi-orchestrator-plan.md](../notes/multi-orchestrator-plan.md).

---

## Phase 5: Session Summary & Review

**Tool:** Human + Claude Code
**Output:** Session report, refined skills and standards

### 5.1 Session Report

The orchestrator produces a comprehensive summary including:

- Completed / Partial / Blocked / Skipped tickets
- Milestones reached and smoke test results
- Observability metrics (tokens, duration, review iterations per ticket)
- PRD amendments discovered during development
- Implementation and integration test PR numbers for audit trail

### 5.2 Triage & Re-entry into Development

After testing the running application, issues and bugs will surface. **Triage is the formal re-entry point back into Phase 4** — it is not optional and not informal. Every bug or unexpected behavior that warrants a fix goes through triage before any code is written.

Use **triage-v6** to investigate and formally capture findings:

- Triage runs in read-only mode — it never writes code
- It investigates symptoms, traces root causes, and produces a GitHub issue as output
- The resulting ticket feeds directly back into the Phase 4 orchestrator on the next development cycle
- Ad-hoc fixes outside of this loop are prohibited — they bypass review gates and break the audit trail

This creates a closed loop: **Phase 5 → triage-v6 → GitHub issue → Phase 4 → merge → Phase 6 → Phase 5**.

For ad-hoc debugging during investigation (not fixing), Claude Code can be used directly to trace behavior, inspect logs, or reproduce issues. The output of that investigation is always a ticket, never a direct code change.

### 5.3 Standards & Skills Iteration

After each development session, feed observations back into the standards and skills as appropriate:

- The shared engineering standards repo (if broadly applicable)
- Project-specific CLAUDE.md or ARCHITECTURE.md
- Skill files (all skills in the standards repo)
- Story-writing standards (if decomposition patterns need adjustment)

---

---

## Phase 6: Deployment & Promotion

**Tool:** GitHub Actions + GitHub Environments
**Input:** Merged code on `main`
**Output:** Code running in Dev, Staging, and eventually Production

### 6.1 Automatic Deploy to Dev

Every merge to `main` automatically triggers the deploy pipeline. No human action required.

```
Build Docker image (tagged {sha}-dev)
  → Push to registry
  → Bicep infrastructure (idempotent)
  → Run migrations
  → Deploy to {project}-dev
  → Smoke tests (health check)
  → ✅ Eligible for Staging promotion
```

Playwright UI tests run on the **self-hosted runner via `workflow_dispatch`** — scoped per story during the pipeline and as a full suite at the end-of-run (CLEANUP) boundary. They are **not** a blocking gate on every PR (that would make every PR pay full browser-stack cost). Post-deploy validation is limited to smoke tests (health checks). If smoke fails, the deploy is broken. Fix via a new commit — do not attempt to patch around the pipeline.

### 6.2 Promote to Staging (manual)

Multiple commits will accumulate in Dev. When ready to cut a release to Staging:

1. Go to the **Actions** tab in GitHub
2. Find the workflow run for the commit you want to promote
3. Click into the run — the `deploy-staging` job will show a **Review deployments** button
4. Click it, approve, and the pipeline resumes — retagging the image and deploying to Staging
5. Smoke tests run automatically against Staging
6. **Cancel any older runs** still waiting approval for Staging — only one run should be pending per environment at a time

### 6.3 Promote to Production (manual + approval gate)

Same flow as Staging promotion, but the `deploy-production` job requires approval from the required reviewers configured in GitHub Environment settings. After approval:

```
Retag image ({sha}-staging → {sha}-prod)
  → Bicep infrastructure (idempotent)
  → Run migrations
  → Deploy to {project}-prod
  → Health check only
```

No Playwright or smoke suite runs against Production — only a health check confirming the app started.

### 6.4 Image Tagging Across Environments

Images are built once and promoted by retagging — never rebuilt:

| Stage | Tag |
|-------|-----|
| Merge to main | `{sha}-dev` |
| Promoted to Staging | `{sha}-staging` |
| Promoted to Production | `{sha}-prod` |

The SHA ties every running environment back to an exact commit at all times.

### 6.5 GitHub Environments Setup (one-time per project)

In **Settings → Environments**, create three environments:

| Environment | Protection Rules |
|-------------|-----------------|
| `dev` | None |
| `staging` | Required reviewers: project owner |
| `production` | Required reviewers: project owner |

See `standards/environments.md` for full pipeline structure, Bicep conventions, smoke test configuration, and the conformance checklist.

---

## Phase 7: Ongoing Project Health

**Tool:** Claude Code + human review
**Cadence:** When returning to a project after time away, or on a regular maintenance cycle

### 7.1 Standards Re-sync

The engineering standards repo evolves. When returning to a project, always re-sync before starting work:

```bash
cd ../TI-Engineering-Standards && git pull --ff-only && cd -
```

The auto-sync protocol in each project's `CLAUDE.md` handles this automatically at session start. If standards have changed since the last session, review the diff and assess whether the project needs conformance updates.

### 7.2 Conformance Check

Point Claude Code at the project and run a conformance audit against `standards/environments.md`. The checklist at the bottom of that document is the authoritative list of what "compliant" means. Common drift areas:

- Integration tests silently excluded from CI
- Auth bypass misconfigured in a non-prod environment
- Playwright env var pointing at a stale URL
- GitHub Environments not configured or missing required reviewers

### 7.3 Dependency Updates

Periodically review NuGet and npm package versions for security updates. This is not automated — it is a deliberate maintenance task. Create a task ticket for dependency updates rather than doing them ad-hoc, so they pass through the standard review pipeline.

### 7.4 Broken Main Recovery

If `main` is ever in a broken state (build fails, tests fail on main):

1. **Try ci-fix-v6 first** — run `/ci-fix-v6` standalone to auto-diagnose and fix. If the orchestrator is running, it will have already attempted this via the background watcher.
2. If ci-fix-v6 reports Blocked (cannot auto-fix), do not merge anything new until main is green.
3. Check the orchestrator's rollback tag (`pre-{STORY_ID}`) if the break was introduced during a development session.
4. Create a triage ticket via triage-v6 for the underlying issue.
5. Fix via a normal branch → PR → review flow, not a direct push to main.

If orchestrators are running, check for an open `fix/ci-*` PR first — one of them may already be fixing it. Don't start a second fix alongside it.

### 7.5 Returning to a Dormant Project

When picking up a project after significant time away:

1. Pull latest `main` and re-sync standards
2. Run unit + integration tests locally — establish a clean baseline before any work
3. Deploy to Dev if it has gone stale — verify the running application matches expectations
4. Review open issues on the board for anything that was In Progress or Waiting/Blocked (an In Progress ticket in an open run's scope belongs to that run — resume the run with `--run`, don't pick the ticket up by hand)
5. Run a conformance check against `standards/environments.md`
6. Only then begin new development work

---

## Key Principles

**Context drift is the primary adversary.** Fresh sub-agents per stage — plus the orchestrator's own stateless relaunch — exist specifically to reset context on every invocation. Each stage gets a fresh context with full standards loaded.

**Vertical slices over horizontal layers.** Stories deliver user-visible functionality. Foundation work is bounded to the minimum needed to unblock the first milestone. Entity lifecycle operations (create, list, view, delete) travel together.

**Milestones are review gates.** Don't let work accumulate too long without human eyes on the running application. Milestone frequency is determined during PRD-to-backlog decomposition based on project complexity.

**PR-based review gates catch what self-review misses.** The engineering review and security review agents operate with independent context, checking the developer's work against standards rather than confirming the developer's own assumptions.

**Trust but verify.** The orchestrator independently verifies build and tests after each stage. Sub-agent status reports are parsed strictly — non-standard responses are treated as Partial.

**Parallelism by separation, not coordination.** Several orchestrators run side by side by owning disjoint tickets in separate clones, not by talking to each other. The only shared signals are ones GitHub already provides: which tickets a run owns, whether `main` is green, and whether a fix PR is open.

**Shared standards, project-specific rules.** The engineering standards repo is the single source of truth across projects. Project-level files (CLAUDE.md, ARCHITECTURE.md) layer on project-specific context. Skills auto-sync from the standards repo.

**Diminishing returns signal phase transitions.** In the PRD convergence loop, the shift from pertinent suggestions to marginal minutiae is the signal to stop refining and start building.

**Observability informs improvement.** Per-ticket token and duration metrics reveal which stories were poorly scoped, which review gates catch the most issues, and where the pipeline can be optimized.

---

## Skills Reference

All skills work under `standards/engineering-discipline.md` (ED-1..ED-5); the ticket-producing skills end with an ED-5 cold read — a fresh subagent reads the saved ticket and reports what's missing (interactive mode only).

### Story Creation & Backlog Maintenance
| Skill | Purpose |
|-------|---------|
| prd-to-backlog-v6 | Bulk PRD decomposition into milestoned backlog; nominates the repo-wide critical-path journeys |
| add-story-v6 | Incremental story creation for existing projects; non-interactive mode for callers |
| reconcile-backlog-v6 | Reconcile PRD version changes against an existing backlog and codebase (classifications grounded in source) |

### Development Pipeline (per ticket, managed by orchestrate-v6)
| Skill | Purpose |
|-------|---------|
| refine-story-v6 | Enrich issue into a behavior-first tier table (one tier per behavior); adversarial self-review in all modes |
| implement-ticket-v6 | Implement code + Unit/Contract tests, create PR. Supports fix mode for review feedback |
| engineering-review-v6 | Review PR against standards + TR rules (two-way) and ED (ungrounded-claim check). Implementation, integration-test, and ui-test modes |
| security-review-v6 | OWASP Top 10 + infrastructure security review (auto-detects Bicep, Docker, GitHub Actions) |
| ci-fix-v6 | Monitor GitHub Actions and auto-fix CI/CD failures, one fixer at a time across runs. Background side-channel after each merge; standalone for ad-hoc repair |
| integration-test-v6 | Write integration tests, create PR. Supports fix mode |
| ui-test-v6 | Write Playwright UI tests, create PR. Supports fix mode |
| orchestrate-v6 | Mode-switching pipeline orchestrator (WORKING/CLEANUP) bound to one explicit run, relaunched by the dumb loop; merge gate, per-run tracking issue, TR gate-audit, observability. Entrypoint `scripts/orchestrate-v6.sh` |
| monitor-v6 | Read-only live narrator for orchestration runs — lists all open runs, or narrates one (stage/PR/CLEANUP events, stall flags); never writes |
| plan-batches-v6 | Split a ticket list into dependency-safe batches for parallel orchestrator runs; read-only, prints one `orchestrate-v6.sh --tickets` line per batch |

### Investigation, Triage & Conformance
| Skill | Purpose |
|-------|---------|
| triage-v6 | Interactive investigation and bug triage — evidence-first runtime diagnosis (pull the real exception before theorizing); never writes code, output is always a ticket |
| conformance-v6 | Audit a project against TI Engineering Standards — informational only, produces a gap report |

### Standards
| File | Purpose |
|------|---------|
| story-writing-standards.md | Story structure, vertical slices, milestones, sizing, acceptance criteria |
| project-tracking.md | Board structure, labels, custom fields, issue types |
| environments.md | Environment definitions, Bicep conventions, pipeline structure, promotion flow, conformance checklist |
| testing.md | Four-tier test model (Unit/Contract/Integration/UI), TR-1..TR-11 rules, CI/CD trigger model, critical-path |
| engineering-discipline.md | How to work: grounded claims + adversarial self-review + cold read (ED-1..ED-5) |
| git-workflow.md | Branching, commits, PR process, deployment strategy |
| architecture.md | Dependency inversion, interface-first design, project layering |
| api-design.md | Endpoint return types, DTOs, serialization, naming conventions |
| configuration.md | Options pattern, config layering, environment variables, feature flags |
| database.md | SQL Server conventions, primary keys, timestamps, migrations |
| dotnet.md | .NET runtime, Minimal APIs, Dapper, DbUp, DI conventions |
| error-handling.md | Error responses, HTTP status codes, validation, pagination |
| logging.md | Serilog, log levels, correlation IDs, health checks |
| security.md | Auth, input validation, CORS, rate limiting, secrets |
| documentation.md | XML docs, architecture docs |
| ui.md | Blazor WebAssembly, MudBlazor, frontend patterns |
