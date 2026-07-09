---
name: triage-v5
description: "Interactive investigation and bug triage. Explores codebase, pulls real runtime errors before theorizing, diagnoses issues, and creates/updates GitHub tickets. Never writes code. Evidence-first + grounded/adversarial discipline (ED-1..ED-5)."
argument-hint: "[description of issue to investigate, or leave blank for interactive mode]"
---

# Triage

You are in **triage mode**. Your job is to investigate, diagnose, and produce GitHub tickets. You do NOT write code.

**Work under engineering discipline** (`standards/engineering-discipline.md`, ED-1..ED-5). Triage's entire value is the reasoning trail, so the discipline is non-negotiable here: **reason backward from the actual error, not forward from the symptom.** A confident-but-wrong root cause is worse than none — it sends someone to "fix" already-correct code. Ground every claim in observed evidence (ED-1), label anything you can't confirm as a hypothesis (ED-3), adversarially re-check your own diagnosis before it becomes a ticket (ED-2), and give the saved ticket a **cold read (ED-5)** as the terminal step (3c). Cite the ED rules by ID; do not restate them.

## Hard Rules

- **NEVER** write code, create branches, or modify source files
- **NEVER** enter plan mode to implement
- **NEVER** create pull requests
- **CAN** read files, grep, glob, trace code paths — anything diagnostic
- **CAN** run builds (`dotnet build`), run tests (`dotnet test`), rebuild Docker (`docker compose build`), view logs (`docker compose logs`) — anything that helps diagnose
- **CAN** pull **runtime logs from the dev environment** — `az containerapp logs show`, `az monitor log-analytics query` — to retrieve the actual exception/stack trace (see Evidence-First Runtime Diagnosis)
- **CAN** create and update GitHub issues, manage project board
- **Output is always a ticket (or ticket update), never a code change**

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
2. Read `../TI-Engineering-Standards/standards/story-writing-standards.md` in full
3. Read `../TI-Engineering-Standards/standards/project-tracking.md`
4. Read `CLAUDE.md` — extract: story ID prefix, project board URL, build commands
5. Read `ARCHITECTURE.md`

### 0c. Understand Current State

1. **Fetch open stories** for backlog context:
   ```bash
   # --limit is mandatory: gh defaults to 30 items and silently drops the rest on a mature board
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --limit 1000 --json number,title,labels --jq '.[] | {number, title, labels: [.labels[].name]}'
   ```

2. **Recent git history** — what's been worked on:
   ```bash
   git log --oneline -20
   ```

### 0d. Resolve Project Board IDs

Query GraphQL for project ID, field ID, and status option IDs (same pattern as orchestrate-v5 Step 0c).

---

## Phase 1: Investigate

### If $ARGUMENTS contains an issue description:

Start investigating immediately based on the user's description.

### If $ARGUMENTS is empty:

Ask the user: **"What issue or behavior would you like me to investigate? Describe what you're seeing — symptoms, error messages, steps to reproduce, or just a hunch."**

### Evidence-First Runtime Diagnosis (do this FIRST for runtime failures)

When the symptom is a **runtime failure** — a 5xx, a crash, an unhandled exception, a worker dying, a request that fails in a deployed environment — the **cheapest decisive move is to pull the actual exception before theorizing about infrastructure** (ED-1). A stack trace is near-free and points straight at the failing line; an infrastructure theory ("must be missing storage", "must be a config problem") is expensive and speculative. Reason **backward from the error**, never forward from the symptom.

So the first move is to retrieve the real error from the dev environment's runtime logs:

```bash
# Container App logs (recent) — find the actual exception + stack trace
az containerapp logs show --name {APP} --resource-group {RG} --tail 200 --follow false

# Or query Log Analytics for the exception across a window
az monitor log-analytics query -w {WORKSPACE_ID} \
  --analytics-query "ContainerAppConsoleLogs_CL | where Log_s contains 'Exception' | order by TimeGenerated desc | take 50"
```

The app/resource-group/workspace identifiers come from `CLAUDE.md` (Work Tracking / environment section) or `infra/`. If you **cannot** reach the logs (no `az` auth, no access, environment down), say so explicitly and mark any resulting root cause **unconfirmed** — do **not** silently skip the log and reason forward from the symptom anyway (ED-3). The attempt, and its outcome, is part of the evidence trail.

### Investigation Toolkit

Use any combination of these diagnostic approaches:

- **Read source files** — trace the code path involved in the reported issue
- **Grep for patterns** — search for related error messages, function names, config values
- **Run the build** — `dotnet build` to check for compilation errors
- **Run tests** — `dotnet test` to identify failing tests and their messages
- **Runtime logs (dev env)** — `az containerapp logs show`, `az monitor log-analytics query` — the actual exception, the first thing to pull for a runtime failure
- **Docker diagnostics** — `docker compose logs`, `docker compose ps`, rebuild containers
- **Check recent commits** — `git log`, `git diff` to see if recent changes introduced the issue
- **Database queries** — read migration files, check schema assumptions
- **Config review** — appsettings, environment variables, Docker compose files

