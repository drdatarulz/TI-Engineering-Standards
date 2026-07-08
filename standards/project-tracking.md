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
| **Story ID** | {PREFIX}-{issue#} | Uses the GitHub issue number (prefix is project-specific, e.g. SF-7) |
| **Component** | (project-specific) | Area of codebase |
| **Due Date** | Date | Optional deadline |

## Issue Types

- **Story** (`story` label) — code-producing work with acceptance criteria and test requirements
- **Bug** (`bug` label) — something broken that needs fixing
- **Task** (`task` label) — non-code work (config, testing, infrastructure, docs)

Templates should be in `.github/ISSUE_TEMPLATE/` (story.md, bug.md, task.md). Reusable templates are in `templates/issue-templates/`. Copy them to your project's `.github/ISSUE_TEMPLATE/`.

## Board Automations

Enable these automations on every project board:
- **Auto-add to project** — new issues from the repo auto-land on the board (configure via project Settings → Workflows)
- Item added → Inbox
- Item closed → Done
- PR merged → Done

## Orchestration Run Tracking (v5)

The v5 orchestrator (`orchestrate-v5`) relaunches as **fresh processes** (it self-selects WORKING/CLEANUP mode each launch), so per-**run** state can't live in a session's memory — it is externalized to a dedicated **per-run tracking issue**, a durable GitHub object that survives process death.

- **One active run = one open issue labeled `orchestration-run`.** Body = **live state** (current ticket, chunk progress, last pyramid ratio, gate-audit status — overwritten each session); comments = **append-only event log**.
- **Find-or-create on startup**, keyed off the `orchestration-run` **label** (not a run ID — that keeps the relaunch loop stateless): no open labelled issue → create one (run start); exactly one → read it to recover state; two or more (a prior run crashed un-closed) → treat the **newest as active**, close the stale one(s).
- **Run-complete = the issue is closed.** At a fixpoint (no Up Next tickets and a CLEANUP pass that injected nothing) the orchestrator closes the tracking issue and emits `RUN_COMPLETE`. Active = open; complete = closed.
- **Crash recovery:** on startup, tickets left **In Progress** by a dead session are resumed or reset to **Up Next**.
- **Ownership:** the orchestrator owns this issue end to end. The dumb relaunch loop (`developer-tools/orchestrate-loop.sh`) never touches GitHub — it only restarts the process and greps stdout for `RUN_COMPLETE`.
- Create the label once if missing: `gh label create orchestration-run --repo {owner}/{repo} --color FBCA04 --description "Active v5 orchestration run"`.

The orchestrator's work **queue is the board** (Status **Up Next** = the ready state; there is no separate "Ready" column). WORKING mode pulls Up Next; crash recovery resets In Progress → Up Next.

## Sub-Issues (Milestone-to-Story Linking)

GitHub's **sub-issues** feature links stories to their parent milestone marker, creating an epic-style hierarchy. When stories are sub-issues of a milestone, the milestone issue displays a progress tracker (e.g., "3 of 5 complete") that updates automatically as child issues are closed.

**Rules:**
- Every story that belongs to a milestone **must** be linked as a sub-issue of that milestone's marker issue
- The `milestone` label must exist on the repo — create it if missing: `gh label create milestone --repo {owner}/{repo} --description "Milestone marker issue (review gate)" --color "0E8A16"`
- Sub-issue linking uses the story's **database ID** (not the issue number) — retrieve it via the GraphQL API
- Both the `prd-to-backlog` and `add-story` skills handle this linking automatically after creating issues

### Post-build additions — the `followup` label

A milestone's **original** stories are created up front (e.g. via `prd-to-backlog`) and carry only their type label (`story`/`bug`). **Any ticket created *after* a milestone's initial build** that belongs to the still-active milestone — mid-development bug fixes, post-staging items, scope additions surfaced during triage — **must**:

1. Be linked as a **sub-issue of the active milestone marker** (per the rules above), and
2. Carry the **`followup`** label, in addition to its type label.

This keeps the original committed scope (`[story]`) distinct from everything added after the build (`[story,followup]` / `[bug,followup]`), so a milestone's growth is legible at a glance. **Never relabel the original stories.** Create the label if missing: `gh label create followup --repo {owner}/{repo} --description "Added after the milestone's initial build" --color "FBCA04"`.

The convention is **manual by design** — the sub-issue link is the signal that a ticket belongs to the milestone, so it can't be inferred before the link exists. Projects may name the active milestone marker in their own `CLAUDE.md` so contributors know which marker to link against.

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

1. Create the issue using the story template with a descriptive title.
2. After creation, extract the issue number from the URL and update the title to `{PREFIX}-{issue#}: Short description`.
3. The issue auto-lands on the board. Set custom fields (Type=Story, Priority, Component, Story ID=`{PREFIX}-{issue#}`).
4. Move to **Up Next** or **In Progress**.

## Working on a Story

1. Create and check out the story branch: `story/{PREFIX}-{issue#}-short-name` from `main`.
2. Move the issue to **In Progress** on the project board.
3. Implement. Check off acceptance criteria in the issue body as you go.
4. Add implementation notes and test results as comments on the issue.
5. Commit code to the story branch.

## Completing a Story

1. Verify all acceptance criteria are checked in the issue body.
2. Add a completion comment with test results and files changed.
3. Merge the story branch to `main`.
4. Close the issue (board automation moves it to **Done**).
