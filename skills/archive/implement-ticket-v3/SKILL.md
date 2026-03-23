---
name: implement-ticket-v3
description: "Implement a single ticket following TI Engineering Standards. Pushes branch, creates PR, posts issue comment. Supports FIX mode to address review feedback on an existing PR."
argument-hint: "[issue-number or full ticket details]"
---

You are implementing a single ticket. Your working directory is the project root (the directory containing `CLAUDE.md`).

**Mode Detection:** When `{FIX_MODE}` is `true`, you are in FIX mode — skip to the Fix Mode section below. Otherwise, proceed with the full implementation workflow.

## Step 0: Resolve Project Context

Before anything else, determine the project's GitHub repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

This gives you `{OWNER}/{REPO}` for all GitHub CLI commands.

## Resolve Ticket Details

If `{TICKET_TITLE}` appears literally (i.e., was not substituted by an orchestrator), you are running standalone:
- Fetch the ticket: `gh issue view $ARGUMENTS` (the `--repo` flag is unnecessary if you're in the project directory)
- Use the issue title as the ticket title and the issue body as the ticket body
- Determine the branch from `git branch --show-current`
- Extract the Story ID (prefix-XXX) from the issue title

Otherwise, when invoked by the orchestrator, these values are already populated:
- **Story ID:** {TICKET_NUMBER}
- **Ticket:** {TICKET_TITLE}
- **Branch:** {BRANCH_NAME}
- **GitHub Issue:** #{ISSUE_NUMBER}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}

**Fetch the full ticket body** from GitHub (do NOT expect it inline — it is too large for the prompt):
```bash
gh issue view {ISSUE_NUMBER}
```
Read the acceptance criteria, technical approach, and files expected to change from the issue body.

## Context Loading (Do This First)

Before writing any code, read and internalize these files:

1. Read `../TI-Engineering-Standards/CLAUDE.md` and **every file it references** — there are 12 standards files covering architecture, testing, git, database, security, logging, etc. Read them all.
2. Read `CLAUDE.md` — project-specific rules (contains build commands, test commands, project structure)
3. Read `ARCHITECTURE.md` — system design, database schema, design rationale

Do NOT write any code until all three steps are complete.

## Critical Constraints Reminder

All rules from the 12 standards files apply — you loaded them in the Context Loading step above. The most commonly violated rules involve: Domain zero-dependency, Dapper-only, no mocking frameworks, hand-rolled fakes, no Co-Authored-By. When in doubt, re-check the standards files.

## Implementation Workflow (Initial Mode)

### 1. EXPLORE (before writing code)
- Read all existing code in the affected area
- Understand the patterns already established for this component
- Check the Fakes project for existing fakes you'll need or need to extend
- Identify which files need to change and what new files are needed

### 2. PLAN (before writing code)
- Determine implementation approach based on existing patterns in the codebase
- Verify the approach respects the build order: Domain -> Fakes -> Infrastructure -> Api
- If anything is architecturally ambiguous, note it in your report — do your best interpretation but flag it

### 3. IMPLEMENT
- Follow the build order — don't jump ahead
- Write fakes for any new interfaces immediately
- Write tests alongside each piece of implementation, not after

### 4. TEST

Use the build and test commands from the project's `CLAUDE.md`:
- Build the full solution
- Run the relevant test project(s)
- All tests must pass — both new and existing
- If tests fail, fix them. You have 3 attempts to fix failing tests before reporting as partial.
- Confirm the full solution builds with no errors

### 5. COMMIT & PUSH
- Stage specific files by name (never `git add .`)
- Commit message format: `{STORY_ID}: Concise description of why this change was made`
- Push the branch: `git push -u origin {BRANCH_NAME}`

### 6. CREATE PULL REQUEST

Create a PR targeting `main`:

```bash
gh pr create --base main --head {BRANCH_NAME} --title "{STORY_ID}: {TICKET_TITLE}" --body "$(cat <<'EOF'
## Summary

[1-3 bullet points describing what this PR does]

## Changes

| File | Change |
|------|--------|
| `path/to/file.cs` | Description of change |

## Decisions

- [Any pattern choices or trade-offs made during implementation]

## Test Coverage

- New tests: [count]
- All unit tests pass: yes/no
- Full solution builds: yes/no

Relates to #{ISSUE_NUMBER}
EOF
)"
```

### 7. POST ISSUE COMMENT (Audit Trail)

Post a comment on the issue:

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
## Implementation Complete

**PR:** #[PR_NUMBER] ([link])
**Files changed:** [count]
**Tests added:** [count]

**Key decisions:**
- [List decisions made during implementation]

**Status:** Ready for engineering review
EOF
)"
```

### 8. CLEANUP: Return to main and remove branch

After the PR is created and pushed, return to `main` so the machine is clean for the next task. The branch is safely attached to the PR — keeping it checked out locally risks the next agent mistaking it for the default branch. Delete both the local and remote branch to prevent stale branch accumulation.

```bash
git checkout main
git pull --ff-only
git branch -d {BRANCH_NAME}
git push origin --delete {BRANCH_NAME}
```

### 9. REPORT

Return your results in this exact format:

```
STATUS: Complete | Partial | Blocked
MODE: initial
TICKET: {STORY_ID}
BRANCH: {BRANCH_NAME}
PR_NUMBER: [number]

