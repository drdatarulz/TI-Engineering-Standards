# Skills (Claude Code)

Shared Claude Code skills that are auto-synced to all TI projects during the [auto-sync protocol](../CLAUDE.md#auto-sync-protocol-for-claude-code).

## Available Skills

| Skill | Invocation | Description |
|-------|-----------|-------------|
| **[implement-ticket](implement-ticket/SKILL.md)** | `/implement-ticket 42` | Implement a single ticket — loads standards, explores codebase, builds/tests, commits, and reports status |
| **[orchestrate](orchestrate/SKILL.md)** | `/orchestrate supervised TX-101, TX-102` | Sequentially implement multiple tickets via subagents with pre-flight checks, board updates, and merging |
| **[refine-story](refine-story/SKILL.md)** | `/refine-story TX-101` | Refine a GitHub issue into an implementation-ready spec by exploring the codebase and resolving gaps interactively |

## How They Fit Together

These skills map to phases in the agentic development workflow:

1. **refine-story** — Phase 4 (Story Decomposition & Refinement)
2. **orchestrate** — Phase 5 (Orchestrated Development)
3. **implement-ticket** — Phase 5 inner loop (spawned by orchestrate for each ticket)

See the full workflow: **[Agentic Development Workflow Diagram](https://htmlpreview.github.io/?https://github.com/drdatarulz/TI-Engineering-Standards/blob/main/workflow/workflow-diagram.html)**

For the detailed written guide, see [workflow/agentic-development-workflow.md](../workflow/agentic-development-workflow.md).

## How Sync Works

The auto-sync protocol in each project's `CLAUDE.md` copies skills from this directory into the project's `.claude/skills/` on session start. Local project copies take precedence — if a project has a customized version of a skill, it won't be overwritten.

## Customizing for a Project

To override a shared skill for a specific project, place a modified `SKILL.md` in that project's `.claude/skills/{skill-name}/` directory. The sync will skip it on future runs.
