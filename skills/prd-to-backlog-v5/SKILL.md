---
name: prd-to-backlog-v5
description: "Decompose a PRD, Screen Inventory, and Decisions Log into a milestoned backlog of vertical-slice stories. Nominates the repo-wide critical-path journeys, surfaces a three-part contribution, and creates GitHub issues on the project board following TI story-writing standards."
argument-hint: "[path to PRD] [optional: --screen-inventory path] [optional: --decisions-log path]"
---

# PRD to Backlog

You are converting a PRD into a development backlog. You produce well-structured, right-sized stories with milestones following TI story-writing standards. You create GitHub issues and organize them on the project board.

**Work under engineering discipline** (`standards/engineering-discipline.md`, ED-1..ED-4). Ground decomposition claims about existing code in the source (ED-1); adversarially re-check the backlog and **surface your own take** before creating issues (ED-2, Phase 2.5). The backlog is also the natural place to **budget the repo-wide critical-path journeys** (TR-6 ceiling is 10 across the whole repo) — nominate them once here (Phase 1f) so refine/ui-test draw from a budgeted pool instead of each story minting its own. Cite ED/TR rules by ID; do not restate them.

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

### 1f. Nominate the Critical-Path Journeys (repo-wide budget)

The UI critical-path set is capped at **10 journeys repo-wide** (TR-6 ceiling; floor ~3) — a hard, repo-level budget, not a per-story one. The backlog is the only vantage point that sees the whole repo at once, so nominate the candidate set here:

- Identify the journeys that genuinely carry the product: **auth**, the **core create→read** flow for the primary entity, the **money path** (payment/checkout/submit), and the few other end-to-end flows whose failure is unacceptable.
- Keep the list to **≤10**, ideally 3–6. Note which story will own each.
- These are *nominations*: `refine-story-v5` declares the journey on the owning story (TR-6) and `ui-test-v5` tags it; `engineering-review-v5` enforces the ≤10 count. Recording the budget here keeps the repo from drifting past the ceiling one story at a time.

---

## Phase 2: Present Plan for Review

**Do NOT create any GitHub issues yet.** Present the full backlog plan to the user first:

```markdown
## Backlog Plan

### Foundation ({N} stories)
1. [title] — [one-line description]
2. [title] — [one-line description]

### Milestone 1: [Name] ({N} stories)
3. [title] — [one-line description]
4. [title] — [one-line description]
→ MILESTONE: [Name] — [What can be reviewed at this point]

### Milestone 2: [Name] ({N} stories)
5. [title] — [one-line description]
...
→ MILESTONE: [Name] — [What can be reviewed]

**Totals:** {N} stories + {N} foundation + {N} milestones = {N} issues

### Critical-path journeys (≤10 repo-wide — TR-6)
1. {journey} — owned by story [N]
2. {journey} — owned by story [N]
...
```

Ask the user: **"Does this decomposition look right? Should I adjust any story scope, reorder anything, or add/remove milestones before I create the issues?"**

Wait for approval. If the user requests changes, adjust and re-present.

---

## Phase 2.5: Adversarial Self-Review & Contribution

Before creating issues, cross-examine the backlog, then volunteer your take.

**Adversarial self-review (ED-2).** Re-check claims about the existing codebase against the source (ED-1) — foundation work that may already exist, entities/screens assumed present. Is the critical-path list within the ≤10 ceiling and genuinely the highest-value flows (ED-4 — an over-budget set is a scope fork)? Anything unconfirmed is flagged, not assumed (ED-3).

**Surface your own take (the three-part contribution).** Volunteer this without being asked:

- **What we missed** — capabilities/screens/flows implied by the PRD but absent from the decomposition; foundation work not called out
- **What we should consider** — alternative milestone boundaries, story splits/merges, sequencing risks, the critical-path nominations
- **What I'd add** — stories, dependencies, or watch-outs that strengthen the backlog
- **What I considered and set aside** — decompositions weighed and rejected, with why

---

## Phase 3: Create GitHub Issues

Only proceed after user approves the plan.

### 3a. Create Foundation Issues

For each foundation story:

```bash
ISSUE_URL=$(gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{Title}" \
  --label "foundation" \
  --body "{issue body per story template}")
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oP '\d+$')
# Backfill the Story ID into the body (number didn't exist at create time; keep {ISSUE_NUM} literal in the body)
gh issue view $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --json body -q .body \
  | sed "s/{ISSUE_NUM}/${ISSUE_NUM}/g" \
  | gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --body-file -
gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --title "{PREFIX}-${ISSUE_NUM}: {Title}"
```

After creation, set custom fields (Type=Task, Priority, Story ID=`{PREFIX}-{ISSUE_NUM}`) and move to **Up Next**.

### 3b. Create Story Issues (Per Milestone)

For each vertical-slice story:

```bash
ISSUE_URL=$(gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{Title}" \
  --label "story" \
  --body "$(cat <<'EOF'
**Story ID:** {PREFIX}-{ISSUE_NUM}

## Summary

{Description — framed from user's perspective}

**Milestone:** {Milestone Name}

## Acceptance Criteria

- [ ] {Criterion 1 — specific and testable}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Branch

`story/{PREFIX}-{ISSUE_NUM}-short-name`

## Test Coverage (intent — refine assigns tiers)

Coarse intent only; `refine-story-v5` produces the enforced behavior-first tier table (one behavior, one tier — TR-1) and declares any critical-path journey (TR-6) from the backlog's nominated set. Do not pre-assign tiers here. See `standards/testing.md`.

- **Likely tiers:** {e.g. Unit + Contract; Integration only if real-infra behavior; UI only if a user journey}
- **Critical path?** {Yes — names a journey from the repo-wide critical-path set | No}

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

After creation, extract the issue number from the URL, then **backfill the Story ID into the body** (mechanical, non-optional — keep `{ISSUE_NUM}` literal in the body at creation, this fills it):
```bash
gh issue view $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --json body -q .body \
  | sed "s/{ISSUE_NUM}/${ISSUE_NUM}/g" \
  | gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --body-file -
```
Update the title to `{PREFIX}-{ISSUE_NUM}: {Title}`, set custom fields (Type=Story, Priority, Story ID=`{PREFIX}-{ISSUE_NUM}`), and move to **Up Next**.

### 3c. Create Milestone Marker Issues

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
- #{issue_number}: {title}
- #{issue_number}: {title}
EOF
)"
```

After creation, set custom fields. Move to **Up Next**.

**Ensure the `milestone` label exists** before creating milestone markers — if not, create it:
```bash
gh label create milestone --repo {REPO_OWNER}/{REPO_NAME} --description "Milestone marker issue (review gate)" --color "0E8A16"
```

### 3d. Link Stories as Sub-Issues of Milestones

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
**Issue range:** #{first} through #{last}

### Issue List
| # | Story ID | Title | Label | Milestone |
|---|----------|-------|-------|-----------|
| {number} | {PREFIX}-{number} | {title} | {label} | {milestone or "Foundation"} |

### Next Steps
1. Review the created issues on the project board
2. Run `refine-story-v5` on each story to add technical detail
3. Use `orchestrate-v5` to begin implementation
```

---
<!-- skill-version: 5.1 -->
<!-- last-updated: 2026-06-27 -->
<!-- pipeline: v5 -->
<!-- pipeline: v4 -->
