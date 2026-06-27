---
name: reconcile-backlog-v5
description: "Reconcile PRD version changes against an existing backlog and codebase. Diffs the old and new PRDs, classifies each change as new ticket / update existing ticket / no action, surfaces a three-part contribution, and executes via add-story-v5 + refine-story-v5 after user approval. Uses a checklist file for state tracking."
argument-hint: "[old PRD path] [new PRD path] [optional: --decisions-log path]"
---

# Reconcile Backlog

You are reconciling changes between two versions of a PRD against an existing project backlog and codebase. You identify what's new, what changed, and what's already built — then produce creates, updates, and skips. You use a checklist file to track your progress and present findings for review before touching GitHub.

You do NOT implement anything. You produce and update stories.

**Work under engineering discipline** (`standards/engineering-discipline.md`, ED-1..ED-4). Your classifications hinge on claims about what's already built — **"already implemented", "needs a code change", "unaffected"** — and those are exactly the claims most likely to be plausible-but-wrong. **Ground every "already built / not built" classification in the source (ED-1)**; never classify from a plausible memory of the codebase. Adversarially re-check the classification set and **surface your own take** before executing (ED-2, Phase 4). Anything you can't confirm is flagged, not assumed (ED-3). Cite the ED rules by ID; do not restate them.

---

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
2. **Read `../TI-Engineering-Standards/standards/story-writing-standards.md` in full**
3. Read `../TI-Engineering-Standards/standards/project-tracking.md`
4. Read `CLAUDE.md` — extract: story ID prefix, project board URL, build commands
5. Read `ARCHITECTURE.md`

### 0c. Parse Arguments

Parse `$ARGUMENTS` for file paths:

1. **Old PRD** (required) — the previous version
2. **New PRD** (required) — the current version
3. **Decisions Log** (optional) — if `--decisions-log` provided, or auto-detect from `docs/` by matching the new PRD version number

If paths are not provided, look for PRD files in `docs/` and ask the user to confirm which is old and which is new.

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

## Phase 1: Understand Current State

### 1a. Fetch the Full Backlog

Fetch ALL issues — open and closed — with bodies, labels, and state:

```bash
# Open issues
gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --limit 200 --json number,title,labels,body,state --jq '.[] | {number, title, state, labels: [.labels[].name], body: (.body | split("\n") | first)}'

# Closed issues
gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state closed --limit 200 --json number,title,labels,body,state --jq '.[] | {number, title, state, labels: [.labels[].name], body: (.body | split("\n") | first)}'
```

Build an internal map:
- **Issue number → title, state (open/closed), labels, summary**
- Group by: `foundation`, `story`, `milestone`, `bug`, `task`
- Note which milestone each story belongs to (parse from issue body)

### 1b. Scan the Codebase

Understand what's actually built:

```bash
# Project structure
find src/ -maxdepth 2 -type d 2>/dev/null
find client/ -maxdepth 2 -type d 2>/dev/null

# Recent development activity
git log --oneline -30

# Database migrations (what schema exists)
find src/ -path "*/Migrations/*" -o -path "*/Scripts/*" -name "*.sql" 2>/dev/null | head -30
```

### 1c. Fetch Milestone Markers

```bash
gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --label milestone --limit 1000 --json number,title --jq '.[] | {number, title}'
```

### 1d. Initialize the Checklist File

Create the checklist file at `docs/reconciliation-{old_version}-to-{new_version}.md`:

```markdown
# PRD Reconciliation: {Old Version} → {New Version}

**Date:** {today}
**Old PRD:** {old_prd_path}
**New PRD:** {new_prd_path}
**Decisions Log:** {decisions_log_path or "N/A"}
**Repository:** {REPO_NWO}

## Current Backlog Snapshot

**Open issues:** {count}
**Closed issues:** {count}
**Milestones:** {list}

## Reconciliation Progress

| # | PRD Section | Change Summary | Decision Ref | Affected Ticket(s) | Action | Status |
|---|-------------|----------------|--------------|---------------------|--------|--------|

## New Tickets to Create

_(populated during Phase 3)_

## Existing Tickets to Update

_(populated during Phase 3)_

## No Action Needed

_(populated during Phase 3)_

## Execution Log

_(populated during Phase 5)_
```

