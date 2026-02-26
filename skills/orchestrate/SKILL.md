---
name: orchestrate
description: Sequentially implement multiple GitHub Project tickets by spawning a subagent per ticket. Handles pre-flight, board updates, merging, and session summary.
disable-model-invocation: true
argument-hint: "[supervised|autonomous] [ticket list, e.g. DS-116, DS-117]"
---

You are the **orchestrator** for this session. Your job is to implement GitHub Project tickets sequentially by spawning a fresh subagent for each ticket. You stay lightweight — you manage the loop, board updates, and sequencing. Subagents do the implementation.

## Parse Arguments

Parse `$ARGUMENTS` as follows:

1. **Mode**: If the first word is `supervised` or `autonomous`, use it as the mode and consume it. Otherwise, default to `supervised`.
2. **Ticket list**: Everything remaining is the ticket list. Tickets are separated by commas. They may be in any format (e.g., `TX-116`, `TX-117 #117`, `DS-042`).

If no tickets are provided, ask the user what tickets to implement.

## Step 0: Load Context (Orchestrator Only)

Before starting the ticket loop, resolve the project context and read these files:

### 0a. Resolve Project Identity

```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
```

Store `REPO_OWNER` and `REPO_NAME` — you'll use them for all `gh` commands.

### 0b. Read Project Config

1. Sync the standards repo:
   - If `../TI-Engineering-Standards/` exists: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
   - If not: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
2. Read `../TI-Engineering-Standards/CLAUDE.md` (skim — you need the overview, subagents get the details)
3. Read `CLAUDE.md` — extract these project-specific values:
   - **Build command** (e.g., `dotnet build ProjectName.slnx`)
   - **Test command** (e.g., `dotnet test tests/ProjectName.Api.Tests/`)
   - **Story ID prefix** (from the Work Tracking section)
   - **Branch naming** (from the Work Tracking section)
   - **GitHub Project Board URL** (from the Work Tracking section)
   - **Merge strategy** (from Things NOT To Do — e.g., "merge directly into main" vs "create PRs")
4. Read `ARCHITECTURE.md`

### 0c. Resolve Project Board IDs

Look up the GitHub Project board IDs dynamically. Extract the project number from the board URL in CLAUDE.md, then query:

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

## Orchestrator Loop

For EACH ticket, execute these steps:

### 1. PRE-FLIGHT (orchestrator does this — MANDATORY CHECKLIST)

Execute ALL of these before spawning the subagent:
- [ ] **Read the ticket:** `gh issue view {number} --repo {REPO_OWNER}/{REPO_NAME}` — understand scope and acceptance criteria
- [ ] **Update main:** `git pull origin main`
- [ ] **Verify git hooks:** If `.githooks/` exists, run `git config --local core.hooksPath .githooks`
- [ ] **Create branch:** `git checkout -b story/{STORY_ID}-short-name main` (use `fix/` for bugs, `task/` for tasks)
- [ ] **Move to In Progress:** Update the ticket status on the GitHub Project board to **In Progress**

### 2. SPAWN SUBAGENT (one per ticket)

Read `.claude/skills/implement-ticket/SKILL.md` and substitute the following placeholders with actual values from this ticket:
- `{TICKET_NUMBER}` — the story ID (e.g., TX-116)
- `{TICKET_TITLE}` — the ticket title
- `{ISSUE_NUMBER}` — the GitHub issue number (e.g., 118)
- `{BRANCH_NAME}` — the branch you just created

**IMPORTANT — Context Size:** Do NOT pass the full ticket body in the prompt. Pass only the issue number and let the subagent fetch the ticket itself via `gh issue view`. This keeps the initial prompt small and avoids API errors from oversized context.

Pass the resulting prompt to the Task tool with `subagent_type: "general-purpose"`.

### 3. PROCESS RESULT (orchestrator does this — MANDATORY CHECKLIST)

After the subagent returns, you MUST complete every checked item before moving to the next ticket. Do NOT skip any step.

**If Complete — execute ALL of these in order:**
- [ ] **Verify build:** Run the project's build command — confirm 0 errors
- [ ] **Verify tests:** Run the project's test command — confirm all pass
- [ ] **Update issue body:** Check off ALL acceptance criteria checkboxes in the issue body via `gh issue edit`
- [ ] **Add completion comment:** Post a comment on the issue with: changes summary, test results, files changed (use `gh issue comment`)
- [ ] **Merge to main:** `git checkout main && git merge {BRANCH_NAME} --no-ff -m "Merge {BRANCH_NAME}"`
- [ ] **Delete branch:** `git branch -d {BRANCH_NAME}`
- [ ] **Push (autonomous mode only):** `git push origin main`
- [ ] **Close the issue:** `gh issue close {number} --repo {REPO_OWNER}/{REPO_NAME}` — board automation moves it to Done

**If Partial — execute ALL of these:**
- [ ] **Add comment on issue:** Describe what was completed and what remains (use `gh issue comment`)
- [ ] **Do NOT merge** — leave the branch as-is

**If Blocked — execute ALL of these:**
- [ ] **Move to Waiting/Blocked:** Update status on the Project board
- [ ] **Add comment on issue:** Describe the blocker and what decision is needed (use `gh issue comment`)
- [ ] **Do NOT merge** — leave the branch as-is

---

### >>> SUPERVISED MODE GATE — READ THIS <<<

**If MODE is `supervised`, you MUST stop here.** Do NOT start the next ticket. Do NOT proceed. Do NOT "continue" or "move on."

Output your check-in report for the completed ticket, then end your message with exactly:

**Waiting for approval. Say "proceed" to continue to the next ticket.**

The next ticket DOES NOT START until the user replies. This is a hard gate, not a suggestion. If you find yourself typing "Now starting the next ticket" in supervised mode, STOP — you are violating this rule.

In `autonomous` mode, skip this gate and continue to the next ticket.

---

## Stop Conditions (Orchestrator Halts Entirely)

Even in autonomous mode, **STOP the entire loop** if:
- **3 consecutive tickets are Blocked or Partial** — something systemic is wrong
- **A subagent corrupts main** — build fails on main after a merge
- **A ticket's changes conflict with a previous ticket's branch** — merge conflict that needs human judgment

When halted, report the full session summary and explain why you stopped.

## Session Summary (Final Report)

After all tickets are processed (or the loop is halted), produce this summary:

```
## Session Summary

### Completed
| Ticket | Title | Branch | Tests Added |
|--------|-------|--------|-------------|
| XX-XXX | ... | story/XX-XXX-... | 5 |

### Partial
| Ticket | Title | What Remains |
|--------|-------|-------------|
| XX-YYY | ... | [description] |

### Blocked
| Ticket | Title | Blocker |
|--------|-------|---------|
| XX-ZZZ | ... | [what's needed] |

### Skipped
| Ticket | Title | Reason |
|--------|-------|--------|
| XX-AAA | ... | [why skipped] |

### Stats
- Tickets completed: X / Y
- Tickets partial: X
- Tickets blocked: X
- Total tests added: X
- Total files changed: X
```
