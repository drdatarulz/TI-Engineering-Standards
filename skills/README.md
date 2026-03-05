# Skills (Claude Code)

Shared Claude Code skills that are auto-synced to all TI projects during the [auto-sync protocol](../CLAUDE.md#auto-sync-protocol-for-claude-code).

## Available Skills

> **Deprecated:** v1 skills (`implement-ticket`, `orchestrate`, `refine-story`) remain in this directory for historical reference but are no longer actively maintained. Use the v2 pipeline below.

### v2 Pipeline (PR-based with review gates)

| Skill | Invocation | Description |
|-------|-----------|-------------|
| **[refine-story-v2](refine-story-v2/SKILL.md)** | `/refine-story-v2 TX-101` | Refine a GitHub issue into an implementation-ready spec. Supports orchestrator mode (auto-decisions, issue comments) and standalone mode (interactive) |
| **[implement-ticket-v2](implement-ticket-v2/SKILL.md)** | `/implement-ticket-v2 42` | Implement a single ticket — pushes branch, creates PR, posts issue comment. Supports FIX mode to address review feedback on an existing PR |
| **[engineering-review-v2](engineering-review-v2/SKILL.md)** | `/engineering-review-v2 42` | Review a PR against TI Engineering Standards. Two modes: implementation (code review) and integration-tests (test quality review). Posts line-level PR comments or approves |
| **[security-review-v2](security-review-v2/SKILL.md)** | `/security-review-v2 42` | OWASP Top 10 security review for PRs. Framework-aware analysis with attack vector requirements to minimize false positives. Blocks merge on high-confidence critical/high findings |
| **[integration-test-v2](integration-test-v2/SKILL.md)** | `/integration-test-v2 TX-101` | Write integration tests for a merged implementation. Branches from main, follows Testcontainers patterns, creates PR. Supports FIX mode for review feedback |
| **[orchestrate-v2](orchestrate-v2/SKILL.md)** | `/orchestrate-v2 supervised TX-101, TX-102` | PR-based pipeline orchestrator. Refine → Implement (PR) → Review loop → Integration Tests (PR) → Review loop → Merge → Close |

## How They Fit Together

The v2 pipeline uses PR-based review gates and integration test stages:

1. **refine-story-v2** — Refine issue spec (orchestrator or standalone mode)
2. **implement-ticket-v2** — Implement and create PR
3. **engineering-review-v2** — Review PR against standards (up to 3 iterations with implement-ticket-v2 fix mode)
4. **security-review-v2** — OWASP Top 10 security review (up to 2 iterations with implement-ticket-v2 fix mode); on pass, merges PR
5. **integration-test-v2** — Write integration tests on a separate PR
6. **engineering-review-v2** — Review integration test PR (up to 3 iterations with integration-test-v2 fix mode)
7. **orchestrate-v2** — Orchestrates the full pipeline per ticket, manages board updates and review loops

See the full workflow: **[Agentic Development Workflow Diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

For the detailed written guide, see [workflow/agentic-development-workflow.md](../workflow/agentic-development-workflow.md).

## How Sync Works

The auto-sync protocol in each project's `CLAUDE.md` copies skills from this directory into the project's `.claude/skills/` on session start. Local project copies take precedence — if a project has a customized version of a skill, it won't be overwritten.

## Customizing for a Project

To override a shared skill for a specific project, place a modified `SKILL.md` in that project's `.claude/skills/{skill-name}/` directory. The sync will skip it on future runs.
