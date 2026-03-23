# Agentic Development Workflow

## Overview

This document defines the end-to-end workflow for 100% agentic software development using Claude (web interface and Claude Code), GitHub Projects, and a supervisor/worker orchestration pattern with PR-based review gates. The workflow covers everything from initial brainstorming through deployed, tested, reviewed code.

The core philosophy: separate concerns between human-driven discovery, AI-assisted specification, and fully orchestrated development — with clean context boundaries at each transition to prevent drift, and milestone-based review gates to ensure human validation at meaningful intervals.

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

### 3.3 Backlog Generation (prd-to-backlog-v4)

Use the `prd-to-backlog-v4` skill to decompose the PRD into a milestoned backlog. The skill:

1. Reads the PRD, Screen Inventory, Decisions Log, and ARCHITECTURE.md
2. Identifies foundation work (kept minimal — only what can't be part of a vertical slice)
3. Groups screens and capabilities into milestones per `standards/story-writing-standards.md`
4. Decomposes into vertical-slice stories sized by entity lifecycle
5. Presents the full plan for human review before creating any issues
6. Creates GitHub issues with proper labels, custom fields, and milestone markers

Stories follow the conventions in `standards/story-writing-standards.md`: vertical slices preferred, entity lifecycle grouping (create + list + view + delete = one story), capability-based splitting for larger features.

### 3.4 Backlog Review

After the skill generates stories, review them:

- Do story titles map back to PRD requirements?
- Is the decomposition at the right granularity?
- Are there gaps — PRD requirements with no corresponding story?
- Are milestone groupings sensible?

### 3.5 Incremental Story Additions (add-story-v4)

When adding stories mid-project (not during initial PRD decomposition), use `add-story-v4`. The skill:

1. Reviews the existing backlog and codebase
2. Works conversationally to understand what you want to add
3. Proposes stories following the same standards
4. Determines milestone placement
5. Creates issues after human approval

### 3.6 Local Development Setup

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

**Tool:** Claude Code with orchestrate-v4
**Input:** Backlog tickets (refined automatically by the orchestrator as Stage 1)
**Output:** Implemented, reviewed, tested, merged code

### 4.1 Architecture: PR-Based Pipeline with Review Gates

The v3 pipeline uses pull requests as the unit of work with automated engineering and security review gates. The orchestrator spawns fresh sub-agents for each stage, preventing context drift.

```
Per Ticket:
1. REFINE ──────────── refine-story-v4 (enriches issue spec)
2. IMPLEMENT ───────── implement-ticket-v4 (creates PR #1)
3. ENGINEERING REVIEW ─ engineering-review-v4 (standards check)
   └─ Loop: reviewer ↔ implementer fix mode (max 3 iterations)
4. SECURITY REVIEW ──── security-review-v4 (OWASP Top 10)
   └─ Loop: reviewer ↔ implementer fix mode (max 2 iterations)
   └─ On pass → merge PR #1
5. INTEGRATION TESTS ── integration-test-v4 (creates PR #2)
6. ENGINEERING REVIEW ─ engineering-review-v4 (integration test quality)
   └─ Loop: reviewer ↔ test-writer fix mode (max 3 iterations)
   └─ On approve → merge PR #2
7. UI TESTS ─── ui-test-v4 (creates PR #3)
8. ENGINEERING REVIEW ─ engineering-review-v4 (ui test quality)
   └─ Loop: reviewer ↔ test-writer fix mode (max 3 iterations)
   └─ On approve → merge PR #3
9. CLOSE ───────────── check acceptance criteria, close issue
```

### 4.2 Milestone Gates

When the orchestrator encounters an issue with the `milestone` label, it stops regardless of operating mode (supervised or autonomous):

1. Runs the smoke test checklist from the milestone issue body
2. Reports results and lists stories completed in this milestone
3. Waits for human approval before continuing

This ensures the developer can launch the application, interact with it, and verify it matches expectations before more work proceeds. Milestones map to screen inventory groupings — each milestone delivers a coherent set of user-visible functionality.

### 4.3 Operating Modes

- **Supervised**: hard stop between each ticket. Used when iterating on skills, early in a project, or when close oversight is desired.
- **Autonomous**: continues between tickets automatically, stopping only at milestones, circuit breakers, or completion.

### 4.4 Circuit Breakers

Even in autonomous mode, the orchestrator halts entirely if:

- 3 consecutive tickets are Blocked or Partial — something systemic is wrong
- A PR merge conflict occurs — needs human judgment
- Build fails on main after a merge — main is corrupted (rollback tag available)
- 3 review iterations exhausted on 2 consecutive tickets — pattern problem

### 4.5 Rollback Safety

Before any work begins on a ticket, the orchestrator tags main (`pre-{STORY_ID}`). If a merge corrupts main, the tag provides a clean rollback point. Tags are deleted after successful completion.

### 4.6 Ticket Readiness Gate

Before spawning agents for a ticket, the orchestrator verifies the issue has acceptance criteria and a non-empty description. Tickets that aren't ready are skipped and logged.

### 4.7 Observability

The orchestrator captures per-ticket metrics from each sub-agent:

- Token usage per stage (refine, implement, review, security, integration test)
- Duration per stage
- Number of review iterations
- Test counts

These are reported in the session summary for cost tracking and identifying stories that consumed disproportionate resources (indicating poor scoping or ambiguity).

### 4.8 PRD Amendment Tracking

When developer CONCERNS or integration tester NOTES reveal something that contradicts or is missing from the PRD, the orchestrator captures it in a PRD amendments log. This is reported in the session summary so the PRD remains a living document.

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

Use **triage-v4** to investigate and formally capture findings:

- Triage runs in read-only mode — it never writes code
- It investigates symptoms, traces root causes, and produces a GitHub issue as output
- The resulting ticket feeds directly back into the Phase 4 orchestrator on the next development cycle
- Ad-hoc fixes outside of this loop are prohibited — they bypass review gates and break the audit trail

This creates a closed loop: **Phase 5 → triage-v4 → GitHub issue → Phase 4 → merge → Phase 6 → Phase 5**.

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
Build → Unit + Integration tests
  → Build Docker image (tagged {sha}-dev)
  → Push to registry
  → Bicep infrastructure (idempotent)
  → Run migrations
  → Deploy to {project}-dev
  → Smoke tests → UI tests
  → ✅ Eligible for Staging promotion
```

If smoke or UI tests fail, the deploy is broken. Fix via a new commit — do not attempt to patch around the pipeline.

### 6.2 Promote to Staging (manual)

Multiple commits will accumulate in Dev. When ready to cut a release to Staging:

1. Go to the **Actions** tab in GitHub
2. Find the workflow run for the commit you want to promote
3. Click into the run — the `deploy-staging` job will show a **Review deployments** button
4. Click it, approve, and the pipeline resumes — retagging the image and deploying to Staging
5. Smoke + UI tests run automatically against Staging
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

1. Do not merge anything new until main is green
2. Check the orchestrator's rollback tag (`pre-{STORY_ID}`) if the break was introduced during a development session
3. Create a triage ticket via triage-v4 — even for pipeline breaks
4. Fix via a normal branch → PR → review flow, not a direct push to main

### 7.5 Returning to a Dormant Project

When picking up a project after significant time away:

1. Pull latest `main` and re-sync standards
2. Run unit + integration tests locally — establish a clean baseline before any work
3. Deploy to Dev if it has gone stale — verify the running application matches expectations
4. Review open issues on the board for anything that was In Progress or Waiting/Blocked
5. Run a conformance check against `standards/environments.md`
6. Only then begin new development work

---

## Key Principles

**Context drift is the primary adversary.** The supervisor/worker pattern exists specifically to reset context on every sub-agent invocation. Each stage gets a fresh context with full standards loaded.

**Vertical slices over horizontal layers.** Stories deliver user-visible functionality. Foundation work is bounded to the minimum needed to unblock the first milestone. Entity lifecycle operations (create, list, view, delete) travel together.

**Milestones are review gates.** Don't let work accumulate too long without human eyes on the running application. Milestone frequency is determined during PRD-to-backlog decomposition based on project complexity.

**PR-based review gates catch what self-review misses.** The engineering review and security review agents operate with independent context, checking the developer's work against standards rather than confirming the developer's own assumptions.

**Trust but verify.** The orchestrator independently verifies build and tests after each stage. Sub-agent status reports are parsed strictly — non-standard responses are treated as Partial.

**Shared standards, project-specific rules.** The engineering standards repo is the single source of truth across projects. Project-level files (CLAUDE.md, ARCHITECTURE.md) layer on project-specific context. Skills auto-sync from the standards repo.

**Diminishing returns signal phase transitions.** In the PRD convergence loop, the shift from pertinent suggestions to marginal minutiae is the signal to stop refining and start building.

**Observability informs improvement.** Per-ticket token and duration metrics reveal which stories were poorly scoped, which review gates catch the most issues, and where the pipeline can be optimized.

---

## Skills Reference (v3)

### Story Creation
| Skill | Purpose |
|-------|---------|
| prd-to-backlog-v4 | Bulk PRD decomposition into milestoned backlog |
| add-story-v4 | Incremental story creation for existing projects |

### Development Pipeline (per ticket, managed by orchestrate-v4)
| Skill | Purpose |
|-------|---------|
| refine-story-v4 | Enrich issue with technical detail and acceptance criteria |
| implement-ticket-v4 | Implement code, create PR. Supports fix mode for review feedback |
| engineering-review-v4 | Review PR against standards. Implementation, integration-test, and ui-test modes |
| security-review-v4 | OWASP Top 10 security analysis with attack vector requirements |
| integration-test-v4 | Write integration tests, create PR. Supports fix mode |
| ui-test-v4 | Write Playwright UI tests, create PR. Supports fix mode |
| orchestrate-v4 | Pipeline orchestrator with milestones, review loops, and observability |

### Investigation, Triage & Conformance
| Skill | Purpose |
|-------|---------|
| triage-v4 | Interactive investigation and bug triage — never writes code, output is always a ticket |
| conformance-v4 | Audit a project against TI Engineering Standards — informational only, produces a gap report |

### Standards
| File | Purpose |
|------|---------|
| story-writing-standards.md | Story structure, vertical slices, milestones, sizing, acceptance criteria |
| project-tracking.md | Board structure, labels, custom fields, issue types |
| environments.md | Environment definitions, Bicep conventions, pipeline structure, promotion flow, conformance checklist |
| testing.md | Testing philosophy, frameworks, tiers, CI/CD gates, pre-existing failure rules |
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
