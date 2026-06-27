# TI Engineering Standards

This repository is the single source of truth for engineering standards, conventions, and patterns used across all TI projects. It is consumed primarily by Claude Code but is also human-readable.

---

## Auto-Sync Protocol (for Claude Code)

When starting a session on **any project**, follow this protocol:

1. **Check for this repo** as a sibling directory: `../TI-Engineering-Standards/`
2. **If not found**, clone it: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
3. **If found**, pull latest: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
4. **Read this file** and the referenced standards files below before starting work.
5. **Sync skills**: Copy shared skills into the project (skipping any that already exist locally):
   ```bash
   mkdir -p .claude/skills
   for skill_dir in ../TI-Engineering-Standards/skills/*/; do
     skill_name=$(basename "$skill_dir")
     # Skip archive directory
     if [ "$skill_name" = "archive" ]; then continue; fi
     if [ ! -d ".claude/skills/$skill_name" ]; then
       cp -r "$skill_dir" ".claude/skills/$skill_name"
     fi
   done
   ```
   Local skills in `.claude/skills/` take precedence — if a project has a customized version, it won't be overwritten.
6. **Sync CI workflows** (v5): Copy the template workflows into the project's `.github/workflows/` (skipping any the project already has), then fill in the placeholder tokens once and commit. Same precedence rule as skills — a customized local copy is never overwritten:
   ```bash
   mkdir -p .github/workflows
   for wf in ../TI-Engineering-Standards/templates/workflows/*.yml; do
     wf_name=$(basename "$wf")
     if [ ! -f ".github/workflows/$wf_name" ]; then
       cp "$wf" ".github/workflows/$wf_name"
     fi
   done
   ```
   After the first copy, replace `{ProjectName}` / `{PROJECT}` / ports per `templates/workflows/README.md`. The merge gate is enforced by `orchestrate-v5` (it won't merge a PR whose `fast-tests`/`integration-tests` checks are red) — no branch-protection setup needed.
7. **Vendor the orchestration entrypoint** (v5): Copy the thin `scripts/orchestrate.sh` wrapper into the project (skip-if-exists — it's stable and self-updates the canonical driver each run). Same precedence rule as skills/workflows:
   ```bash
   mkdir -p scripts
   for s in ../TI-Engineering-Standards/templates/scripts/*.sh; do
     s_name=$(basename "$s")
     if [ ! -f "scripts/$s_name" ]; then
       cp "$s" "scripts/$s_name" && chmod +x "scripts/$s_name"
     fi
   done
   ```
   This is the entrypoint for long-haul autonomous runs (`./scripts/orchestrate.sh --tickets "#7,#8"`). A single interactive ticket does **not** need it — that's `orchestrate-v5 supervised #<issue>` invoked directly.
8. **Verify git hooks path**: If the project has a `.githooks/` directory, ensure git is configured to use it:
   ```bash
   if [ -d ".githooks" ]; then
     current=$(git config core.hooksPath 2>/dev/null)
     if [ "$current" != ".githooks" ]; then
       git config core.hooksPath .githooks
     fi
   fi
   ```

When the user asks to update a standard:
- Update the relevant file in this repo
- Apply the change to the current project if applicable
- Commit the change to this repo

---

## Standards Index

Read each of these files — they contain the engineering rules and conventions that apply to all projects:

| File | Scope |
|------|-------|
| [standards/api-design.md](standards/api-design.md) | Endpoint return types, DTOs, serialization, naming conventions |
| [standards/api-integration.md](standards/api-integration.md) | External API spec-first rule, `docs/api-specs/` convention, model-building rules |
| [standards/architecture.md](standards/architecture.md) | Dependency inversion, interface-first design, project layering |
| [standards/configuration.md](standards/configuration.md) | Options pattern, config layering, environment variables |
| [standards/database.md](standards/database.md) | SQL Server conventions, primary keys, timestamps, migrations |
| [standards/documentation.md](standards/documentation.md) | XML docs, architecture docs (dual-format md + draw.io) |
| [standards/dotnet.md](standards/dotnet.md) | .NET runtime, Minimal APIs, Dapper, DbUp, DI conventions |
| [standards/engineering-discipline.md](standards/engineering-discipline.md) | How to work: grounded claims + adversarial self-review (ED-1..ED-4) |
| [standards/error-handling.md](standards/error-handling.md) | Error responses, HTTP status codes, validation, pagination |
| [standards/git-workflow.md](standards/git-workflow.md) | Branching, commits, PR process |
| [standards/logging.md](standards/logging.md) | Serilog, log levels, correlation IDs, health checks |
| [standards/project-tracking.md](standards/project-tracking.md) | GitHub Projects v2 workflow, issue types, board structure |
| [standards/security.md](standards/security.md) | Auth, input validation, CORS, rate limiting, secrets |
| [standards/testing.md](standards/testing.md) | Testing philosophy, frameworks, naming, fakes, CI/CD tiers |
| [standards/environments.md](standards/environments.md) | Environment definitions, Bicep conventions, pipeline structure, promotion flow |
| [standards/ui.md](standards/ui.md) | Blazor WebAssembly, MudBlazor, frontend patterns |
| [standards/story-writing-standards.md](standards/story-writing-standards.md) | Story structure, vertical slices, milestones, sizing, acceptance criteria |

---

## Skills (Claude Code)

Shared skills live in `skills/` and are auto-copied to each project's `.claude/skills/` during sync. Projects can override any skill by placing a customized version in their own `.claude/skills/` directory.

**All pipeline and authoring skills are now v5** (four-tier model + TR enforcement — see [standards/testing.md](standards/testing.md)) and apply the grounded + adversarial **engineering discipline** (ED-1..ED-4 — see [standards/engineering-discipline.md](standards/engineering-discipline.md)). The ticket-producing skills end with a three-part contribution step (what we missed / should consider / I'd add).

| Skill | Purpose |
|-------|---------|
| [skills/prd-to-backlog-v5/SKILL.md](skills/prd-to-backlog-v5/SKILL.md) | Decompose a PRD into a milestoned backlog of vertical-slice stories; nominates the repo-wide critical-path journeys; three-part contribution |
| [skills/add-story-v5/SKILL.md](skills/add-story-v5/SKILL.md) | Conversationally create incremental stories for an existing project; three-part contribution; non-interactive mode for callers |
| [skills/refine-story-v5](skills/refine-story-v5/SKILL.md) | Refine a GitHub issue into an implementation-ready spec with a behavior-first test plan (one tier per behavior, critical journeys declared); adversarial self-review (ED-2) in all modes |
| [skills/implement-ticket-v5](skills/implement-ticket-v5/SKILL.md) | Implement a single ticket — writes Unit + Contract tests per the tier table (no logic in Contract). Pushes branch, creates PR. Supports FIX mode |
| [skills/engineering-review-v5](skills/engineering-review-v5/SKILL.md) | Review a PR against standards. Three modes; enforces tiers two-way (missing + redundant), counts critical-path, emits the TR checklist grid |
| [skills/security-review-v5](skills/security-review-v5/SKILL.md) | OWASP Top 10 + infrastructure security review for PRs; fail-open / silent-error check |
| [skills/integration-test-v5](skills/integration-test-v5/SKILL.md) | Write integration tests for a merged implementation — real-infra behavior only (no contract re-assertion). Creates PR. Supports FIX mode |
| [skills/ui-test-v5](skills/ui-test-v5/SKILL.md) | Write Playwright UI tests — journey-scoped, conditional, critical-path tagged. Runs via scoped `workflow_dispatch` on the self-hosted runner. Creates PR. Supports FIX mode |
| [skills/orchestrate-v5/SKILL.md](skills/orchestrate-v5/SKILL.md) | Mode-switching pipeline orchestrator (WORKING/CLEANUP) built for relaunch by the dumb loop; per-run tracking issue, board-driven queue, TR gate-audit, observability |
| [skills/ci-fix-v5](skills/ci-fix-v5/SKILL.md) | Monitor GitHub Actions and auto-fix CI/CD failures — fix the code, not the test. Background side-channel for orchestrator; standalone for ad-hoc repair |
| [skills/monitor-v5](skills/monitor-v5/SKILL.md) | Read-only live narrator for an orchestration run — interpretive play-by-play off the tracking issue + work tickets + CI (stage/PR/CLEANUP events, stall flags). Observe-only companion to the dumb-driver heartbeat; never writes |
| [skills/reconcile-backlog-v5](skills/reconcile-backlog-v5/SKILL.md) | Reconcile PRD version changes against an existing backlog and codebase. Diffs, classifies (grounded in source), and executes via add-story-v5 + refine-story-v5 |
| [skills/triage-v5](skills/triage-v5/SKILL.md) | Interactive investigation and bug triage — evidence-first runtime diagnosis (pull the real exception before theorizing), never writes code, output is always a ticket |
| [skills/conformance-v5](skills/conformance-v5/SKILL.md) | Audit a project against TI Engineering Standards incl. the v5 four-tier test model — informational only, produces a gap report |

> **Note:** v1–v4 skills remain in `skills/archive/` for historical reference but are no longer actively maintained or synced (the auto-sync protocol skips `archive/`).
>
> **v4 → v5 transition — COMPLETE (2026-06-27).** v5 is proven on the pilot; all thirteen v4 skills have been moved to `skills/archive/`. v5 is the only synced generation. The round-out (the six authoring/audit skills plus the ED-discipline patches to `refine-story-v5` / `implement-ticket-v5` / `engineering-review-v5`) is tracked in [notes/v5-round-out-plan.md](notes/v5-round-out-plan.md); the full build is in [notes/v5-implementation-plan.md](notes/v5-implementation-plan.md).

---

## Templates

| File | Purpose |
|------|---------|
| [templates/CLAUDE-project.md](templates/CLAUDE-project.md) | Template CLAUDE.md for new projects — copy and fill in project-specific sections |
| [templates/workflows/](templates/workflows/) | CI workflow templates (fast / integration / ui tests) — copied into each project's `.github/workflows/` |
| [templates/scripts/orchestrate.sh](templates/scripts/orchestrate.sh) | Thin orchestration entrypoint wrapper projects vendor as `scripts/orchestrate.sh` |

---

## Process & Workflow

The end-to-end agentic development process (discovery → PRD → backlog → orchestrated pipeline → deploy) and the tooling that runs it:

| Path | Purpose |
|------|---------|
| [workflow/agentic-development-workflow.md](workflow/agentic-development-workflow.md) | Master process doc — all phases, the v5 pipeline, mode-switching orchestrator, four-tier testing |
| [workflow/README.md](workflow/README.md) | Workflow overview + per-ticket v5 pipeline at a glance |
| [workflow/screen-inventory-template.md](workflow/screen-inventory-template.md) | Screen Inventory artifact template (per-surface UI-scope decisions) |
| [workflow/workflow-diagram.html](workflow/workflow-diagram.html) | Interactive visual diagram of the pipeline |
| [developer-tools/self-hosted-runner-setup.md](developer-tools/self-hosted-runner-setup.md) | Provision the self-hosted runner that executes the v5 test workflows |
| [developer-tools/](developer-tools/) | Operator tooling — the dumb loop driver, runner/hooks/VM setup guides |

---

## How To Work (Universal)

These habits apply to **every task on every project** — see [standards/engineering-discipline.md](standards/engineering-discipline.md) for the full rules (ED-1..ED-4):

- **Confirm, don't guess (ED-1).** Trace any claim about how the code behaves to an observed `file:line` before writing it as fact. A plausible model is a hypothesis, not a fact.
- **Falsify, don't rubber-stamp (ED-2).** Treat your own just-produced spec/ticket/PR as a suspect — try to break each claim before finalizing it.
- **Label hypotheses (ED-3).** An ungrounded claim is written as a hypothesis with the evidence needed to settle it, never as established fact.
- **Surface scope forks (ED-4).** If the chosen approach changes blast radius or which test tiers apply, say so — never let a ticket hide it.
- **Contribute, last (ED-5).** When producing/refining a ticket, volunteer your own take — *what we missed / should consider / I'd add* — automatically, as the final, non-skippable step. It must be the wrap-up, or it gets skipped.

---

## Things NOT To Do (Universal)

These rules apply to **every project**, no exceptions:

- Do NOT use Entity Framework or any ORM other than Dapper
- Do NOT use MVC controllers — Minimal APIs only
- Do NOT use mocking frameworks (Moq, NSubstitute, FakeItEasy) — hand-rolled fakes only
- Do NOT use GUID primary keys — INT IDENTITY everywhere
- Do NOT add third-party IoC containers — built-in DI only
- Do NOT create down migrations — DbUp forward-only
- Do NOT use `!` in passwords or secrets — bash interprets `!` as history expansion, making them unusable in shell commands
- Do NOT put cloud SDK references in Domain or any service project except Infrastructure
- Do NOT add `Co-Authored-By` trailers to git commit messages
- Do NOT exercise business logic through the Contract tier (host + fakes) — it asserts the HTTP contract only; logic scenarios go in Unit tests (see [standards/testing.md](standards/testing.md) → Test Tiers)
