# Project Tracking Standards

## Tool

- **GitHub Projects v2** — single source of truth for all work tracking
- **GitHub Issues** as the backing items — issues auto-land on the board via the **Auto-add to project** workflow
- Do NOT track work in markdown files

## Board Columns (Status)

| Column | Maps to |
|--------|---------|
| **Inbox** | Newly captured ideas — needs triage |
| **Up Next** | Triaged, ready to work on |
| **In Progress** | Actively being worked on |
| **Waiting / Blocked** | Blocked on external dependency (note who/what in a comment) |
| **Someday / Maybe** | Low-priority ideas, no commitment |
| **Done** | Completed and verified |

## Custom Fields

| Field | Values | Purpose |
|-------|--------|---------|
| **Type** | Story, Bug, Task | Classify the work item |
| **Priority** | High, Medium, Low | Urgency |
| **Story ID** | {PREFIX}-XXX | Sequential ID for stories (prefix is project-specific) |
| **Component** | (project-specific) | Area of codebase |
| **Due Date** | Date | Optional deadline |

## Issue Types

- **Story** (`story` label) — code-producing work with acceptance criteria and test requirements
- **Bug** (`bug` label) — something broken that needs fixing
- **Task** (`task` label) — non-code work (config, testing, infrastructure, docs)

Templates should be in `.github/ISSUE_TEMPLATE/` (story.md, bug.md, task.md). Reusable templates are in `templates/issue-templates/`. Copy them to your project's `.github/ISSUE_TEMPLATE/` and replace `{PREFIX}` with your project's Story ID prefix.

## Board Automations

Enable these automations on every project board:
- **Auto-add to project** — new issues from the repo auto-land on the board (configure via project Settings → Workflows)
- Item added → Inbox
- Item closed → Done
- PR merged → Done

## GTD Labels

Apply GTD labels as needed for workflow management:
- `gtd:next-action`
- `gtd:waiting-for`
- `gtd:someday-maybe`

## Session Start Protocol

1. Check the project board for **In Progress** items — pick up where you left off.
2. If nothing is In Progress, check **Up Next** for the highest-priority item.
3. Run `gh issue list --repo {owner}/{repo} --state open --label story` to see open stories.

## Creating Issues

When creating issues, they auto-land on the board via the Auto-add workflow. Always set custom fields immediately after creation — don't leave them for manual assignment.

1. Create the issue via `gh issue create`.
2. The issue auto-lands on the board in **Inbox**.
3. **Immediately set custom fields** (Type, Priority, Component, Story ID) via `gh project item-edit` — the board automations only set Status to Inbox, all other fields must be set explicitly.
4. Store the project ID and field IDs in your project's `CLAUDE.md` for quick reference.

### Creating a Story

1. Determine next Story ID: check existing stories and increment.
2. Create the issue using the story template — fill in title as `{PREFIX}-XXX: Short description`, acceptance criteria, plan, and test coverage.
3. The issue auto-lands on the board. Set custom fields (Type=Story, Priority, Component, Story ID).
4. Move to **Up Next** or **In Progress**.

## Working on a Story

1. Create and check out the story branch: `story/{PREFIX}-XXX-short-name` from `main`.
2. Move the issue to **In Progress** on the project board.
3. Implement. Check off acceptance criteria in the issue body as you go.
4. Add implementation notes and test results as comments on the issue.
5. Commit code to the story branch.

## Completing a Story

1. Verify all acceptance criteria are checked in the issue body.
2. Add a completion comment with test results and files changed.
3. Merge the story branch to `main`.
4. Close the issue (board automation moves it to **Done**).