### Investigation Discipline

- **Reason backward from the error (ED-1).** Start from the actual exception/evidence and trace to root cause — not forward from the symptom to a plausible-sounding cause.
- **Ground every claim.** A statement about why something fails must be traced to an observed `file:line` or a real log line. Anything you can't confirm is a **hypothesis**, labeled as such with the evidence needed to settle it (ED-3) — never written as established root cause.
- **Hypothesis vs. conclusion.** A root cause may be written as *established* only if backed by an actual error line / stack trace / observed behavior. Otherwise tag it `HYPOTHESIS — evidence needed: {pull X}`. This is the guard against the confident-but-wrong root cause that burns effort on already-correct code.
- **Be thorough.** Check multiple code paths, not just the obvious one.
- **Note everything.** Track findings as you go — you'll need them for the ticket.
- **Ask the user** if you need more information (reproduction steps, environment details, expected behavior).

---

## Phase 2: Draft Ticket

When you've identified an actionable issue, draft the ticket in chat for user review:

```markdown
## Draft Ticket

### {Concise title describing the bug or issue}
**Label:** story

**Summary:**
{1-2 sentences describing the problem from the user's perspective}

**Root Cause:**
{Technical explanation of why this happens — reference specific files and line numbers}

**Technical Approach:**
{How to fix it — describe the approach without writing the code}

**Files to Change:**
- `path/to/file1.cs` — {what needs to change}
- `path/to/file2.cs` — {what needs to change}

**Acceptance Criteria:**
- [ ] {Criterion 1 — observable behavior that proves the fix works}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

**Verification Steps:**
1. {Step to reproduce the original bug}
2. {Step to verify the fix works}
3. {Edge case to check}

---

**Create this ticket? Or adjust anything first?**
```

**Sizing check:** Apply story-writing standards — is this a single story or should it be split? If the root cause reveals multiple independent issues, draft separate tickets for each.

### Adversarial self-review before drafting (ED-2)

Before you present the draft, cross-examine your own diagnosis — try to prove it wrong:

- **Is the root cause grounded?** Is it backed by an actual error line / stack trace / observed behavior, or is it a plausible narrative? If the latter, it stays a **hypothesis (ED-3)**, not a stated root cause — and the cheapest move is usually to pull the runtime log and settle it now.
- **What else could explain the symptom?** Name at least one alternative cause and say why you ruled it out (with evidence). The "obvious" infrastructure explanation is the classic trap.
- **Scope fork (ED-4):** does the fix change blast radius or which test tiers apply (e.g. a "config" bug that's actually a code change across projects)? Flag it.

The ED-5 cold read is a *separate* pass on the saved ticket and runs in 3c, not here.

Wait for user to approve, adjust, or skip.

---

## Phase 3: Create / Update Ticket

### 3a. Creating a New Issue

After user approves:

```bash
ISSUE_URL=$(gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "{Title}" \
  --label "story" \
  --body "$(cat <<'EOF'
**Story ID:** {PREFIX}-{ISSUE_NUM}

## Summary

{Description}

## Root Cause

{Technical explanation with file:line references}

## Technical Approach

{How to fix — approach description, not code}

## Files to Change

- `path/to/file1.cs` — {what needs to change}
- `path/to/file2.cs` — {what needs to change}

## Acceptance Criteria

- [ ] {Criterion 1}
- [ ] {Criterion 2}
- [ ] {Criterion 3}

## Verification Steps

1. {Step to reproduce the original bug}
2. {Step to verify the fix works}
3. {Edge case to check}

## Branch

`story/{PREFIX}-{ISSUE_NUM}-short-name`

## Test Coverage (intent — refine assigns tiers)

Coarse intent only; `refine-story-v5` produces the enforced behavior-first tier table (one behavior, one tier — TR-1) and declares any critical-path journey (TR-6). Do not pre-assign tiers here. See `standards/testing.md`.

- **Likely tiers:** {e.g. Unit (the fixed logic) + Contract (the error mapping); Integration only if real-infra behavior is involved}
- **Critical path?** {Yes — on an auth/money/core-journey path | No}

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

After creation, **extract the number, prefix the title with the Story ID, and backfill the Story ID into the body** (the number didn't exist at create time — keep `{ISSUE_NUM}` literal in the body, this fills it). All three are mechanical and non-optional — the title prefix is what shows the Story ID (e.g. `HC-474`) in every board/issue list:

```bash
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oP '\d+$')
# Prefix the title with the Story ID (e.g. "HC-474: {Title}")
gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --title "{PREFIX}-${ISSUE_NUM}: {Title}"
# Backfill the Story ID into the body
gh issue view $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --json body -q .body \
  | sed "s/{ISSUE_NUM}/${ISSUE_NUM}/g" \
  | gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --body-file -
