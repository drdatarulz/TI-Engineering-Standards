# Agentic Development Workflow

This folder contains the end-to-end workflow for 100% agentic software development using Claude, GitHub Projects, and a PR-based supervisor/worker orchestration pattern with review gates and milestones.

## Contents

| File | Description |
|------|-------------|
| [agentic-development-workflow.md](agentic-development-workflow.md) | Full written guide covering all phases from discovery through deployment |
| [workflow-diagram.html](workflow-diagram.html) | Interactive visual diagram of the v3 pipeline |
| [screen-inventory-template.md](screen-inventory-template.md) | Reusable template for the Screen Inventory artifact (Phase 2) |

## Workflow Diagram

**[View the interactive workflow diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

## Phases at a Glance

1. **Discovery & Capture** — Record freeform discussions with Otter.ai
2. **PRD Refinement** — Claude Web synthesizes transcript into PRD, Screen Inventory, and Decisions Log
3. **Project Bootstrap** — Claude Code creates repo, board, and milestoned backlog (prd-to-backlog-v3)
4. **Orchestrated Development** — PR-based pipeline: Refine → Implement → Engineering Review → Security Review → Integration Tests → Review → Merge (orchestrate-v3)
5. **Session Summary & Review** — Observability metrics, PRD amendments, debug and iterate

## v3 Pipeline Per Ticket

```
1.   REFINE ──────────── refine-story-v3
2.   IMPLEMENT ───────── implement-ticket-v3 → PR #1
3.   ENGINEERING REVIEW ─ engineering-review-v3 (↻ max 3 fix iterations)
3.5. SECURITY REVIEW ──── security-review-v3 (↻ max 2 fix iterations) → merge PR #1
4.   INTEGRATION TESTS ── integration-test-v3 → PR #2
5.   ENGINEERING REVIEW ─ engineering-review-v3 (↻ max 3 fix iterations) → merge PR #2
6.   CLOSE ───────────── acceptance criteria → close issue
     ⬥ MILESTONE GATE ── hard stop, smoke test, human approval
```

## Related

- [Skills](../skills/) — The v3 Claude Code skills that power Phases 3-5
- [Standards](../standards/) — Engineering standards including story-writing-standards.md
- [Templates](../templates/) — Project CLAUDE.md template and issue templates