Tell the user: **"Checklist file created at {path}. Beginning PRD analysis."**

---

## Phase 2: Compute PRD Delta

### 2a. Read Both PRDs

Read the old PRD and new PRD in full. Also read the Decisions Log if provided.

### 2b. Section-by-Section Diff

Walk through the new PRD section by section (each `## Section N:` heading). For each section:

1. Identify the corresponding section in the old PRD
2. Compare content — look for:
   - Added content (new paragraphs, table rows, subsections)
   - Modified content (changed values, renamed terms, updated descriptions)
   - Removed content (struck-through items, deleted subsections)
3. For each material change, create a change record:
   - **Section** — which PRD section
   - **Change summary** — one-line description of what changed
   - **Decision reference** — if this change maps to a decision in the Decisions Log, note it (e.g., "D-52")
   - **Scope** — backend, frontend-extension, frontend-website, database, infrastructure, docs-only

**What counts as "material":** Changes to features, data flows, pricing, provider architecture, UI layout, API contracts, business rules. **Not material:** Wording tweaks, formatting, historical comparison tables, revision log entries.

### 2c. Write Findings to Checklist

For each material change found, add a row to the reconciliation progress table in the checklist file:

```markdown
| 1 | Section 4.1 | Basic Flood Grade added to Stage 1 property card | D-52 | TBD | TBD | ⬜ Pending |
| 2 | Section 4.1 | AI summary moved from Stage 1 to Ask Capto on-demand | D-54 | TBD | TBD | ⬜ Pending |
```

After writing all rows, tell the user: **"Found {N} material changes across {M} PRD sections. Proceeding to classify each against the existing backlog."**

---

## Phase 3: Classify Changes

For each change record in the checklist, determine the action:

### Classification Rules

**CREATE (new ticket)** — when ALL of the following are true:
- The change introduces a capability, service, data flow, or UI element that did not exist in the old PRD
- No existing open ticket covers this work
- No existing closed ticket already implemented this work

**UPDATE (modify existing ticket)** — when:
- An existing open ticket covers related work, but its scope, acceptance criteria, or technical details need to change to reflect the new PRD
- The ticket has NOT been implemented yet (state = open, not in a completed milestone)

**FLAG (review needed)** — when:
- An existing closed ticket implemented something that the new PRD changes
- The built code may need modification
- This produces a new ticket scoped specifically to the delta (not a re-do of the original ticket)

