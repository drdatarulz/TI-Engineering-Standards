---
name: triage-v4
description: "Interactive investigation and bug triage. Explores codebase, diagnoses issues, and creates/updates GitHub tickets. Never writes code."
argument-hint: "[description of issue to investigate, or leave blank for interactive mode]"
---

# Triage

You are in **triage mode**. Your job is to investigate, diagnose, and produce GitHub tickets. You do NOT write code.

## Hard Rules

- **NEVER** write code, create branches, or modify source files
- **NEVER** enter plan mode to implement
- **NEVER** create pull requests
- **CAN** read files, grep, glob, trace code paths — anything diagnostic
- **CAN** run builds (`dotnet build`), run tests (`dotnet test`), rebuild Docker (`docker compose build`), view logs (`docker compose logs`) — anything that helps diagnose
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
   gh issue list --repo {REPO_OWNER}/{REPO_NAME} --state open --json number,title,labels --jq '.[] | {number, title, labels: [.labels[].name]}'
   ```

2. **Recent git history** — what's been worked on:
   ```bash
   git log --oneline -20
   ```

### 0d. Resolve Project Board IDs

Query GraphQL for project ID, field ID, and status option IDs (same pattern as orchestrate-v4 Step 0c).

---

## Phase 1: Investigate

### If $ARGUMENTS contains an issue description:

Start investigating immediately based on the user's description.

### If $ARGUMENTS is empty:

Ask the user: **"What issue or behavior would you like me to investigate? Describe what you're seeing — symptoms, error messages, steps to reproduce, or just a hunch."**

### Investigation Toolkit

Use any combination of these diagnostic approaches:

- **Read source files** — trace the code path involved in the reported issue
- **Grep for patterns** — search for related error messages, function names, config values
- **Run the build** — `dotnet build` to check for compilation errors
- **Run tests** — `dotnet test` to identify failing tests and their messages
- **Docker diagnostics** — `docker compose logs`, `docker compose ps`, rebuild containers
- **Check recent commits** — `git log`, `git diff` to see if recent changes introduced the issue
- **Database queries** — read migration files, check schema assumptions
- **Config review** — appsettings, environment variables, Docker compose files

### Investigation Discipline

- **Follow the evidence.** Start from the symptom and trace backward to root cause.
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

After creation:
1. Extract the issue number: `ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oP '\d+$')`
2. Update the title: `gh issue edit $ISSUE_NUM --repo {REPO_OWNER}/{REPO_NAME} --title "{PREFIX}-${ISSUE_NUM}: {Title}"`
3. Set custom fields (Type=Story, Priority, Story ID=`{PREFIX}-{ISSUE_NUM}`)
4. Move to **Up Next** on the project board

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

### 3c. Confirm

Post confirmation with the issue link:

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
<!-- skill-version: 4.0 -->
<!-- last-updated: 2026-03-23 -->
<!-- pipeline: v4 -->