CHANGES:
- path/to/file.cs: what changed and why

TESTS:
- New tests written: [count]
- All unit tests pass: yes/no
- Full solution builds: yes/no
- Integration tests needed: yes/no (reason)

DECISIONS:
- Any pattern choices, trade-offs, or interpretations of ambiguous requirements

CONCERNS:
- Anything that felt wrong, might need revisiting, or affects future tickets

BLOCKED_REASON: (only if STATUS is Blocked)
- What's blocking and what decision is needed
```

If STATUS is Blocked, explain clearly what decision or dependency you need. Do NOT guess or improvise around blockers.

---

## Fix Mode (When `{FIX_MODE}` is `true`)

When invoked with `{FIX_MODE}=true`, you are addressing review feedback on an existing PR. Do NOT re-explore or re-plan from scratch.

### Provided by orchestrator:
- **PR Number:** {PR_NUMBER}
- **Iteration:** {ITERATION}
- **Story ID:** {TICKET_NUMBER}
- **Branch:** {BRANCH_NAME}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}

### Fix Workflow:

1. **Load standards** — Read `../TI-Engineering-Standards/CLAUDE.md` and all 12 standards files, `CLAUDE.md`, `ARCHITECTURE.md`

2. **Fetch review comments** — Get the PR review comments:
   ```bash
   gh api repos/{REPO_OWNER}/{REPO_NAME}/pulls/{PR_NUMBER}/comments --jq '.[] | {path: .path, line: .line, body: .body}'
   ```
   Also check the PR reviews for top-level review bodies:
   ```bash
   gh api repos/{REPO_OWNER}/{REPO_NAME}/pulls/{PR_NUMBER}/reviews --jq '.[] | select(.state == "CHANGES_REQUESTED") | {body: .body}'
   ```

3. **Parse feedback** — For each comment, identify:
   - The file and line being discussed
   - The specific standards violation or issue
   - The required fix

4. **Read affected files** — Read each file mentioned in the review comments

5. **Apply fixes** — Address each review comment. Follow the standards exactly.

6. **Build & test** — Run the full build and all relevant test suites. Fix any failures (3 attempts max).

7. **Commit & push** — Stage specific files, commit with message:
   ```
   {STORY_ID}: Address review feedback (iteration {ITERATION})
   ```
   Push to the existing branch (the PR updates automatically):
   ```bash
   git push origin {BRANCH_NAME}
   ```
   Do NOT create a new PR — the existing PR #{PR_NUMBER} will show the new commits.

8. **Cleanup: Return to main and remove branch** — Switch back to `main` and delete the branch (local + remote) so the machine is clean for the next task:
   ```bash
   git checkout main
   git pull --ff-only
   git branch -d {BRANCH_NAME}
   git push origin --delete {BRANCH_NAME}
   ```

9. **Report**:
   ```
   STATUS: Complete | Partial | Blocked
   MODE: fix
   TICKET: {STORY_ID}
   BRANCH: {BRANCH_NAME}
   PR_NUMBER: {PR_NUMBER}
   ITERATION: {ITERATION}

   FIXES_APPLIED:
   - path/to/file.cs:line — description of fix

   TESTS:
   - All unit tests pass: yes/no
   - Full solution builds: yes/no

   UNRESOLVED:
   - Any review comments that could not be addressed and why
   ```

---
<!-- skill-version: 3.0 -->
<!-- last-updated: 2026-03-05 -->
<!-- pipeline: v3 -->
