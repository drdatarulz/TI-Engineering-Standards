# Skills (Claude Code)

Shared Claude Code skills that are auto-synced to all TI projects during the [auto-sync protocol](../CLAUDE.md#auto-sync-protocol-for-claude-code).

## Available Skills

> **Deprecated:** v1 and v2 skills remain in this directory for historical reference but are no longer actively maintained. Use the v3 pipeline below.

### v3 Pipeline (PR-based with review gates, milestones, and observability)

| Skill | Invocation | Description |
|-------|-----------|-------------|
| **[prd-to-backlog-v3](prd-to-backlog-v3/SKILL.md)** | `/prd-to-backlog-v3 docs/PRD.md` | Decompose a PRD into a milestoned backlog of vertical-slice stories |
| **[add-story-v3](add-story-v3/SKILL.md)** | `/add-story-v3 [description]` | Conversationally create incremental stories for an existing project |
| **[refine-story-v3](refine-story-v3/SKILL.md)** | `/refine-story-v3 AZ-101` | Refine a GitHub issue into an implementation-ready spec |
| **[implement-ticket-v3](implement-ticket-v3/SKILL.md)** | `/implement-ticket-v3 42` | Implement a single ticket — pushes branch, creates PR. Supports FIX mode |
| **[engineering-review-v3](engineering-review-v3/SKILL.md)** | `/engineering-review-v3 42` | Review a PR against TI Engineering Standards. Implementation and integration-tests modes |
| **[security-review-v3](security-review-v3/SKILL.md)** | `/security-review-v3 42` | OWASP Top 10 security review for PRs |
| **[integration-test-v3](integration-test-v3/SKILL.md)** | `/integration-test-v3 AZ-101` | Write integration tests for a merged implementation. Creates PR. Supports FIX mode |
| **[orchestrate-v3](orchestrate-v3/SKILL.md)** | `/orchestrate-v3 supervised AZ-101, AZ-102` | PR-based pipeline orchestrator with milestone support and observability |

### Investigation & Triage

| Skill | Invocation | Description |
|-------|-----------|-------------|
| **[triage-v3](triage-v3/SKILL.md)** | `/triage-v3 [issue description]` | Interactive investigation and bug triage. Explores codebase, diagnoses issues, creates/updates tickets. Never writes code. |

## How They Fit Together

### Story Creation Path

1. **prd-to-backlog** — Bulk: decompose PRD into milestoned backlog
2. **add-story** — Incremental: add stories to an existing backlog

### Development Pipeline (per ticket, managed by orchestrate-v3)

1. **refine-story-v3** — Refine issue spec (orchestrator or standalone mode)
2. **implement-ticket-v3** — Implement and create PR
3. **engineering-review-v3** — Review PR against standards (up to 3 iterations with fix mode)
4. **security-review-v3** — OWASP Top 10 security review (up to 2 iterations with fix mode); on pass, merges PR
5. **integration-test-v3** — Write integration tests on a separate PR
6. **engineering-review-v3** — Review integration test PR (up to 3 iterations with fix mode)
7. **orchestrate-v3** — Orchestrates the full pipeline per ticket, manages board updates, review loops, milestones, and observability

### Feedback Loop (testing → new tickets)

1. **triage-v3** — Investigate bugs found during manual testing, produce tickets
2. Tickets feed back into the development pipeline (refine → implement → review → ...)

### Milestone Gates

When the orchestrator encounters an issue with the `milestone` label, it stops regardless of mode, runs the smoke test from the issue body, and waits for human review. This enables vertical-slice development with periodic human checkpoints.

See the full workflow: **[Agentic Development Workflow Diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

For the detailed written guide, see [workflow/agentic-development-workflow.md](../workflow/agentic-development-workflow.md).

## How Sync Works

The auto-sync protocol in each project's `CLAUDE.md` copies skills from this directory into the project's `.claude/skills/` on session start. Local project copies take precedence — if a project has a customized version of a skill, it won't be overwritten.

## Customizing for a Project

To override a shared skill for a specific project, place a modified `SKILL.md` in that project's `.claude/skills/{skill-name}/` directory. The sync will skip it on future runs.

## Archive

Previous versions (v1, v2) are in `skills/archive/` for historical reference. They are not synced to projects and are not actively maintained.
