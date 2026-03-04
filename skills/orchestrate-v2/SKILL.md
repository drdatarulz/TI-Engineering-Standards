---
name: orchestrate-v2
description: "PR-based pipeline orchestrator with engineering review gates. Refine → Implement (PR) → Review loop → Integration Tests (PR) → Review loop → Merge → Close."
disable-model-invocation: true
argument-hint: "[supervised|autonomous] [ticket list, e.g. AZ-017, AZ-018]"
---

You are the **v2 orchestrator** for this session. Your job is to implement GitHub Project tickets sequentially using a PR-based pipeline with engineering review gates. You stay lightweight — you manage the pipeline, board updates, review loops, and sequencing. Subagents do the work.

## Pipeline Per Ticket

```
1. REFINE STORY ─────────── refine-story-v2 (updates issue spec)
2. IMPLEMENT ────────────── implement-ticket-v2 (creates PR #1)
3. REVIEW (implementation) ─ engineering-review (standards + build + unit tests)
   └─ Loop: reviewer ↔ implementer (max 3 iterations)
   └─ On approve → merge PR #1
4. INTEGRATION TESTS ────── integration-test (branches from updated main, creates PR #2)
5. REVIEW (integration) ─── engineering-review (test quality + tests pass)
   └─ Loop: reviewer ↔ test-writer (max 3 iterations)
   └─ On approve → merge PR #2
6. CLOSE ────────────────── close issue, update board
```

## Parse Arguments

Parse `$ARGUMENTS` as follows:

1. **Mode**: If the first word is `supervised` or `autonomous`, use it as the mode and consume it. Otherwise, default to `supervised`.
2. **Ticket list**: Everything remaining is the ticket list. Tickets are separated by commas. They may be in any format (e.g., `AZ-017`, `AZ-018 #45`, `AZ-019`).

If no tickets are provided, ask the user what tickets to implement.

## Step 0: Load Context (Once Per Session)

### 0a. Resolve Project Identity

```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
```

Store `REPO_OWNER` and `REPO_NAME` — you'll use them for all commands.

### 0b. Sync Standards & Read Config

1. Sync the standards repo:
   - If `../TI-Engineering-Standards/` exists: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
   - If not: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
2. Read `../TI-Engineering-Standards/CLAUDE.md` (skim — subagents get the details)
3. Read `CLAUDE.md` — extract:
   - **Build command** (e.g., `dotnet build AgentZula.slnx`)
   - **Test commands** (unit + integration)
   - **Story ID prefix**
   - **Branch naming pattern**
   - **GitHub Project Board URL**
4. Read `ARCHITECTURE.md`

### 0c. Resolve Project Board IDs

Extract the project number from the board URL in CLAUDE.md, then query:

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

### 0d. Resolve Ticket Issue Numbers

For each ticket in the list, if the GitHub issue number isn't provided, search for it:

```bash
gh issue list --repo REPO_OWNER/REPO_NAME --search "STORY_ID in:title" --json number,title --jq '.[0].number'
```

---

## Per-Ticket Pipeline

For EACH ticket, execute these 6 stages:

---

### Stage 1: REFINE STORY

#### 1a. Pre-flight
- `git checkout main && git pull origin main`
- Verify git hooks: If `.githooks/` exists, run `git config --local core.hooksPath .githooks`

#### 1b. Spawn refine-story-v2

Read `.claude/skills/refine-story-v2/SKILL.md` and substitute:
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID (e.g., AZ-017)
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{ORCHESTRATOR_MODE}` → `true`

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 1c. Process result

- If `STATUS: AlreadyRefined` — continue to Stage 2
- If `STATUS: Refined` — continue to Stage 2
- If `STATUS: NeedsManualReview` — move issue to Waiting/Blocked, post comment, skip this ticket

---

### Stage 2: IMPLEMENT

#### 2a. Pre-flight
- `git checkout main && git pull origin main`
- Create branch: `git checkout -b story/{STORY_ID}-short-name main` (use `fix/` for bugs, `task/` for tasks)
- Move issue to In Progress on the project board

#### 2b. Spawn implement-ticket-v2

Read `.claude/skills/implement-ticket-v2/SKILL.md` and substitute:
- `{TICKET_NUMBER}` → the story ID (e.g., AZ-017)
- `{STORY_ID}` → the story ID (same value as TICKET_NUMBER)
- `{TICKET_TITLE}` → the ticket title
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{BRANCH_NAME}` → the branch just created
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{FIX_MODE}` → `false`
- `{PR_NUMBER}` → (leave as literal — not in fix mode)
- `{ITERATION}` → `0`

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 2c. Process result

- If `STATUS: Complete` — extract `PR_NUMBER` from report, continue to Stage 3
- If `STATUS: Partial` — post issue comment describing what's incomplete, move to Waiting/Blocked, skip this ticket
- If `STATUS: Blocked` — post issue comment with blocker, move to Waiting/Blocked, skip this ticket

---

### Stage 3: REVIEW (Implementation)

Run a review loop: reviewer checks → if changes requested → implementer fixes → reviewer re-checks. Max 3 iterations.

#### 3a. Spawn engineering-review

Read `.claude/skills/engineering-review-v2/SKILL.md` and substitute:
- `{PR_NUMBER}` → the implementation PR number
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID
- `{BRANCH_NAME}` → the implementation branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{MODE}` → `implementation`
- `{ITERATION}` → current iteration (starting at 1)

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 3b. Process review result

**If `STATUS: Approved`:**
- Post issue comment: "Implementation review approved after {N} iteration(s). Merging PR #{PR_NUMBER}."
- Merge the PR:
  ```bash
  gh pr merge {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --merge --delete-branch
  ```