**SKIP (no action)** — when:
- The change is cosmetic (wording, formatting, tier name renames that don't affect functionality)
- The change is documentation-only (revision log, comparison tables)
- An existing ticket already accounts for this change
- The change affects only PRD companion docs, not the product itself

### Classification Process

For each change record:

1. **Search existing tickets** — scan issue titles and bodies for keywords related to this change
2. **Check codebase** — grep for relevant files, classes, or database tables that would be affected
3. **Determine action** — apply the classification rules above
4. **Write to checklist** — update the row with:
   - Affected ticket(s): issue numbers, or "None (new)" 
   - Action: `CREATE`, `UPDATE #N`, `FLAG #N`, or `SKIP`
   - Brief rationale

After classifying all changes, update the three summary sections in the checklist file:

**New Tickets to Create:**
```markdown
### NT-1: {Proposed Title}
**Source:** Change #{N} — {change summary}
**Decision:** {D-XX or "N/A"}
**Milestone:** {existing milestone or "New milestone needed"}
**Summary:** {1-2 sentences}
**Acceptance Criteria:**
- [ ] {criterion}
- [ ] {criterion}
```

**Existing Tickets to Update:**
```markdown
### UT-1: Update #{issue_number} — {issue title}
**Source:** Change #{N} — {change summary}
**What to change:** {specific edits to the issue body or acceptance criteria}
**Comment to add:** {explanation of why the ticket is being updated}
```

**No Action Needed:**
```markdown
| Change # | Summary | Reason |
|----------|---------|--------|
| 5 | Revision log entry added | Docs-only |
| 8 | "Team/Pro" renamed to "Professional" | Cosmetic — no functional change |
```

---

## Phase 4: Present Reconciliation Plan

Present the full plan to the user in conversation. Structure it as:

```markdown
## Reconciliation Plan: {Old Version} → {New Version}

### New Tickets ({count})
1. **{Title}** — {one-line summary}. Milestone: {milestone}.
2. ...

### Ticket Updates ({count})
1. **#{number}: {title}** — {what changes and why}
2. ...

### Flagged for Review ({count})
1. **#{number}: {title}** — built code may need changes: {what changed in PRD}
2. ...

### No Action ({count})
- {count} cosmetic/doc-only changes skipped

**Full details in:** `{checklist_file_path}`

**Ready to execute? Or adjust anything first?**
```

### Adversarial self-review & contribution (before the plan above)

Cross-examine the classification set, then volunteer your take alongside the plan:

- **Adversarial self-review (ED-2).** For every "already built / unaffected / needs a code change" classification, confirm it against the source (ED-1) — open the file, don't classify from memory. A wrong "already built" silently drops needed work; a wrong "needs change" creates phantom tickets. Anything unconfirmed is flagged as a hypothesis (ED-3), not a settled classification.
- **Surface your own take (the three-part contribution):**
  - **What we missed** — PRD deltas with no row, or ripple effects of a change beyond the obvious ticket
  - **What we should consider** — classifications you were unsure about, merges/splits, sequencing
  - **What I'd add** — flag tickets or watch-outs the diff implies
  - **What I considered and set aside** — classifications weighed and rejected, with why

**STOP and wait for user approval.** The user may:
- Approve as-is → proceed to Phase 5
- Adjust classifications (e.g., "skip NT-3, that's not needed")
- Split or merge proposed tickets
- Change milestone assignments
- Ask questions about specific items

Update the checklist file with any adjustments before proceeding.

---

## Phase 5: Execute

Only proceed after user approves the plan.

### 5a. Create New Tickets (via add-story-v5)

For each approved new ticket (NT-*), **invoke the `add-story-v5` skill** rather than creating issues directly. The add-story skill handles story-writing standards, issue creation, title formatting, custom field assignment, milestone linking, and board placement.

**How to invoke:** Call the `add-story-v5` skill **non-interactively** (pass `NONINTERACTIVE=true` plus the full spec — reconcile is the caller, there's no separate human turn per ticket). A prompt that includes:
- The proposed title
- The summary (framed from user's perspective)
- The acceptance criteria from the checklist
- The target milestone
- The source context: "PRD reconciliation {Old Version} → {New Version}, {Decision reference}"

In non-interactive mode add-story-v5 still runs its grounding (ED-1) and adversarial self-review (ED-2), and folds its contribution items into the issue body rather than asking you.

The add-story skill will:
1. Review the current backlog and codebase for context
2. Create the issue with proper story template and acceptance criteria
3. Set the title to `{PREFIX}-{ISSUE_NUM}: {Title}`
4. Set custom fields (Type=Story, Priority, Story ID)
5. Move to **Up Next**
6. Link as sub-issue of the appropriate milestone marker

After each story is created, **run `refine-story-v5` on the new ticket** to bring it to implementation-ready spec. Invoke the skill with the issue number (e.g., `refine-story-v5 #{ISSUE_NUM}`). The refine skill will review the acceptance criteria against the codebase, add a technical plan (files to change, test approach), and post its findings as an issue comment.

After refinement completes, update the checklist: mark the row as `✅ Created & Refined #{ISSUE_NUM}`

**Important:** Process new tickets one at a time. Wait for the add-story skill AND the refine-story skill to complete before starting the next one.

### 5b. Update Existing Tickets (then refine via refine-story-v5)

For each approved ticket update (UT-*):

1. **Read the current issue body:**
   ```bash
   gh issue view {ISSUE_NUM} --repo {REPO_OWNER}/{REPO_NAME} --json body -q .body
   ```

2. **Edit the issue body** with the approved changes:
   ```bash
   gh issue edit {ISSUE_NUM} --repo {REPO_OWNER}/{REPO_NAME} --body "{updated_body}"
   ```

3. **Add an explanatory comment:**
   ```bash
   gh issue comment {ISSUE_NUM} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
   ## PRD Reconciliation Update ({Old Version} → {New Version})

   **What changed:** {specific changes made to this ticket}
   **Why:** {decision reference and rationale}
   **Source:** `{checklist_file_path}`, change #{N}
   EOF
   )"
   ```

4. **Run `refine-story-v5` on the updated ticket** to bring it up to implementation-ready spec. Invoke the skill with the issue number (e.g., `refine-story-v5 #{ISSUE_NUM}`). The refine skill will review the updated acceptance criteria against the codebase, add technical detail (plan, files to change, test approach), and post its findings as an issue comment.

5. Update checklist: mark row as `✅ Updated & Refined #{ISSUE_NUM}`

**Important:** Process ticket updates one at a time. Wait for the refine-story skill to complete before starting the next one.

### 5c. Create Flag Tickets (via add-story-v5)

For each flagged item that needs a code change, **invoke the `add-story-v5` skill** to create the ticket. The flag ticket is scoped to the specific delta (not a re-implementation of the original ticket).

**How to invoke:** Call the `add-story-v5` skill with a prompt that includes:
- The proposed title (describing what needs to change)
- Context: "PRD {New Version} changed {what} (per {Decision reference}). The existing implementation (from #{original_issue}) needs to be updated."
- The specific acceptance criteria from the checklist
- The original ticket number for reference
- The target milestone

The add-story skill handles issue creation, title formatting, custom fields, milestone linking, and board placement.

After each flag ticket is created, **run `refine-story-v5` on the new ticket** to bring it to implementation-ready spec. Invoke the skill with the issue number (e.g., `refine-story-v5 #{ISSUE_NUM}`). The refine skill will review the acceptance criteria against the codebase, add a technical plan, and post its findings as an issue comment.

After refinement completes, update the checklist: mark the row as `✅ Created & Refined #{ISSUE_NUM}`

### 5d. Finalize Checklist

After all actions are executed, update the Execution Log section of the checklist:

```markdown
## Execution Log

**Executed:** {date/time}
**New tickets created:** {count} — #{list}
**Existing tickets updated:** {count} — #{list}
**Flag tickets created:** {count} — #{list}
**Skipped:** {count}
**Total GitHub actions:** {count}
```

Mark all rows in the reconciliation progress table as `✅ Done`.

---

## Phase 6: Report

```markdown
## Reconciliation Complete: {Old Version} → {New Version}

**Repository:** {REPO_NWO}

### Summary
| Action | Count | Issues |
|--------|-------|--------|
| New tickets created | {N} | #{list} |
| Existing tickets updated | {N} | #{list} |
| Flag tickets created | {N} | #{list} |
| No action (skipped) | {N} | — |

### New Tickets
| # | Story ID | Title | Milestone | Decision |
|---|----------|-------|-----------|----------|
| {num} | {PREFIX}-{num} | {title} | {milestone} | {D-XX} |

### Updated Tickets
| # | Title | What Changed |
|---|-------|-------------|
| {num} | {title} | {summary of update} |

### Checklist File
Full reconciliation details: `{checklist_file_path}`

### Next Steps
1. Review created/updated issues on the project board
2. All tickets (new, updated, and flagged) have been refined via `refine-story-v5` — review refinement comments on each
3. Use `implement-ticket-v4` to begin implementation
```

---

## Recovery: Resuming After Context Loss

If the skill is re-invoked or context is compressed mid-run:

1. **Check for existing checklist file** — look in `docs/` for `reconciliation-*.md`
2. **Read the checklist** — determine which phase was last completed by scanning for:
   - If reconciliation progress table has no rows → still in Phase 2
   - If rows exist but Action column shows "TBD" → still in Phase 3
   - If rows have actions but Status shows "⬜ Pending" → still in Phase 4 or 5
   - If all rows show "✅" → Phase 5 complete, proceed to Phase 6
3. **Resume from the incomplete phase** — do not repeat completed work

---
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-27 -->
<!-- pipeline: v5 -->
<!-- pipeline: v4 -->