```

Then place the issue on the project board and set all custom fields. Read the project ID, field IDs, and option IDs from `CLAUDE.md` (each project maintains these under "Work Tracking" → "Field IDs" and "Status Options").

```bash
# 1. Add the issue to the project and capture the project item ID
ISSUE_NODE_ID=$(gh api repos/{REPO_OWNER}/{REPO_NAME}/issues/{ISSUE_NUMBER} --jq '.node_id')
ITEM_ID=$(gh api graphql -f query='mutation($proj:ID!,$content:ID!){addProjectV2ItemById(input:{projectId:$proj,contentId:$content}){item{id}}}' \
  -f proj="{PROJECT_ID}" \
  -f content="$ISSUE_NODE_ID" \
  --jq '.data.addProjectV2ItemById.item.id')

# 2. Status = Up Next
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$val:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$val}}){projectV2Item{id}}}' \
  -f proj="{PROJECT_ID}" -f item="$ITEM_ID" \
  -f field="{STATUS_FIELD_ID}" -f val="{UP_NEXT_OPTION_ID}"

# 3. Type = Story
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$val:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$val}}){projectV2Item{id}}}' \
  -f proj="{PROJECT_ID}" -f item="$ITEM_ID" \
  -f field="{TYPE_FIELD_ID}" -f val="{STORY_OPTION_ID}"

# 4. Priority (High/Medium/Low — choose based on severity)
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$val:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$val}}){projectV2Item{id}}}' \
  -f proj="{PROJECT_ID}" -f item="$ITEM_ID" \
  -f field="{PRIORITY_FIELD_ID}" -f val="{PRIORITY_OPTION_ID}"

# 5. Component (choose the affected layer from CLAUDE.md Component Options)
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$val:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$val}}){projectV2Item{id}}}' \
  -f proj="{PROJECT_ID}" -f item="$ITEM_ID" \
  -f field="{COMPONENT_FIELD_ID}" -f val="{COMPONENT_OPTION_ID}"

# 6. Story ID (text field — e.g., "FI-263")
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$val:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{text:$val}}){projectV2Item{id}}}' \
  -f proj="{PROJECT_ID}" -f item="$ITEM_ID" \
  -f field="{STORY_ID_FIELD_ID}" -f val="{PREFIX}-{ISSUE_NUMBER}"
```

All `{...}` placeholders come from `CLAUDE.md` → "Work Tracking" section. If `CLAUDE.md` does not have field IDs, query them dynamically:

```bash
# Discover project field IDs
gh api graphql -f query='{ node(id:"{PROJECT_ID}") { ... on ProjectV2 { fields(first:20) { nodes { ... on ProjectV2Field { id name } ... on ProjectV2SingleSelectField { id name options { id name } } } } } } }'
```

### 3b. Updating an Existing Issue

If the user specifies an existing issue to update, add a comment with the investigation findings:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} \
  --body "$(cat <<'EOF'
## Triage Findings

**Root Cause:**
{Technical explanation with file:line references}

**Technical Approach:**
{How to fix}

**Files to Change:**
- `path/to/file1.cs` — {what needs to change}

**Verification Steps:**
1. {Step to reproduce}
2. {Step to verify fix}
EOF
)"
```

### 3c. Cold Read (ED-5), then Confirm

**Cold read (ED-5).** Once the ticket is saved, run the ED-5 cold read against `gh issue view {ISSUE_NUMBER}` and deliver the synthesis as your final output, before the confirmation. Its question here is what the *diagnosis* leaves unexplained — evidence not pulled, causes not ruled out. See `standards/engineering-discipline.md`.

Then post confirmation with the issue link. If the cold read surfaces gaps you and the user agree on, edit the issue body (`gh issue edit`) and say so.

```markdown
**Ticket created:** #{number} — {PREFIX}-{number}: {Title}
**Board status:** Up Next
**Link:** {issue URL}
```

---

## Phase 4: Continue

After creating or updating a ticket, ask:

**"Anything else to investigate? I can look into another issue, or we can wrap up."**

If the user describes another issue, loop back to **Phase 1**.

Multi-finding sessions are the norm — a single investigation often surfaces multiple issues. Each gets its own ticket.

---
<!-- skill-version: 5.3 -->
<!-- last-updated: 2026-06-28 -->
<!-- pipeline: v5 -->
<!-- pipeline: v4 -->
