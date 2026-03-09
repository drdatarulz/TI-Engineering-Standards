---
name: prd-to-backlog-v3
description: "Decompose a PRD, Screen Inventory, and Decisions Log into a milestoned backlog of vertical-slice stories. Creates GitHub issues on the project board following TI story-writing standards."
argument-hint: "[path to PRD] [optional: --screen-inventory path] [optional: --decisions-log path]"
---

# PRD to Backlog

You are converting a PRD into a development backlog. You produce well-structured, right-sized stories with milestones following TI story-writing standards. You create GitHub issues and organize them on the project board.

You do NOT implement anything. You produce stories.

## Phase 0: Load Context

### 0a. Resolve Project Identity

```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
```

### 0b. Sync Standards & Read Config

1. Sync standards repo:
   - If `../TI-Engineering-Standards/` exists: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
   - If not: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
2. Read `../TI-Engineering-Standards/CLAUDE.md`
3. **Read `../TI-Engineering-Standards/standards/story-writing-standards.md` in full** — this defines how stories must be written, sized, and ordered. Follow it exactly.
4. Read `../TI-Engineering-Standards/standards/project-tracking.md` — board structure, labels, custom fields
5. Read `CLAUDE.md` — extract: story ID prefix, project board URL, build commands
6. Read `ARCHITECTURE.md` — system design, component boundaries, database schema

### 0c. Read Input Documents

Parse `$ARGUMENTS` for file paths:

1. **PRD** (required) — the primary input
2. **Screen Inventory** (optional) — if `--screen-inventory` provided or if a screen inventory file exists in `docs/`
3. **Decisions Log** (optional) — if `--decisions-log` provided or if a decisions log file exists in `docs/`

If the PRD path is not provided, ask the user.

### 0d. Resolve Project Board IDs

Extract the project number from the board URL in CLAUDE.md, then query for project ID, field ID, and status option IDs:

```bash
gh api graphql -f query='
{
  user(login: "REPO_OWNER") {
    projectV2(number: PROJECT_NUMBER) {
      id
      field(name: "Status") {
        ... on ProjectV2SingleSelectField {
          id
          options { id name }
        }
      }
    }
  }
}'
```

Store the project ID, field ID, and option IDs for: Inbox, Up Next, In Progress, Done, Waiting/Blocked.

---

## Phase 1: Analyze and Decompose

### 1a. Identify Components and Boundaries

From the PRD and ARCHITECTURE.md, identify:

- Compilable components (APIs, clients, workers, background services)
- Database entities and their relationships
- External integrations and third-party dependencies
- Authentication and authorization boundaries

### 1b. Identify Screens and User Flows

From the Screen Inventory (or PRD if no inventory exists):

- Every screen/view the user interacts with
- Navigation paths between screens
- Modals and overlays
- Shared UI components that appear on multiple screens

### 1c. Determine Foundation Work

Identify what genuinely cannot be part of a vertical slice:

- Solution/project scaffolding
- Shared middleware (auth, logging, error handling)
- Database project setup and initial seed migration
- Docker/test environment configuration
- CI/CD pipeline setup

Keep this list as short as possible. If a database table is only used by one feature, it belongs in that feature's story, not here.

### 1d. Define Milestones

Group screens and capabilities into milestones per story-writing standards:

- **Milestone 1:** Minimum viable visibility — login + primary landing screen. Target: "I can log in and see something."
- **Milestone 2:** Core entity lifecycle — the primary thing the application manages.
- **Milestone 3+:** Secondary features, grouped by relatedness.

Each milestone should map to a coherent set of screens from the screen inventory.

### 1e. Decompose Into Stories

For each milestone, create vertical-slice stories per story-writing standards:

- Group by entity lifecycle (create + list + view + delete = one story)
- Split along capability boundaries, not CRUD operations
- Each story should be completable by a single developer agent session
- Order stories within a milestone so each builds on the previous logically

---

## Phase 2: Present Plan for Review

**Do NOT create any GitHub issues yet.** Present the full backlog plan to the user first:

```markdown
## Backlog Plan

### Foundation ({N} stories)
1. {PREFIX}-001: [title] — [one-line description]
2. {PREFIX}-002: [title] — [one-line description]

### Milestone 1: [Name] ({N} stories)
3. {PREFIX}-003: [title] — [one-line description]
4. {PREFIX}-004: [title] — [one-line description]
→ MILESTONE: [Name] — [What can be reviewed at this point]

### Milestone 2: [Name] ({N} stories)
5. {PREFIX}-005: [title] — [one-line description]
...
→ MILESTONE: [Name] — [What can be reviewed]

**Totals:** {N} stories + {N} foundation + {N} milestones = {N} issues
```

