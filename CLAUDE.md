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
   After the first copy, replace `{ProjectName}` / `{PROJECT}` / ports per `templates/workflows/README.md`, then run `developer-tools/setup-branch-protection.sh` once to make `fast-tests` + `integration-tests` required checks.
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

The seven **pipeline** skills are now **v5** (four-tier model + TR enforcement — see [standards/testing.md](standards/testing.md)) — the six test-pipeline skills plus the mode-switching `orchestrate-v5`. The other skills are unchanged at v4.

| Skill | Purpose |
|-------|---------|
| [skills/prd-to-backlog-v4/SKILL.md](skills/prd-to-backlog-v4/SKILL.md) | Decompose a PRD into a milestoned backlog of vertical-slice stories |
| [skills/add-story-v4/SKILL.md](skills/add-story-v4/SKILL.md) | Conversationally create incremental stories for an existing project |
| [skills/refine-story-v5](skills/refine-story-v5/SKILL.md) | Refine a GitHub issue into an implementation-ready spec with a behavior-first test plan (one tier per behavior, critical journeys declared) |
| [skills/implement-ticket-v5](skills/implement-ticket-v5/SKILL.md) | Implement a single ticket — writes Unit + Contract tests per the tier table (no logic in Contract). Pushes branch, creates PR. Supports FIX mode |
| [skills/engineering-review-v5](skills/engineering-review-v5/SKILL.md) | Review a PR against standards. Three modes; enforces tiers two-way (missing + redundant), counts critical-path, emits the TR checklist grid |
| [skills/security-review-v4](skills/security-review-v4/SKILL.md) | OWASP Top 10 + infrastructure security review for PRs |
| [skills/integration-test-v5](skills/integration-test-v5/SKILL.md) | Write integration tests for a merged implementation — real-infra behavior only (no contract re-assertion). Creates PR. Supports FIX mode |
| [skills/ui-test-v5](skills/ui-test-v5/SKILL.md) | Write Playwright UI tests — journey-scoped, conditional, critical-path tagged. Runs via scoped `workflow_dispatch` on the self-hosted runner. Creates PR. Supports FIX mode |
| [skills/orchestrate-v5/SKILL.md](skills/orchestrate-v5/SKILL.md) | Mode-switching pipeline orchestrator (WORKING/CLEANUP) built for relaunch by the dumb loop; per-run tracking issue, board-driven queue, TR gate-audit, observability |
| [skills/ci-fix-v5](skills/ci-fix-v5/SKILL.md) | Monitor GitHub Actions and auto-fix CI/CD failures — fix the code, not the test. Background side-channel for orchestrator; standalone for ad-hoc repair |
| [skills/reconcile-backlog-v4](skills/reconcile-backlog-v4/SKILL.md) | Reconcile PRD version changes against an existing backlog and codebase. Diffs, classifies, and executes creates/updates |
| [skills/triage-v4](skills/triage-v4/SKILL.md) | Interactive investigation and bug triage — never writes code, output is always a ticket |
| [skills/conformance-v4](skills/conformance-v4/SKILL.md) | Audit a project against TI Engineering Standards — informational only, produces a gap report |

> **Note:** v1, v2, and v3 skills remain in `skills/archive/` for historical reference but are no longer actively maintained.
>
> **v4 → v5 transition:** the v4 copies of the seven rebuilt skills (`refine-story-v4`, `implement-ticket-v4`, `integration-test-v4`, `ui-test-v4`, `engineering-review-v4`, `ci-fix-v4`, `orchestrate-v4`) **remain in `skills/`** and are still synced — v4 keeps running until v5 is proven on the pilot (Phase 5). Only then do the v4 copies move to `skills/archive/`.

---

## Templates

| File | Purpose |
|------|---------|
| [templates/CLAUDE-project.md](templates/CLAUDE-project.md) | Template CLAUDE.md for new projects — copy and fill in project-specific sections |

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
