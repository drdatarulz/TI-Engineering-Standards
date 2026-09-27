# Agentic Development Workflow

This folder contains the end-to-end workflow for 100% agentic software development using Claude, GitHub Projects, and a **mode-switching orchestrator** (relaunched by a dumb loop) running a PR-based pipeline with review gates and milestones.

## Contents

| File | Description |
|------|-------------|
| [agentic-development-workflow.md](agentic-development-workflow.md) | Full written guide covering all phases from discovery through deployment |
| [workflow-diagram.html](workflow-diagram.html) | Interactive visual diagram of the pipeline |
| [screen-inventory-template.md](screen-inventory-template.md) | Reusable template for the Screen Inventory artifact (Phase 2) |

## Workflow Diagram

**[View the interactive workflow diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

## Phases at a Glance

1. **Discovery & Capture** — Record freeform discussions with Otter.ai
2. **PRD Refinement** — Claude Web synthesizes transcript into PRD, Screen Inventory, and Decisions Log
3. **Project Bootstrap** — Claude Code creates repo, board, and milestoned backlog (`prd-to-backlog-v6`)
4. **Orchestrated Development** — PR-based pipeline: Refine → Implement → Engineering Review → Security Review → Integration Tests → Review → UI Tests → Review → Merge, driven by one or more `orchestrate-v6` runs — several can work one repo in parallel, each in its own clone on its own batch of tickets (`plan-batches-v6` splits the list)
5. **Session Summary & Review** — Observability metrics, PRD amendments, debug and iterate
6. **Deployment & Promotion** — Dev auto-deploy, manual promotion to Staging and Production
7. **Ongoing Project Health** — Standards re-sync, conformance checks, dependency updates

## Pipeline Per Ticket

The four-tier test model (Unit / Contract / Integration / UI) governs what runs where. Unit + Contract are the **fast tier** (no Docker); Integration uses real infra; **UI runs on the self-hosted runner via `workflow_dispatch`, scoped per story — not a blocking gate on every PR.** Each producer stage signs off its TR rows; the reviewer re-checks them adversarially. See [standards/testing.md](../standards/testing.md).

```
1.   REFINE ──────────── refine-story-v6 (behavior-first tier table; adversarial self-review)
2.   IMPLEMENT ───────── implement-ticket-v6 → PR #1 (Unit + Contract tests)
3.   ENGINEERING REVIEW ─ engineering-review-v6 (↻ max 3 fix iterations)
3.5. SECURITY REVIEW ──── security-review-v6 (OWASP Top 10 + infrastructure) → merge PR #1
4.   INTEGRATION TESTS ── integration-test-v6 → PR #2 (real-infra behavior only)
5.   ENGINEERING REVIEW ─ engineering-review-v6 (↻ max 3 fix iterations) → merge PR #2
6.   UI TESTS ─────────── ui-test-v6 → PR #3 (journey-scoped, runner via workflow_dispatch)
7.   ENGINEERING REVIEW ─ engineering-review-v6 (↻ max 3 fix iterations) → merge PR #3
8.   CLOSE ───────────── acceptance criteria → close issue (orchestrator owns the close)
     ⬥ MILESTONE GATE ── hard stop, smoke test, human approval
```

The orchestrator is **stateless and relaunched** by the dumb loop: it self-selects **WORKING** (process up to N ready tickets) or **CLEANUP** (end-of-run oversight) from durable state on a per-run tracking issue, so it survives crashes and avoids context rot. CI failures are repaired in the background by `ci-fix-v6` after each merge; `monitor-v6` narrates the run read-only.

Runs are always explicit: `./scripts/orchestrate-v6.sh --tickets "#7,#8"` starts one, `--run N` continues or resumes it, `--status` lists them. A ticket belongs to at most one open run. Before every merge the orchestrator re-tests the PR against the latest `main`; a red `main` goes to one CI fixer at a time across all runs; a merge conflict gets one automatic resolve attempt before halting; and a Claude usage-limit hit is waited out rather than treated as a crash.

## Working discipline

Every skill works under [standards/engineering-discipline.md](../standards/engineering-discipline.md) (ED-1..ED-5): confirm claims against source, adversarially self-review before finalizing. The ticket-producing skills end with an ED-5 cold read — a fresh subagent reads the saved ticket, with no access to the author's reasoning, and reports what's missing.

## Related

- [Skills](../skills/) — The Claude Code skills that power Phases 3–5
- [Standards](../standards/) — Engineering standards including `testing.md`, `engineering-discipline.md`, and `story-writing-standards.md`
- [Templates](../templates/) — Project CLAUDE.md template, CI workflow templates, and the `orchestrate-v6.sh` wrapper
- [notes/multi-orchestrator-plan.md](../notes/multi-orchestrator-plan.md) — design and decisions behind parallel runs