Ask the user: **"Does this decomposition look right? Should I adjust any story scope, reorder anything, or add/remove milestones before I create the issues?"**

Wait for approval. If the user requests changes, adjust and re-present.

---

## Phase 3: Create GitHub Issues

Only proceed after user approves the plan.

### 3a. Determine Next Story ID

```bash
gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state all --label story --json title --jq '.[].title' | grep -oP '{PREFIX}-\d+' | sort -t- -k2 -n | tail -1
```

Increment from there.

### 3b. Create Foundation Issues

For each foundation story:

```bash
gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{PREFIX}-{NNN}: {Title}" \
  --label "foundation" \
  --body "{issue body per story template}"
```

After creation, set custom fields (Type=Task, Priority, Story ID) and move to **Up Next**.

### 3c. Create Story Issues (Per Milestone)

For each vertical-slice story:

```bash
gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{PREFIX}-{NNN}: {Title}" \
  --label "story" \
  --body "$(cat <<'EOF'
## Summary

{Description — framed from user's perspective}

**Milestone:** {Milestone Name}

## Acceptance Criteria

- [ ] {Criterion 1 — specific and testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Branch

`story/{PREFIX}-{NNN}-short-name`

## Test Coverage

| Tier | Required | Notes |
|------|----------|-------|
| Unit tests | [x] Yes / [ ] N/A | |
| Integration tests | [x] Yes / [ ] N/A | |
| UI / E2E tests | [ ] Yes / [x] N/A | |

## Plan

_Fill in before starting implementation._

## Implementation Notes

_Fill in during implementation._

## Test Results

_Fill in when done._

## Files Changed

_Fill in when done._
EOF
)"
```

After creation, set custom fields (Type=Story, Priority, Story ID) and move to **Up Next**.

### 3d. Create Milestone Marker Issues

At the end of each milestone group:

```bash
gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "MILESTONE: {Milestone Name}" \
  --label "milestone" \
  --body "$(cat <<'EOF'
## Review Checklist
- [ ] Application starts without errors
- [ ] {Screen/flow 1} is functional: {what to verify}
- [ ] {Screen/flow 2} is functional: {what to verify}
- [ ] No regressions in previously completed milestones

## Smoke Test
- [ ] Application process starts successfully
- [ ] GET /health returns 200
- [ ] {Key endpoint} returns expected response
- [ ] UI loads at localhost:{port} without console errors

## Stories in This Milestone
- {PREFIX}-{NNN}: {title}
- {PREFIX}-{NNN}: {title}
EOF
)"
```

After creation, set custom fields and move to **Up Next**.

**Ensure the `milestone` label exists** before creating milestone markers — if not, create it:
```bash
gh label create milestone --repo {REPO_OWNER}/{REPO_NAME} --description "Milestone marker issue (review gate)" --color "0E8A16"
```

### 3e. Link Stories as Sub-Issues of Milestones

After creating all stories and milestone markers, link each story as a sub-issue of its milestone marker. This gives epic-style progress tracking — GitHub displays "N of M complete" on each milestone as stories are closed.

For each milestone, for each story in that milestone:

1. Get the story's database ID:
   ```bash
   gh api graphql -f query='query($owner: String!, $repo: String!, $number: Int!) {
     repository(owner: $owner, name: $repo) { issue(number: $number) { databaseId } }
   }' -f owner={REPO_OWNER} -f repo={REPO_NAME} -F number={STORY_ISSUE_NUMBER} --jq '.data.repository.issue.databaseId'
   ```
2. Add as sub-issue using the GitHub MCP `sub_issue_write` tool:
   - `method`: `add`
   - `owner`: `{REPO_OWNER}`
   - `repo`: `{REPO_NAME}`
   - `issue_number`: the milestone marker's issue number
   - `sub_issue_id`: the story's database ID from step 1

---

## Phase 4: Report

```markdown
## Backlog Created

**Repository:** {REPO_OWNER}/{REPO_NAME}
**Stories created:** {N}
**Foundation issues:** {N}
**Milestones created:** {N}
**Story ID range:** {PREFIX}-{first} through {PREFIX}-{last}

### Issue List
| # | Story ID | Title | Label | Milestone |
|---|----------|-------|-------|-----------|
| {number} | {PREFIX}-{NNN} | {title} | {label} | {milestone or "Foundation"} |

### Next Steps
1. Review the created issues on the project board
2. Run `refine-story-v3` on each story to add technical detail
3. Use `orchestrate-v3` to begin implementation
```

---
<!-- skill-version: 3.1 -->
<!-- last-updated: 2026-03-09 -->
<!-- pipeline: v3 -->
