# Agentic Development Workflow

This folder contains the end-to-end workflow for 100% agentic software development using Claude, GitHub Projects, and a supervisor/worker orchestration pattern.

## Contents

| File | Description |
|------|-------------|
| [agentic-development-workflow.md](agentic-development-workflow.md) | Full written guide covering all phases from discovery through deployment |
| [workflow-diagram.html](workflow-diagram.html) | Interactive visual diagram of the workflow |
| [screen-inventory-template.md](screen-inventory-template.md) | Reusable template for the Screen Inventory artifact (Phase 2) |

## Workflow Diagram

**[View the interactive workflow diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

## Phases at a Glance

1. **Discovery & Capture** — Record freeform discussions with Otter.ai
2. **PRD Refinement** — Claude Web synthesizes transcript into PRD, Screen Inventory, and Decisions Log
3. **Project Bootstrap** — Claude Code creates repo, board, and enriched backlog
4. **Orchestrated Development** — Orchestrator + developer sub-agents implement tickets sequentially
5. **Session Summary & Review** — Review results, debug, iterate on skills and standards

## Related

- [Skills](../skills/) — The Claude Code skills that power Phases 3-4 (implement-ticket, orchestrate, refine-story)
