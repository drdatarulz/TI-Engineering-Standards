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
3. **Project Bootstrap** — Claude Code creates repo, board, and milestoned backlog (`prd-to-backlog-v5`)
4. **Orchestrated Development** — PR-based pipeline: Refine → Implement → Engineering Review → Security Review → Integration Tests → Review → UI Tests → Review → Merge, driven by `orchestrate-v5`
5. **Session Summary & Review** — Observability metrics, PRD amendments, debug and iterate
6. **Deployment & Promotion** — Dev auto-deploy, manual promotion to Staging and Production
7. **Ongoing Project Health** — Standards re-sync, conformance checks, dependency updates

## v5 Pipeline Per Ticket

The four-tier test model (Unit / Contract / Integration / UI) governs what runs where. Unit + Contract are the **fast tier** (no Docker); Integration uses real infra; **UI runs on the self-hosted runner via `workflow_dispatch`, scoped per story — not a blocking gate on every PR.** Each producer stage signs off its TR rows; the reviewer re-checks them adversarially. See [standards/testing.md](../standards/testing.md).

```
1.   REFINE ──────────── refine-story-v5 (behavior-first tier table; adversarial self-review)
2.   IMPLEMENT ───────── implement-ticket-v5 → PR #1 (Unit + Contract tests)
3.   ENGINEERING REVIEW ─ engineering-review-v5 (↻ max 3 fix iterations)
3.5. SECURITY REVIEW ──── security-review-v5 (OWASP Top 10 + infrastructure) → merge PR #1
4.   INTEGRATION TESTS ── integration-test-v5 → PR #2 (real-infra behavior only)
5.   ENGINEERING REVIEW ─ engineering-review-v5 (↻ max 3 fix iterations) → merge PR #2
6.   UI TESTS ─────────── ui-test-v5 → PR #3 (journey-scoped, runner via workflow_dispatch)
7.   ENGINEERING REVIEW ─ engineering-review-v5 (↻ max 3 fix iterations) → merge PR #3
8.   CLOSE ───────────── acceptance criteria → close issue (orchestrator owns the close)
     ⬥ MILESTONE GATE ── hard stop, smoke test, human approval
```

The orchestrator is **stateless and relaunched** by the dumb loop: it self-selects **WORKING** (process up to N ready tickets) or **CLEANUP** (end-of-run oversight) from durable state on a per-run tracking issue, so it survives crashes and avoids context rot. CI failures are repaired in the background by `ci-fix-v5` after each merge; `monitor-v5` narrates the run read-only.

## Working discipline

Every skill works under [standards/engineering-discipline.md](../standards/engineering-discipline.md) (ED-1..ED-4): confirm claims against source, adversarially self-review before finalizing. The ticket-producing skills end with a three-part contribution (*what we missed / should consider / I'd add*).

## Related

- [Skills](../skills/) — The v5 Claude Code skills that power Phases 3–5
- [Standards](../standards/) — Engineering standards including `testing.md`, `engineering-discipline.md`, and `story-writing-standards.md`
- [Templates](../templates/) — Project CLAUDE.md template, CI workflow templates, and the orchestrate.sh wrapper