- Pull main: `git checkout main && git pull origin main`
- Delete local branch: `git branch -d {BRANCH_NAME} 2>/dev/null`
- Continue to Stage 4

**If `STATUS: ChangesRequested` and iteration < 3:**
- Post issue comment: "Review iteration {N}: {VIOLATIONS} issues found. Sending back for fixes. See PR #{PR_NUMBER} comments."
- Spawn implement-ticket-v2 in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the implementation PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 2
- After fix completes, loop back to 3a with incremented iteration

**If `STATUS: ChangesRequested` and iteration >= 3:**
- Post issue comment: "Review loop exhausted after 3 iterations. Moving to Waiting/Blocked for manual attention."
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 4: INTEGRATION TESTS

#### 4a. Pre-flight
- Ensure on main with latest: `git checkout main && git pull origin main`
- Create integration test branch: `git checkout -b story/{STORY_ID}-integration-tests main`

#### 4b. Spawn integration-test

Read `.claude/skills/integration-test-v2/SKILL.md` and substitute:
- `{STORY_ID}` → the story ID
- `{TICKET_TITLE}` → the ticket title
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{BRANCH_NAME}` → the integration test branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{IMPLEMENTATION_PR}` → the merged implementation PR number
- `{FIX_MODE}` → `false`
- `{PR_NUMBER}` → (leave as literal — not in fix mode)
- `{ITERATION}` → `0`

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 4c. Process result

- If `STATUS: Complete` — extract `PR_NUMBER` from report, continue to Stage 5
- If `STATUS: Partial` or `STATUS: Blocked` — post issue comment, move to Waiting/Blocked, skip remaining stages

---

### Stage 5: REVIEW (Integration Tests)

Same review loop structure as Stage 3, but in `integration-tests` mode.

#### 5a. Spawn engineering-review

Read `.claude/skills/engineering-review-v2/SKILL.md` and substitute:
- `{PR_NUMBER}` → the integration test PR number
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID
- `{BRANCH_NAME}` → the integration test branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{MODE}` → `integration-tests`
- `{ITERATION}` → current iteration (starting at 1)

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 5b. Process review result

**If `STATUS: Approved`:**
- Post issue comment: "Integration test review approved after {N} iteration(s). Merging PR #{PR_NUMBER}."
- Merge the PR:
  ```bash
  gh pr merge {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --merge --delete-branch
  ```
- Pull main: `git checkout main && git pull origin main`
- Delete local branch: `git branch -d {BRANCH_NAME} 2>/dev/null`
- Continue to Stage 6

**If `STATUS: ChangesRequested` and iteration < 3:**
- Post issue comment: "Integration test review iteration {N}: {VIOLATIONS} issues found. Sending back for fixes."
- Spawn integration-test in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the integration test PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 4
- After fix completes, loop back to 5a with incremented iteration

**If `STATUS: ChangesRequested` and iteration >= 3:**
- Post issue comment: "Integration test review loop exhausted after 3 iterations. Moving to Waiting/Blocked."
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 6: CLOSE

- Check off ALL acceptance criteria checkboxes in the issue body via `gh issue edit`
- Post final issue comment:
  ```
  ## Story Complete

  **Implementation PR:** #{IMPL_PR} (merged)
  **Integration Test PR:** #{TEST_PR} (merged)
  **Review iterations (implementation):** {N}
  **Review iterations (integration tests):** {N}

  All acceptance criteria verified. Closing issue.
  ```
- Close the issue: `gh issue close {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME}`
  (Board automation moves it to Done)

---

## Supervised Mode Gate

**If MODE is `supervised`, you MUST stop between tickets (not between stages).** After completing all 6 stages for a ticket (or after a ticket is skipped/blocked), output your check-in report and end with exactly:

**Waiting for approval. Say "proceed" to continue to the next ticket.**

The next ticket DOES NOT START until the user replies. This is a hard gate. If you find yourself typing "Now starting the next ticket" in supervised mode, STOP.

In `autonomous` mode, skip this gate and continue to the next ticket.

---

## Circuit Breakers (Orchestrator Halts Entirely)

Even in autonomous mode, **STOP the entire loop** if:
- **3 consecutive tickets are Blocked or Partial** — something systemic is wrong
- **A PR merge conflict occurs** — needs human judgment
- **Build fails on main after a merge** — main is corrupted
- **3 review iterations exhausted** on a single ticket — already handled per-ticket, but if this happens on 2 consecutive tickets, halt

When halted, report the full session summary and explain why you stopped.

---

## Session Summary (Final Report)

After all tickets are processed (or the loop is halted), produce this summary:

```
## Session Summary

### Completed
| Ticket | Title | Impl PR | Test PR | Review Iters (Impl) | Review Iters (Test) | Tests Added |
|--------|-------|---------|---------|---------------------|---------------------|-------------|
| AZ-XXX | ... | #N | #N | N | N | N |

### Partial
| Ticket | Title | What Remains |
|--------|-------|-------------|
| AZ-YYY | ... | [description] |

### Blocked
| Ticket | Title | Blocker |
|--------|-------|---------|
| AZ-ZZZ | ... | [what's needed] |

### Skipped
| Ticket | Title | Reason |
|--------|-------|--------|
| AZ-AAA | ... | [why skipped] |

### Stats
- Tickets completed: X / Y
- Tickets partial: X
- Tickets blocked: X
- Total implementation PRs merged: X
- Total integration test PRs merged: X
- Total review iterations: X
- Total tests added: X
- Total files changed: X
```

---
<!-- skill-version: 2.0 -->
<!-- last-updated: 2026-03-04 -->
<!-- pipeline: v2-pr-based -->
