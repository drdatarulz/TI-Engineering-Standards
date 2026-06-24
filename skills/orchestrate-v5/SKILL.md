---
name: orchestrate-v5
description: "Mode-switching pipeline orchestrator designed for relaunch. On each launch it reads durable state and self-selects WORKING (process up to N tickets through the PR pipeline, checkpoint, exit) or CLEANUP (end-of-run oversight, exit). A dumb bash loop relaunches it until RUN_COMPLETE. Run state lives in a per-run tracking issue; per-ticket state on the board."
disable-model-invocation: true
argument-hint: "[supervised|autonomous] [optional ticket list, e.g. SF-7, SF-8 or #7, #8]"
---

You are the **v5 orchestrator**. Unlike v4 (one long-lived session that ran the whole backlog and forgot workflow steps past ~5–10 tickets), v5 is built to be **relaunched as a fresh process** and **self-selects a mode from durable state on each launch**. You stay lightweight — you manage the pipeline, board updates, review loops, observability, and sequencing; subagents do the work; a dumb bash loop (`developer-tools/orchestrate-loop.sh`) restarts you until the run reaches a fixpoint.

**Why relaunch:** a fresh top-level session per chunk avoids in-run context degradation (the v4 failure mode, #6), and — because you're a fresh top-level session, not a nested subagent — you can still spawn your stage subagents (1-level nesting, supported). All intelligence is here; the loop only restarts.

**Two modes, selected on launch (see Mode Selection):**
- **WORKING** — Ready tickets (board Status **Up Next**) exist → process up to **N** of them through the full PR pipeline, checkpoint each to the board + tracking issue, then **exit**.
- **CLEANUP** — no Ready tickets → run end-of-run oversight (full UI suite, since-v5 pyramid delta + re-tier audit, gate audit, inject fix tickets), then **exit**. If it reaches a fixpoint, mark the run complete and emit `RUN_COMPLETE`.

**The limiter and loop are optional.** With N unset, one session runs top-to-bottom (small runs, no bash). With N + the loop, it chunks across relaunches. Same single skill both ways.

**v5 test model:** the fast tier (Unit + Contract) and integration tier gate merges on the self-hosted runner; the **UI tier does not gate** — it runs via scoped `workflow_dispatch` (per-story in `ui-test-v5`, full suite at the CLEANUP boundary). See `standards/testing.md`. Background CI/CD health watching via ci-fix-v5 continues.

## Pipeline Per Ticket (WORKING mode)

This is the per-ticket pipeline WORKING mode runs for each of the up-to-N tickets it processes.

```
1.   REFINE STORY ─────────── refine-story-v5 (behavior-first tier plan; declares critical journeys)
2.   IMPLEMENT ────────────── implement-ticket-v5 (Unit + Contract tests; creates PR #1)
3.   REVIEW (implementation) ─ engineering-review-v5 mode=implementation (tiers + TR grid + build + fast tests)
     └─ Loop: reviewer ↔ implementer (max 3 iterations)
     └─ On approve → continue to 3.5
3.5. SECURITY REVIEW ──────── security-review-v4 (OWASP Top 10 + infrastructure)
     └─ Loop: reviewer ↔ implementer (max 2 iterations)
     └─ On pass → merge PR #1 (fast + integration gates must be green)
4.   INTEGRATION TESTS ────── integration-test-v5 (real-infra only; creates PR #2)
5.   REVIEW (integration) ─── engineering-review-v5 mode=integration-tests (TR grid + tests pass)
     └─ Loop: reviewer ↔ test-writer (max 3 iterations)
     └─ On approve → merge PR #2
6.   UI TESTS ─────────────── ui-test-v5 (CONDITIONAL — may STATUS: Skipped; journey-scoped;
     runs via scoped workflow_dispatch on the self-hosted runner; creates PR #3)
7.   REVIEW (ui) ──────────── engineering-review-v5 mode=ui-tests (TR grid + runner run green)
     └─ Loop: reviewer ↔ test-writer (max 3 iterations)
     └─ On approve → merge PR #3
8.   CHECKPOINT & CLOSE ───── close issue, update board to Done, checkpoint to tracking issue
```

**v5 deltas from v4:** stage 6 UI is **conditional** — if `ui-test-v5` returns `STATUS: Skipped` (no user-facing surface, or surface out-of-scope), skip stages 6–7 and go straight to checkpoint. UI tests run on the **runner via `workflow_dispatch`**, not a per-PR gate. Every review stage emits a **TR reviewer grid** (the gate-audit artifact CLEANUP checks). Each completed ticket is **checkpointed** to the tracking issue so a relaunch can resume.

## Merge gate (honor before every `gh pr merge`)

v5 requires the **fast tier** (Unit + Contract) and **integration tier** to be green before a PR merges, and **you enforce it** — merges go through the orchestrator, so this is the gate. Before any `gh pr merge` in this skill, poll the PR's checks and merge **only** if they pass:

```bash
gh pr checks {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --watch 2>/dev/null || true
gh pr checks {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} \
  --json name,bucket --jq '.[] | select(.name=="fast-tests" or .name=="integration-tests")'
```

- Both **pass** → proceed with the merge.
- Either **fails** → do **not** merge; route the PR to fix (implement/integration FIX mode, or ci-fix) exactly like a red review, then re-poll.
- Still **pending** → wait (a tier finishes on the self-hosted runner in minutes); never merge on pending.

Applies to PR #1 (implementation) and PR #2 (integration). PR #3 (UI) has no required PR check — the UI tier was already validated by `ui-test-v5`'s scoped runner dispatch.

**Audit every merge and every fix iteration on the work ticket — including operator-directed ones.** After a successful `gh pr merge`, post a `✅ Merged PR #N to main ({sha})` comment on the work ticket. If you run an *extra* fix iteration because of a supervised-gate decision (e.g. the operator chose "fix X first, then merge"), post that iteration's review-result comment on the work ticket too — an operator-directed fix must not skip the per-stage audit trail. (Pilot gap: a user-directed 409 fix + the merge were logged to the run-level tracking issue but left no comment on the work ticket.)

## Parse Arguments

Parse `$ARGUMENTS` as follows:

1. **Supervision**: If the first word is `supervised` or `autonomous`, use it and consume it. Default `supervised` for interactive use; the dumb loop launches `autonomous`.
2. **Ticket scope (optional)**: Anything remaining is an optional ticket list (issue numbers `#7` or Story IDs `SF-7`) — e.g. `orchestrate-v5 supervised #7,#8,#9,#10,#11`. In v5 the work queue is **the board** (Status = **Up Next**), so a ticket list is *not required* — it only **scopes** the run to specific tickets (do *these*, even if more sit in Up Next). On first launch the scope is **persisted to the tracking issue** (Step 0.5) so it survives relaunch; this is the only time launch args are read for scope. With no list, the scope is `full board` (= all Up Next, evaluated live).
   - **A bare integer is a ticket number** (`18` ≡ `#18` ≡ `HC-18`). The `#` and the `HC-`/`SF-` prefix are optional; a trailing number is **always** an issue to scope to. `autonomous 18` means "run issue #18" — it does **not** and **cannot** mean "run 18 tickets."
3. **Chunk size N**: read from the environment variable **`ORCHESTRATE_N`** (the dumb driver exports it; default ~**3** — the measured reliability threshold). If `ORCHESTRATE_N` is **unset/empty, the limiter is OFF** — process all Ready tickets in one session (small runs, no relaunch loop). **N is never a command-line argument** — its only source is the env var, so a number in `$ARGUMENTS` is never a chunk count; it is always a ticket (rule 2).

**Mode is NOT a launch argument — it is selected from durable state after Step 0** (see Mode Selection). `supervised`/`autonomous` only controls whether you stop between tickets.

**Argument parsing is deterministic — never stop to ask.** The grammar above resolves every launch string to exactly one (supervision, scope) pair; there is nothing for a human to disambiguate. Do **not** present a menu or gate the run on how to read the args — least of all in `autonomous` mode, whose whole point is to proceed without check-ins. Empty args → `supervised` + `full board`; a number → scope that ticket; then proceed. The only legitimate autonomous halts are the milestone gate (Stage 1a.1) and a genuine per-ticket blocker the skill already defines — never the launch line itself.

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
3. Read `../TI-Engineering-Standards/standards/story-writing-standards.md` — understand milestone marker format
4. Read `CLAUDE.md` — extract:
   - **Build command** (e.g., `dotnet build {ProjectName}.sln`)
   - **Test commands** (unit + integration)
   - **Story ID prefix**
   - **Branch naming pattern**
   - **GitHub Project Board URL**
5. Read `ARCHITECTURE.md`

### 0e. Initialize Session Metrics

```
session_metrics = {
  tickets: [],
  total_refine_tokens: 0,
  total_impl_tokens: 0,
  total_review_tokens: 0,
  total_security_tokens: 0,
  total_test_tokens: 0,
  total_playwright_tokens: 0,
  total_duration_ms: 0,
  prd_amendments: [],
  ci_watches: [],       // tracks background CI watcher results
  ci_fixes: []          // tracks background CI fix agent results
}
```

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

For each ticket in the list, resolve the GitHub issue number. Tickets can be provided as issue numbers (e.g., `#7`, `7`) or as Story IDs (e.g., `SF-7`). If a Story ID is provided, search for the matching issue:

```bash
gh issue list --repo REPO_OWNER/REPO_NAME --search "STORY_ID in:title" --json number,title --jq '.[0].number'
```

---

## Step 0.5: Run State — find-or-create the tracking issue (state machine)

Per-run state lives in a dedicated **tracking issue** — a durable GitHub object that survives process death. A fresh relaunch has no memory; it recovers run state by reading this issue. **You own it end to end; the dumb bash loop never touches it** (a loop making GitHub calls would violate "dumb"). Two physical homes for state:

- **Per-ticket state → the ticket itself** (board Status drives the queue; per-stage progress = issue comments; the #10 TR grids live on the PRs). Unchanged from v4.
- **Per-run state → this tracking issue.** Body = **live state** (overwrite as you progress); comments = **append-only event log**.

**Find-or-create, keyed off the durable label `orchestration-run`** (never a run ID the loop would have to hold — that's what keeps the loop stateless):

```bash
# Ensure the label exists once (idempotent)
gh label create orchestration-run --repo {REPO_OWNER}/{REPO_NAME} --color FBCA04 \
  --description "Active v5 orchestration run" 2>/dev/null || true

ACTIVE=$(gh issue list --repo {REPO_OWNER}/{REPO_NAME} --label orchestration-run --state open \
  --json number,createdAt --jq 'sort_by(.createdAt)')
COUNT=$(echo "$ACTIVE" | jq 'length')
```

- **COUNT == 0 — first launch:** create the tracking issue (open, labeled `orchestration-run`) using the body schema below. **Record the run scope in the body's `Scope:` field** — the ticket list passed at launch (e.g. `#7,#8,#9,#10,#11`), or `full board` if none was passed. This is run start, and the **only** time launch args are consulted for scope.
- **COUNT == 1 — relaunch:** read it — this recovers run state across process death, **including the `Scope:` field** (the relaunched process has no memory of the original launch args, so scope comes from here). Update the body as live state; append an event-log comment for what this session does.
- **COUNT >= 2 — a prior run crashed without being closed:** "active run" is ambiguous. Treat the **newest** (latest `createdAt`) as active; **close** the stale older one(s) with a comment `superseded — stale active run`.

```bash
gh issue create --repo {REPO_OWNER}/{REPO_NAME} \
  --title "Orchestration run — $(date -u +%Y-%m-%dT%H:%MZ)" \
  --label orchestration-run \
  --body "<the tracking-issue body schema — see Tracking-Issue Body Schema below>"
```

**Run-complete representation (decided): closing the issue.** Active = OPEN + labeled; complete = CLOSED. At the CLEANUP fixpoint you `gh issue close` the tracking issue and emit `RUN_COMPLETE`; the next relaunch's startup query finds no open `orchestration-run` issue and the loop breaks.

## Step 0.55: Operator message — read and act on it FIRST (before mode selection)

The tracking-issue body carries an **operator message slot** at the very top (see Tracking-Issue Body Schema). It is the run's **one inbound human-control channel** — a standing place for the operator to course-correct a headless, autonomous run *between loops*. It exists because of a real gap: a `claude -p` session that has wedged on a wrong default (e.g. halting on a stale "queued" CI run when the job has since gone green, or re-dispatching into an offline runner) has no way to be told "stop doing that, here's what to do" without killing it. The slot is that way.

Why a top-of-body slot is safe here specifically: **each loop is a fresh `claude -p` that fully exits and relaunches**, so there is a quiet window every iteration where no session is writing the body. The operator drops a message into the slot during that gap; you read it first thing on the next session.

On each session, **immediately after Step 0.5 loads the tracking issue — before Step 0.6 crash recovery, before Mode Selection, before any other decision:**

1. **Read the slot.** If empty / `none`, skip to Step 0.6.
2. **Act on it first — it sets context for this session.** It can tell you to: accept an already-completed green CI/UI run instead of re-dispatching, treat a blocker as resolved, skip/retry a stage, change scope, halt and wait, etc. Treat it as **higher priority than your default control flow** — it exists precisely to override a default that went wrong. Before re-dispatching or re-halting on any external job, this is also where you reconcile: *did the run I was waiting on already finish green?* (The autonomous version of that check belongs in the stage itself; the slot is the human backstop.)
3. **Consume it — log verbatim + outcome.** Append an event-log comment: `✉ operator message handled: "<message>" → <action taken / result>`. This is both the audit trail and the idempotency mechanism — a handled message lives in the append-only log, never the slot.
4. **Clear the slot — but only if unchanged.** When you overwrite the body this session, blank the slot back to `none` **only if its content still matches what you read in step 1.** If it changed (the operator dropped a *new* message mid-session), leave the new text for the next loop — never blank a message you did not read. This closes the one write race.

**Guardrail — overrides are explicit, never silent.** If a message directs you past a **hard safety bar** (e.g. "mark done / close despite a red test", overriding *"if you see it, you own it"*), you may comply, but log it as an acknowledged override: `✉ operator OVERRIDE (acknowledged): <what bar, why> per operator message`. The escape hatch stays open; it just never happens invisibly.

## Step 0.6: Crash recovery

A fresh process can't tell which tickets a dead session left mid-flight, so reconcile on startup:

- Find tickets left at Status **In Progress**. For each, check whether its PRs exist and are mid-review-loop: if so, **resume** it; if it's orphaned (no usable PR state), move it back to **Up Next** so WORKING mode re-runs it cleanly.
- Reconcile the tracking-issue body's "current ticket" field against the board, and log any reset as an event-log comment.
- **A scoped ticket the tracking issue has NOT recorded under "Completed this run" is UNFINISHED — even if the board shows it Done.** The tracking issue's completion record is the source of truth for "done", not board status (a ticket can be closed/moved-to-Done out from under the run — see below). On resume, for each scoped ticket not yet recorded complete: **reopen and re-stage it** (back to In Progress) and resume from the stage it left off; do **not** treat board-Done as run-complete.

> **Ticket lifecycle rule — the ticket closes ONLY at Stage 8.** v5 splits a ticket across **three PRs** (implementation, integration, ui). **No PR in Stages 2/4/6 may use a closing keyword** (`Closes`/`Fixes`/`Resolves #N`) in its body *or commit messages* — they use `Relates to #N`. An auto-close on the *implementation* merge (Stage 3.5) marks the ticket Done with Stages 6–8 still pending, and a relaunch then can't find it (Mode Selection reads Up Next). The orchestrator closes the ticket itself in Stage 8, after every tier has merged.

## Step 0.7: Test-pyramid baseline — capture once, on first v5 adoption

The pre-v5 suite was written before the four-tier model and `Infrastructure.Tests` existed, so its shape (often an inverted pyramid — logic stuck at the Integration tier) is **accepted debt that is NOT measured against the run.** What *is* measured is everything added **since** v5 adoption. To separate the two, capture an immutable snapshot the first time the orchestrator ever runs in a repo — **detected by the file being absent.**

**This step has exactly two outcomes — there is no path that rewrites an existing baseline:**

- **File present → STOP IMMEDIATELY. Do not run `count()`. Do not regenerate, edit, restamp, or `git add` the file for any reason.** A "refresh" of the frozen baseline is always a bug (it zeroes the since-v5 delta). If you believe the numbers are stale, that feeling is the design working — the *current* counts belong in the CLEANUP since-v5 report, never in this file.
- **File absent → do NOT silently auto-capture.** Capturing at an arbitrary later commit freezes the *wrong* numbers as the "v5 adoption" point. Treat a missing baseline as an anomaly: **halt and tell the operator**, and only write when they explicitly opt in to a first-time capture (the `BASELINE_FIRST_CAPTURE=1` gate below). A genuine first adoption sets that flag once; a missing file on any later run is a problem to surface, not to paper over.

```bash
BASELINE=docs/test-pyramid-baseline.md
if [ -f "$BASELINE" ]; then
  echo "Step 0.7: baseline present and FROZEN — no-op (never re-capture, never edit)."
elif [ "${BASELINE_FIRST_CAPTURE:-}" != "1" ]; then
  echo "Step 0.7: baseline MISSING at $BASELINE — refusing to auto-capture (would freeze the wrong v5 point)." >&2
  echo "  If this is a genuine first v5 adoption, re-run this step with BASELINE_FIRST_CAPTURE=1." >&2
  echo "  Otherwise the file was lost/moved — restore it from git, do not recreate it." >&2
  # Surface, do not proceed. This is an operator decision, not an auto-fix.
else
  SHA=$(git rev-parse HEAD)
  count() { grep -rlE '\[Fact|\[Theory' "$@" 2>/dev/null | xargs grep -cE '\[Fact|\[Theory' | awk -F: '{s+=$2} END{print s+0}'; }
  # Unit tier = Domain.Tests + Infrastructure.Tests (logic, wherever it lives)
  unit=$(count tests/*Domain.Tests/ tests/*Infrastructure.Tests/)
  contract=$(count tests/*Api.Tests/); integ=$(count tests/*Integration.Tests/); ui=$(count tests/*Playwright.Tests/)
  mkdir -p docs
  cat > "$BASELINE" <<EOF
# Test Pyramid Baseline — v5 adoption snapshot (FROZEN — do not edit)

Captured $(date -u +%Y-%m-%dT%H:%MZ) @ \`$SHA\`.
Pre-v5 tests are **accepted debt**. Pyramid health is judged on tests added **since** this
point, not the total — see standards/testing.md → Test-Pyramid Baseline.

| Tier | Count at v5 adoption |
|------|----------------------|
| Unit (Domain + Infrastructure) | $unit |
| Contract (Api.Tests) | $contract |
| Integration | $integ |
| UI | $ui |
EOF
  git add "$BASELINE" && git commit -m "chore: capture v5 test-pyramid baseline" && git push
fi
```

Write-once is the whole point: a **frozen** baseline means any later genuine re-tiering of an old test simply shows up as a *negative* since-v5 delta (progress) — there is nothing to ratchet and nothing to maintain. The file's **content must always equal its first-adoption capture**; CLEANUP audits this (C2 a.1) by diffing against the commit that added the file, and any divergence is treated as accidental drift to revert.

## Mode Selection

After Step 0 (context + board IDs), 0.5 (tracking issue + **run scope**), and 0.6 (crash recovery), **select the mode from durable state** — mode is computed, never passed in.

**Ready tickets = tickets that are in this run's SCOPE *and* currently Status "Up Next".** Read the scope from the tracking-issue body (Step 0.5), not from launch args — a relaunched process has no memory of the original arguments, so the scope must come from durable state.

```bash
# All Up Next board items (use the project + field IDs from 0c)
UPNEXT=$(gh project item-list {PROJECT_NUMBER} --owner {REPO_OWNER} --format json \
  --jq '[.items[] | select(.status == "Up Next") | .content.number]')
# READY = UPNEXT ∩ scope.  If scope is "full board", READY = UPNEXT.
```

- **Ready count > 0 → WORKING mode** (process up to N of the *scoped* Up Next tickets).
- **Ready count == 0 → CLEANUP mode** (end-of-run oversight).

That is the entire control flow: each launch picks **one** mode, does its chunk, and **exits**. The loop relaunches until CLEANUP reaches a fixpoint and emits `RUN_COMPLETE`.

**Scoping is durable, not per-process.** "Do these five even though ten are in Up Next" works *because* the five are written to the tracking issue at run start (Step 0.5) and every relaunch reads them back. The other five Up Next tickets are never touched by this run, and the run reaches its fixpoint when the **scoped** five are done — it does **not** wait for Up Next to empty.

---

## WORKING Mode — Per-Ticket Pipeline

WORKING mode processes **up to N** Ready tickets — those **in this run's scope and currently Status = Up Next** (see Mode Selection) — highest-priority first. A run scoped to `#7…#11` only ever pulls from those five; the rest of Up Next is invisible to it. For EACH ticket, execute the stages below, then **checkpoint** (Stage 8). After N tickets are done — or the scoped Ready queue empties mid-chunk — **exit** (do not roll into CLEANUP in the same session; the relaunch re-evaluates the mode). If `ORCHESTRATE_N` is unset, process all Ready tickets in this one session.

At the start of each ticket, append an event-log comment to the tracking issue (`▶ started {STORY_ID}`) and set the body's **Current ticket**.

**Keep the tracking issue live — the orchestrator maintains it, every stage.** Update the body's `Current ticket: {STORY_ID} @ Stage {n} ({name})` field **every time you enter a new stage** below (refine → implement → review → security → integration → review → ui → review → checkpoint) with a `gh issue edit {TRACKING_ISSUE} --body`, so the issue always reflects the true current stage — for anyone monitoring the run, and so a relaunched process recovers accurate state — never a stale "Stage 1." Also append a short tracking-issue event-log **comment** at the high-level milestones — PR opened, PR merged, review REQUEST_CHANGES, ticket done — so the comment thread is a skimmable timeline. (The *detailed* per-stage audit still lands on the work ticket as before; the tracking issue carries the run-level summary.)

For EACH ticket, execute these stages:

---

### Stage 1: REFINE STORY

#### 1a. Pre-flight
- `git checkout main && git pull origin main`
- Verify git hooks: If `.githooks/` exists, run `git config --local core.hooksPath .githooks`

#### 1a.1 Milestone Detection

Check if this ticket is a milestone marker:

```bash
gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json labels --jq '.labels[].name' | grep -q '^milestone$'
```

**If `milestone` label is found:** This is a milestone review gate. Do NOT run the pipeline. Instead:

1. Run the smoke test checklist from the milestone issue body
2. Report milestone results to the user
3. **STOP regardless of mode** (supervised or autonomous). Output:

```
## Milestone Reached: {MILESTONE_TITLE}

### Smoke Test Results
- [ ] Application starts: {pass/fail}
- [ ] Health endpoint: {pass/fail}
- [ ] {Other checks from issue body}

### Stories Completed in This Milestone
{list of stories completed since last milestone}

Waiting for approval. Review the application and say "proceed" to continue past this milestone.
```

Wait for user reply. This is a hard gate.

#### 1a.2 Ticket Readiness Check

For non-milestone tickets, verify the ticket is ready:

```bash
BODY=$(gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json body --jq .body)
```

If the body is empty or contains no `- [ ]` acceptance criteria checkboxes, **SKIP** this ticket. Add to Skipped table with reason "Ticket not ready — missing acceptance criteria."

#### 1a.3 Rollback Tag

Tag main before any work begins on this ticket:

```bash
git tag pre-{STORY_ID}
```

#### 1b. Spawn refine-story-v5

Read `.claude/skills/refine-story-v5/SKILL.md` and substitute:
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID (e.g., AZ-017)
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{ORCHESTRATOR_MODE}` → `true`

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 1c. Process result

- If `STATUS: AlreadyRefined` — continue to Stage 1d
- If `STATUS: Refined` — continue to Stage 1d
- If `STATUS: Blocked` (e.g., missing external API spec) — move issue to Waiting/Blocked, post comment with `REASON`, skip this ticket
- If `STATUS: NeedsManualReview` — move issue to Waiting/Blocked, post comment, skip this ticket

#### 1d. External API Spec Gate (HARD GATE — see `standards/api-integration.md`)

Before dispatching to implementation, check whether the refined ticket involves external API integration. Read the issue body and check for signs: provider names (e.g., Athena, PropertyLens, E2Value, FEMA), `HttpClient` references, endpoint URLs, or a `## Spec Reference` section.

**If the ticket involves an external API:**

1. Check for the spec on disk:
   ```bash
   ls docs/api-specs/{provider}* 2>/dev/null
   ```
2. **If no spec exists:** The orchestrator blocks this ticket immediately. Do NOT dispatch to implement-ticket-v5.
   - Move issue to Waiting/Blocked
   - Post issue comment:
     ```
     ## Blocked: External API Spec Missing

     This ticket requires integration with **{provider}** but no API spec was found at `docs/api-specs/`.

     **Required action:** Obtain the API spec (OpenAPI JSON, ArcGIS layer definition, or documented response schema) and commit it to `docs/api-specs/{provider}-openapi.json` before implementation can proceed.

     **Why this gate exists:** Provider C# models must be built from verified API contracts, not from PRD descriptions or assumptions. See `standards/api-integration.md`.
     ```
   - Skip this ticket and continue to the next one
3. **If the spec exists:** Continue to Stage 2

**If the ticket does NOT involve an external API:** Continue to Stage 2.

---

### Stage 2: IMPLEMENT

#### 2a. Pre-flight
- `git checkout main && git pull origin main`
- Create branch: `git checkout -b story/{STORY_ID}-short-name main` (use `fix/` for bugs, `task/` for tasks)
- Move issue to In Progress on the project board

#### 2b. Spawn implement-ticket-v5

Read `.claude/skills/implement-ticket-v5/SKILL.md` and substitute:
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

- If `STATUS: Complete` — extract `PR_NUMBER` from report, continue to **Stage 2d**
- If `STATUS: Partial` — post issue comment describing what's incomplete, move to Waiting/Blocked, skip this ticket
- If `STATUS: Blocked` — post issue comment with blocker, move to Waiting/Blocked, skip this ticket

#### 2d. Scope Completeness Check

After the implementer reports completion, verify the implementation actually covers the full scope of the ticket. Specifically:

1. **UI Deferral Detection:** If the ticket's acceptance criteria mention any of these: Blazor pages, screens, routes (e.g., `/forms`, `/data-dictionary`), UI components, or `.razor` files — check whether corresponding `.razor` files were created in the PR. If the criteria require UI but no `.razor` files were added:
   - Check the PR description and implementation notes for deferral language ("deferred", "follow-up", "NOT include UI", "API-only")
   - If deferral is detected, check whether a follow-up ticket was created
   - **If no follow-up ticket exists:** Create one automatically. Title: `{STORY_ID}b: {original title} — Blazor UI pages`. Label: `story`. Link as sub-issue of the current milestone. Post an issue comment: "Implementation deferred UI pages. Auto-created follow-up ticket #{NEW_ISSUE_NUMBER}."
   - **If a follow-up ticket exists:** Note it in the issue comment and continue

2. **Acceptance Criteria Spot-Check:** Compare the ticket's `- [ ]` acceptance criteria against what was implemented. If more than 30% of criteria appear unaddressed (no corresponding code, endpoints, or tests), treat as `STATUS: Partial` — post issue comment and move to Waiting/Blocked.

3. **Follow-Up Ticket Injection (Non-Negotiable):** If a follow-up ticket was created (either by the implementer or auto-created in step 1 above), it **must be appended to the current orchestrator run's ticket queue**. Follow-up tickets do not wait for a future session — they run in the current batch, after the parent ticket completes.

   **How to inject:**
   - Resolve the follow-up issue number
   - Verify it is on the project board with all fields set (Status, Type, Priority, Component, Story ID). If not, add it and set the fields.
   - Append the issue number to the ticket list so it will be picked up after the current ticket's pipeline (stages 3–8) completes
   - Log the injection: `"Follow-up ticket #{FOLLOW_UP_NUMBER} injected into current run after #{CURRENT_TICKET_NUMBER}"`

   **Rationale:** A follow-up ticket that isn't in the current run will be forgotten. The orchestrator is the only agent that manages sequencing — if it doesn't pick up the ticket, no one will until a human notices the gap. This is how II-210's deferred UI work (II-226) sat untouched for weeks.

After the completeness check passes, continue to Stage 3.

---

### Stage 3: REVIEW (Implementation)

Run a review loop: reviewer checks → if changes requested → implementer fixes → reviewer re-checks. Max 3 iterations.

#### 3a. Spawn engineering-review

Read `.claude/skills/engineering-review-v5/SKILL.md` and substitute:
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

**Post a dedicated issue comment for every review result** — this creates a real-time audit trail on the issue.

**If `STATUS: Approved`:**
- Post issue comment:
  ```
  ## Implementation Review — Approved

  **PR:** #{PR_NUMBER}
  **Iterations:** {N}
  **Violations:** 0
  **Suggestions:** {count}

  Review passed all standards checks. Proceeding to security review.
  ```
- Continue to Stage 3.5 (do NOT merge yet)

**If `STATUS: ChangesRequested` and iteration < 3:**
- Post issue comment:
  ```
  ## Implementation Review — Changes Requested

  **PR:** #{PR_NUMBER}
  **Iteration:** {N} of 3
  **Violations:** {count}
  **Suggestions:** {count}

  Issues found — sending back for fixes. See PR #{PR_NUMBER} for inline comments.
  ```
- Spawn implement-ticket-v5 in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the implementation PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 2
- After fix completes, loop back to 3a with incremented iteration

**If `STATUS: ChangesRequested` and iteration >= 3:**
- Post issue comment:
  ```
  ## Implementation Review — Exhausted

  **PR:** #{PR_NUMBER}
  **Iterations:** 3 (max reached)
  **Unresolved violations:** {count}

  Review loop exhausted. Moving to Waiting/Blocked for manual attention.
  ```
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 3.5: SECURITY REVIEW

Run an OWASP Top 10 security analysis on the approved implementation PR. If the PR contains infrastructure files (`.bicep`, `Dockerfile`, `.github/workflows/*.yml`), the infrastructure security checklist runs automatically. Max 2 iterations (security issues that persist after one fix likely need human judgment).

#### 3.5a. Spawn security-review-v4

Read `.claude/skills/security-review-v4/SKILL.md` and substitute:
- `{PR_NUMBER}` → the implementation PR number
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID
- `{BRANCH_NAME}` → the implementation branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{ITERATION}` → current iteration (starting at 1)

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 3.5b. Process security review result

**Post a dedicated issue comment for every security review result** — this creates a real-time audit trail on the issue. (The security-review-v4 skill posts its own audit comment; verify it was posted but do not duplicate it.)

**If `STATUS: Passed`:**
- Merge the PR:
  ```bash
  gh pr merge {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --merge --delete-branch
  ```
- Pull main: `git checkout main && git pull origin main`
- Capture the merge SHA: `MERGE_SHA=$(git rev-parse HEAD)`
- Delete local branch: `git branch -d {BRANCH_NAME} 2>/dev/null`
- **Spawn CI watcher (background)** — see [Background CI/CD Health Watching](#background-cicd-health-watching)
- Continue to Stage 4 immediately (do not wait for the watcher)

**If `STATUS: Blocked` and iteration < 2:**
- Spawn implement-ticket-v5 in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the implementation PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 2
- After fix completes, loop back to 3.5a with incremented iteration

**If `STATUS: Blocked` and iteration >= 2:**
- Post issue comment:
  ```
  ## Security Review — Exhausted

  **PR:** #{PR_NUMBER}
  **Iterations:** 2 (max reached)
  **Unresolved findings:** {count}

  Security review loop exhausted. Moving to Waiting/Blocked for manual attention.
  ```
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 4: INTEGRATION TESTS

#### 4a. Pre-flight
- Ensure on main with latest: `git checkout main && git pull origin main`
- Create integration test branch: `git checkout -b story/{STORY_ID}-integration-tests main`

#### 4b. Spawn integration-test

Read `.claude/skills/integration-test-v5/SKILL.md` and substitute:
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

Read `.claude/skills/engineering-review-v5/SKILL.md` and substitute:
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

**Post a dedicated issue comment for every review result** — this creates a real-time audit trail on the issue.

**If `STATUS: Approved`:**
- **Check off ALL acceptance criteria checkboxes** in the issue body BEFORE merging (prevents the `Closes #XX` auto-close from racing the checkbox update):
  ```bash
  # Fetch the current issue body
  BODY=$(gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json body --jq .body)
  # Replace all unchecked boxes with checked boxes
  UPDATED=$(echo "$BODY" | sed 's/- \[ \]/- [x]/g')
  # Update the issue
  gh issue edit {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$UPDATED"
  ```
- **Verify checkboxes were checked** — re-fetch the issue body and confirm no `- [ ]` remains:
  ```bash
  gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json body --jq '.body' | grep -c '\- \[ \]'
  ```
  If the count is > 0, retry the edit once. If it still fails, log a warning but continue.
- Post issue comment:
  ```
  ## Integration Test Review — Approved

  **PR:** #{PR_NUMBER}
  **Iterations:** {N}
  **Violations:** 0
  **Suggestions:** {count}

  Review passed all standards checks. Merging.
  ```
- Merge the PR:
  ```bash
  gh pr merge {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --merge --delete-branch
  ```
- Pull main: `git checkout main && git pull origin main`
- Capture the merge SHA: `MERGE_SHA=$(git rev-parse HEAD)`
- Delete local branch: `git branch -d {BRANCH_NAME} 2>/dev/null`
- **Spawn CI watcher (background)** — see [Background CI/CD Health Watching](#background-cicd-health-watching)
- Continue to Stage 6 immediately (do not wait for the watcher)

**If `STATUS: ChangesRequested` and iteration < 3:**
- Post issue comment:
  ```
  ## Integration Test Review — Changes Requested

  **PR:** #{PR_NUMBER}
  **Iteration:** {N} of 3
  **Violations:** {count}
  **Suggestions:** {count}

  Issues found — sending back for fixes. See PR #{PR_NUMBER} for inline comments.
  ```
- Spawn integration-test in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the integration test PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 4
- After fix completes, loop back to 5a with incremented iteration

**If `STATUS: ChangesRequested` and iteration >= 3:**
- Post issue comment:
  ```
  ## Integration Test Review — Exhausted

  **PR:** #{PR_NUMBER}
  **Iterations:** 3 (max reached)
  **Unresolved violations:** {count}

  Review loop exhausted. Moving to Waiting/Blocked for manual attention.
  ```
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 6: UI TESTS

#### 6a. Pre-flight
- Ensure on main with latest: `git checkout main && git pull origin main`
- Create UI test branch: `git checkout -b story/{STORY_ID}-ui-tests main`

#### 6b. Spawn ui-test

Read `.claude/skills/ui-test-v5/SKILL.md` and substitute:
- `{STORY_ID}` → the story ID
- `{TICKET_TITLE}` → the ticket title
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{BRANCH_NAME}` → the UI test branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{IMPLEMENTATION_PR}` → the merged implementation PR number
- `{FIX_MODE}` → `false`
- `{PR_NUMBER}` → (leave as literal — not in fix mode)
- `{ITERATION}` → `0`

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 6c. Process result

- If `STATUS: Skipped` — the ticket has **no in-scope UI surface** (TR-5). This is normal, not a failure. Post an issue comment noting the skip reason from the report, record `UI: skipped ({reason})` for the checkpoint, and **skip stages 6–7** — go straight to Stage 8.
- If `STATUS: Complete` — extract `PR_NUMBER` from report, continue to Stage 7
- If `STATUS: Partial` or `STATUS: Blocked` — post issue comment, move to Waiting/Blocked, skip remaining stages

Note: `ui-test-v5` runs the new tests via a **scoped `workflow_dispatch`** on the self-hosted runner and fix-loops there — the UI tier is not a per-PR gate. Stage 7's review confirms that runner run was green.

---

### Stage 7: REVIEW (Playwright Tests)

Same review loop structure as Stage 5, but reviewing UI test quality.

#### 7a. Spawn engineering-review

Read `.claude/skills/engineering-review-v5/SKILL.md` and substitute:
- `{PR_NUMBER}` → the UI test PR number
- `{ISSUE_NUMBER}` → the GitHub issue number
- `{STORY_ID}` → the story ID
- `{BRANCH_NAME}` → the UI test branch
- `{REPO_OWNER}` → resolved repo owner
- `{REPO_NAME}` → resolved repo name
- `{MODE}` → `ui-tests`
- `{ITERATION}` → current iteration (starting at 1)

Pass to Agent tool with `subagent_type: "general-purpose"`.

#### 7b. Process review result

**Post a dedicated issue comment for every review result.**

**If `STATUS: Approved`:**
- Post issue comment:
  ```
  ## UI Test Review — Approved

  **PR:** #{PR_NUMBER}
  **Iterations:** {N}
  **Violations:** 0
  **Suggestions:** {count}

  Review passed all standards checks. Merging.
  ```
- Merge the PR:
  ```bash
  gh pr merge {PR_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --merge --delete-branch
  ```
- Pull main: `git checkout main && git pull origin main`
- Capture the merge SHA: `MERGE_SHA=$(git rev-parse HEAD)`
- Delete local branch: `git branch -d {BRANCH_NAME} 2>/dev/null`
- **Spawn CI watcher (background)** — see [Background CI/CD Health Watching](#background-cicd-health-watching)
- Continue to Stage 8 immediately (do not wait for the watcher)

**If `STATUS: ChangesRequested` and iteration < 3:**
- Post issue comment:
  ```
  ## UI Test Review — Changes Requested

  **PR:** #{PR_NUMBER}
  **Iteration:** {N} of 3
  **Violations:** {count}
  **Suggestions:** {count}

  Issues found — sending back for fixes. See PR #{PR_NUMBER} for inline comments.
  ```
- Spawn ui-test in FIX mode:
  - `{FIX_MODE}` → `true`
  - `{PR_NUMBER}` → the UI test PR number
  - `{ITERATION}` → current iteration number
  - All other placeholders same as Stage 6
- After fix completes, loop back to 7a with incremented iteration

**If `STATUS: ChangesRequested` and iteration >= 3:**
- Post issue comment:
  ```
  ## UI Test Review — Exhausted

  **PR:** #{PR_NUMBER}
  **Iterations:** 3 (max reached)
  **Unresolved violations:** {count}

  Review loop exhausted. Moving to Waiting/Blocked for manual attention.
  ```
- Move issue to Waiting/Blocked on the project board
- Skip this ticket

---

### Stage 8: CHECKPOINT & CLOSE

- **Checkpoint to the tracking issue (do this first — it is the relaunch-safety record).** Update the tracking-issue **body** (move this ticket from "current" to "completed this run", bump the N-chunk progress counter) and append an **event-log comment**: `✓ completed {STORY_ID} — impl #PR, integ #PR, ui #PR|skipped`. If a relaunch happens after this point, the new session reads this and does not re-process the ticket.
- **Safety-net checkbox verification** — if the issue is still open (not auto-closed by `Closes #XX`), check off any remaining unchecked acceptance criteria:
  ```bash
  REMAINING=$(gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json body --jq '.body' | grep -c '\- \[ \]')
  if [ "$REMAINING" -gt 0 ]; then
    BODY=$(gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --json body --jq .body)
    UPDATED=$(echo "$BODY" | sed 's/- \[ \]/- [x]/g')
    gh issue edit {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$UPDATED"
  fi
  ```
- **Post observability metrics** as an issue comment before closing:
  ```bash
  gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
  ## Observability Metrics

  **Orchestrator model:** {ORCHESTRATOR_MODEL}

  | Phase | Model | Tokens | Duration |
  |-------|-------|--------|----------|
  | Refine | {REFINE_MODEL} | {REFINE_TOKENS} | {REFINE_DURATION} |
  | Implement | {IMPL_MODEL} | {IMPL_TOKENS} | {IMPL_DURATION} |
  | Review (Impl) | {REVIEW_MODEL} | {REVIEW_TOKENS} | {REVIEW_DURATION} |
  | Security Review | {SECURITY_MODEL} | {SECURITY_TOKENS} | {SECURITY_DURATION} |
  | Integration Tests | {TEST_MODEL} | {TEST_TOKENS} | {TEST_DURATION} |
  | Review (Tests) | {TEST_REVIEW_MODEL} | {TEST_REVIEW_TOKENS} | {TEST_REVIEW_DURATION} |
  | Playwright Tests | {PLAYWRIGHT_MODEL} | {PLAYWRIGHT_TOKENS} | {PLAYWRIGHT_DURATION} |
  | Review (Playwright) | {PLAYWRIGHT_REVIEW_MODEL} | {PLAYWRIGHT_REVIEW_TOKENS} | {PLAYWRIGHT_REVIEW_DURATION} |
  | **Total** | — | **{TOTAL_TOKENS}** | **{TOTAL_DURATION}** |

  Review iterations (impl): {IMPL_REVIEW_ITERS} | Security iterations: {SECURITY_ITERS} | Review iterations (tests): {TEST_REVIEW_ITERS} | Review iterations (playwright): {PLAYWRIGHT_REVIEW_ITERS}

  ### CI/CD Health
  | Merge | PR | Status | Fix PR |
  |-------|----|--------|--------|
  | {SHA} | #{PR} | {passed/fixed/blocked} | #{FIX_PR or n/a} |
  EOF
  )"
  ```
  Omit the CI/CD Health table if all watchers reported `Passed` (i.e., nothing interesting happened).
  Use the per-ticket metrics tracked in `session_metrics.tickets[]` for this ticket. Tokens should be formatted with comma separators (e.g., `45,230`). Duration should be in human-readable format (e.g., `1m 35s`). Omit rows for phases that were skipped (e.g., if no integration tests were run, omit that row).

  **Capturing the model per phase.** Every per-stage subagent skill (`refine-story-v5`, `implement-ticket-v5`, `engineering-review-v5`, `security-review-v4`, `integration-test-v5`, `ui-test-v5`) reports its model in the `MODEL:` line of its STATUS block. Extract that value verbatim and use it in the table above. Use the friendly name (e.g., `Opus 4.7`, `Sonnet 4.6`, `Haiku 4.5`) rather than the model ID. When a phase runs multiple iterations on different models (rare, but possible if you override per iteration), list them comma-separated (e.g., `Opus 4.7, Sonnet 4.6`).

  **Capturing the orchestrator's own model.** Report the model the orchestrator (this session) is running on — read it from the system prompt's "You are powered by the model named …" line. Use the same friendly-name format.

- Close the issue (if not already auto-closed):
  ```bash
  gh issue close {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME}
  ```
  (Board automation moves it to Done)

Note: Acceptance criteria are primarily checked off in Stage 5b before merging, so this step is a safety net. The individual stage comments (Refinement, Implementation, Review results, Integration Tests) provide the audit trail, and the observability metrics comment provides the cost/performance record.

---

## WORKING Mode — chunk completion

After processing N tickets (or when the scoped Ready queue empties mid-chunk):

- Ensure every completed ticket is checkpointed (Stage 8) and the tracking-issue body reflects current state.

**What happens next depends on whether a relaunch loop is driving you — detected by whether `ORCHESTRATE_N` is set (the dumb loop exports it; a direct session does not):**

- **Looped run (`ORCHESTRATE_N` is set):** append `⟳ chunk done — exiting for relaunch` to the event log and **exit the session.** Do NOT roll into CLEANUP in this process — exiting and letting the loop relaunch is what gives the next chunk fresh context (#6). The relaunch re-runs Mode Selection: more scoped Ready → another WORKING chunk; none → CLEANUP.
- **Single-session run (`ORCHESTRATE_N` unset — you were launched directly, not by the loop):** there is **no relaunch** to run the wrap-up, so **continue in this same session.** When the scoped Ready queue is empty, fall through to **CLEANUP** (below); let it reach the fixpoint and **close the tracking issue**. This is what makes a direct run self-complete and leave no dangling open `orchestration-run` issue. (You may still emit `RUN_COMPLETE` — harmless with no loop listening.)
- In **supervised** mode, honor the Supervised Mode Gate (stop between tickets) regardless of the above. After the *last* scoped ticket and a final "proceed", a single-session run still falls through to CLEANUP and closes out; a looped run exits and the loop's next relaunch handles CLEANUP.

---

## CLEANUP Mode (end-of-run oversight)

CLEANUP runs when **no scoped Ready tickets remain** (scope ∩ Up Next == 0) — reached either by a **relaunch** picking this mode in Mode Selection (looped run), or by a **single-session** run falling through here after WORKING (direct run, `ORCHESTRATE_N` unset). It is the run's periodic detector — run-completion-triggered, not clock-triggered. Execute in order:

> **"If you see it, you own it" — a known-failing test is a HARD BAR on fixpoint, no matter who caused it.** The instant CLEANUP (or any stage) observes a test failing/flaking/timing-out, **driving it to green becomes this run's obligation** — regardless of provenance. "Pre-existing" / "not my story" explains *where the red came from*; it is **not** permission to close around it. **A filed ticket is bookkeeping, not discharge:** the ticket tracks the work; only a green test completes it. A run that *saw* red and closed is worse than one that never looked — the failure is now documented-and-abandoned. The only exits from an observed red are **green** (fix it in-run: inject → work → re-run → confirm green → close) or a **circuit-breaker halt** (leave the issue OPEN, flag a human) — never a close with the bug parked in a ticket. *(Pilot gap, HC-21 #377: CLEANUP's C1 sweep returned 11/12 — the 12th was the pre-existing AuthGuard redirect-timeout, unchanged since HC-14. The orchestrator correctly diagnosed it, ruled out the current story, filed #389, and reported "not at fixpoint, leaving OPEN" — then the run **stopped anyway** with a known-red test still in the suite, discharged by nothing but a queued ticket. Green or halt — those are the only two outs.)*

> **Closing the run is gated on CLEANUP — never close the tracking issue by hand to "wrap up."** A hand-written "run complete" summary comment is **not** CLEANUP. The since-v5 re-tier audit (C2) and the gate audit (C3) are the entire reason this mode exists — the gate audit is the only check that catches a PR which merged without a filled TR grid, and the re-tier audit is the only check that catches new logic-only tests that slipped into the Integration tier; so the run is **not** complete until they have actually run and C5's fixpoint condition is met. **This holds even when you resumed by hand-driving the stage skills outside the orchestrator** — e.g. because the work ticket was prematurely closed/Done (the `Closes #N`-on-a-stage-PR bug) so `orchestrate-v5` wouldn't auto-pick it. If you ever finish a run that way, you still owe it C1–C3: **re-enter `orchestrate-v5` to run CLEANUP, or run C1–C3 manually, then close via C5** — and keep the body live the whole time (a frozen body that still says "Stage 1 (refine) / Pyramid ratio: not yet run" means CLEANUP never happened). *(Pilot gap, HC-14 #359: the run was hand-driven through Stages 6→8 and the tracking issue closed with a summary comment while its body still read `Pyramid ratio: not yet run` / `Gate audit: not yet run` — CLEANUP was skipped entirely, and the integration-tier flake it would have flagged went un-ticketed.)*

### C1. Full UI regression suite (unfiltered runner dispatch)

Dispatch `ui-tests.yml` **unfiltered** (full suite) on the self-hosted runner and poll to completion:

```bash
gh workflow run ui-tests.yml --ref main -f ref=main -f filter=""
run_id=$(gh run list --workflow=ui-tests.yml --branch main --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --exit-status || true
```

This catches regressions a *later* story introduced into an *earlier* story's UI (the job blame isn't the point — the fix is). For each genuine failure — **including any diagnosed as pre-existing** — inject a fix ticket (C4) **and own it through to green**. "Pre-existing" is a reason to fix it *calmly*, not a reason to defer it; the only exits from a red C1 are a **green re-run** or a **circuit-breaker halt** (per *"If you see it, you own it"* above). A red C1 is itself a hard bar on fixpoint (C5) — a queued ticket does not discharge it.

### C2. Test-pyramid: since-v5 delta (report) + re-tier audit (the gate) (#5a)

The pre-v5 suite is frozen as accepted debt in `docs/test-pyramid-baseline.md` (Step 0.7). CLEANUP does **two** things here — one informational, one enforcing. Do **not** revert to the old "is the absolute ratio bad?" check: it measures the polluted total (the frozen debt talking), nags every run with no actuator, *misses* drift that hides under the aggregate, and would deadlock a legitimately infra-heavy run.

**(a) Report the since-v5 delta — visibility, never a blocker.** Recompute current per-tier counts (same `count()` as Step 0.7), read the frozen baseline, and write `total now / baseline / since-v5` per tier into the run summary and the tracking-issue body. This is the honest scoreboard — the part the team actually controls. No ticket comes off these numbers.

**(a.1) Frozen-baseline integrity check — content must equal the first capture.** The since-v5 delta is only meaningful if the frozen numbers were never re-stamped (Step 0.7). Audit by comparing current content to the file's *first* commit — not by counting commits, because a legitimate revert leaves a permanent 3-commit history (capture → bad edit → restore) that a count check would nag on forever:

```bash
B=docs/test-pyramid-baseline.md
first=$(git log --diff-filter=A --format=%H -- "$B" | tail -1)   # commit that ADDED the file
if [ -n "$first" ] && ! git diff --quiet "$first" -- "$B"; then
  echo "DRIFT: $B differs from its first capture ($first) — frozen baseline was edited." >&2
  echo "  Restore: git checkout $first -- $B  (commit as a revert), then flag in run summary." >&2
fi
```

Content differing from the first capture means the frozen file was overwritten despite Step 0.7's guard (an LLM-paraphrase slip is the usual cause). **Restore it from that first commit and flag it in the run summary** so the regression is visible. This is the backstop for when the Step 0.7 instruction is not honored literally.

**(b) Audit THIS run's new Integration tests — the gate, per-test not per-count.** Scope: the Integration tests **this run added or changed** — from the completed tickets in the tracking-issue body → the `*Integration.Tests/` files in their diffs (bounded to one run's work; no SHA bookkeeping, no re-auditing the frozen debt). For each, ask the single TR-3 question: *would this pass against the fakes host, with no real infrastructure?* If **yes**, it is **mis-tiered** — its subject is logic that belongs in `Infrastructure.Tests`, not the Docker-bound tier. For each such test, **inject a re-tier fix ticket** (C4): move the scenario to `Infrastructure.Tests`, delete the slow copy (TR-10). Tests that genuinely need infra (SQL, constraints, transactions) are never flagged, so a real infra-heavy run audits clean and closes — **no deadlock, no threshold to tune.** Layer 1 (the `engineering-review-v5` faucet-stop at the PR diff) should make this backstop usually find nothing; it exists for what review missed. A run that completed zero tickets has nothing to audit.

### C3. Gate audit (#10 — concrete artifact, not vibes)

For every ticket completed in this run (from the tracking-issue body), confirm each stage's PR review actually **posted a filled-in TR reviewer grid** (the `### TR checklist — {mode} (reviewer)` block) and that the required gates passed. A ticket missing its grid, or with an unaddressed `[JUDGMENT]` FAIL, gets a **fix ticket** injected.

### C4. Inject fix tickets

Any fix/drift tickets from C1–C3 are created on the board (Up Next), with all fields set (Status, Type, Priority, Component, Story ID) — a ticket not on the board doesn't exist. Record each in the tracking-issue body's "Injected this run", **and append its number to the `Scope:` field** so the next WORKING chunk actually picks it up (otherwise a scoped run would inject a fix and never work it). For a `full board` run this is automatic — it's already Up Next.

### C5. Fixpoint check

> **HARD BAR — evaluated first, overrides every condition below: no known-failing test may exist at fixpoint.** If the C1 regression suite — or *any* test this run observed red/flaking/timing-out — is not green, **closing or `RUN_COMPLETE` is FORBIDDEN**, even if every injected ticket reads "done." A ticket marked done with a still-red test does **not** clear the bar; only a clean re-run of the regression does. If the failure genuinely cannot be driven green in-run, **circuit-breaker halt** — leave the issue OPEN and emit `⚠ halted — needs human ({reason})` — never a close. (This is the C5 teeth behind *"If you see it, you own it."*)

- **CLEANUP injected nothing** (no re-tier ticket from the C2 audit, no C1/C3 fix tickets), **the C1 regression suite is green** (hard bar above clear), AND **no scoped Ready tickets remain** (scope ∩ Up Next == 0) → **fixpoint reached.** Close the tracking issue and emit the sentinel:
  ```bash
  gh issue close {TRACKING_ISSUE} --repo {REPO_OWNER}/{REPO_NAME} \
    --comment "⬛ Run complete — fixpoint reached (no scoped Ready tickets, C1 regression green, CLEANUP injected nothing)."
  echo "RUN_COMPLETE"
  ```
  The next relaunch's startup query finds no open `orchestration-run` issue → the loop breaks. **Done.** (Up Next may still hold *out-of-scope* tickets — that's fine; this run only ever owned its scope.)
- **CLEANUP injected something** (a re-tier ticket, a C1/C3 fix ticket, or a still-red regression to own) → exit **without** closing/`RUN_COMPLETE`. Because the injected tickets were appended to scope (C4), the next relaunch finds scoped Ready > 0 → WORKING → works then re-verifies the injected work. **For a C1-regression fix specifically, the next CLEANUP must re-dispatch the full UI suite and confirm the once-red test is now green before the hard bar clears** — a ticket marked done is not enough; the green re-run is what discharges it. This is **"fix the drift before the run closes" — and the orchestrator directs it**: a re-tier ticket from the C2 audit is processed like any other ticket (it moves the logic-only tests to `Infrastructure.Tests` and deletes the slow copies), and the *next* CLEANUP re-audits — those tests are now gone from Integration, so it finds nothing and closes. This is correct and non-infinite: injected tickets are real, bounded work that, once clean, leave CLEANUP with nothing to inject. (A genuinely infra-heavy run never injects in the first place — the audit flags no test — so it closes on the first pass.)

---

## Tracking-Issue Body Schema

Template the body — don't leave it freeform. **Overwrite** it as live state each session (the comments are the append-only log):

```markdown
## Orchestration Run

### 📨 Operator message (read FIRST each session — Step 0.55)
<!-- Operator: drop a course-correction here between loops. The orchestrator reads this
     before any decision, acts on it, logs the result to a comment, and clears it to `none`.
     Default value is `none`. -->
none

**Mode (last session):** WORKING | CLEANUP
**Started:** <UTC>   **Last session:** <UTC>
**Chunk size N:** 3   **Scope:** <ticket list | full board>

### Progress
- **Current ticket:** {STORY_ID} @ Stage {n} | none
- **Completed this run:** {STORY_ID} (impl #/integ #/ui #|skipped), …
- **Injected this run:** {fix/drift ticket #s} | none

### Test pyramid (last CLEANUP) — total / baseline / since-v5
- Unit Tu/Tb/+Td · Contract Cu/Cb/+Cd · Integration Iu/Ib/+Id · UI Uu/Ub/+Ud
- Since-v5 audit: {clean | re-tier ticket #s for N mis-tiered Integration tests}

### Gate audit (last CLEANUP)
- Tickets verified: N | missing TR grid / failed gate: {none | #s}

### Fixpoint
- Ready (Up Next): N | CLEANUP injected this pass: {yes | no}
```

Event-log comments use stable markers: `▶ started {id}`, `✓ completed {id}`, `⚠ blocked {id}`, `✉ operator message handled`, `⟳ chunk done / relaunch`, `⬛ RUN_COMPLETE`.

---

## Supervised Mode Gate

**If MODE is `supervised`, you MUST stop between tickets (not between stages).** After completing all 6 stages for a ticket (or after a ticket is skipped/blocked), output your check-in report and end with exactly:

**Waiting for approval. Say "proceed" to continue to the next ticket.**

The next ticket DOES NOT START until the user replies. This is a hard gate. If you find yourself typing "Now starting the next ticket" in supervised mode, STOP.

In `autonomous` mode, skip this gate and continue to the next ticket.

---

## Background CI/CD Health Watching

After every PR merge (implementation, integration tests, or UI tests), spawn a **ci-fix-v5** agent in WATCH mode as a **background agent**. This runs in parallel with the next stage — the orchestrator does not block on it.

### Spawning the Watcher

Read `.claude/skills/ci-fix-v5/SKILL.md` and substitute:
- `{MODE}` → `WATCH`
- `{MERGE_SHA}` → the merge commit SHA (captured after `git pull`)
- `{PR_NUMBER}` → the PR that was just merged
- `{STORY_ID}` → the current story ID
- `{REPO_OWNER}` / `{REPO_NAME}` → resolved repo identity

Pass to Agent tool with `subagent_type: "general-purpose"` and **`run_in_background: true`**.

Track each watcher in `session_metrics.ci_watches[]`:
```
{ merge_sha, pr_number, story_id, stage, status: "pending" }
```

### Processing Watcher Results

When a background watcher completes, check its status:

**If `STATUS: Passed`:**
- Update the watcher entry: `status: "passed"`
- No further action — continue current work

**If `STATUS: Failed`:**
- Update the watcher entry: `status: "failed"`
- **Spawn ci-fix-v5 in FIX mode** as a background agent:
  - Read `.claude/skills/ci-fix-v5/SKILL.md` and substitute:
    - `{MODE}` → `FIX`
    - `{FAILED_RUN_IDS}` → from the watcher's report
    - `{MERGE_SHA}` → from the watcher's report
    - `{STORY_ID}` → from the watcher's report
    - `{REPO_OWNER}` / `{REPO_NAME}` → resolved repo identity
  - Pass to Agent tool with `subagent_type: "general-purpose"` and **`run_in_background: true`**
  - Track in `session_metrics.ci_fixes[]`:
    ```
    { merge_sha, story_id, failed_run_ids, status: "pending" }
    ```
- Continue current work — do not block

**If `STATUS: Timeout` or `STATUS: NoRuns`:**
- Update the watcher entry with the reported status
- Log a warning but do not halt — these are informational. They may indicate a workflow configuration issue but are not blocking.

### Processing Fix Agent Results

When a background fix agent completes, check its status:

**If `STATUS: Fixed`:**
- Update the fix entry: `status: "fixed"`, `fix_pr: {FIX_PR_NUMBER}`
- No further action — the fix has already been merged

**If `STATUS: Blocked`:**
- Update the fix entry: `status: "blocked"`, `reason: {REASON}`
- **This is a circuit breaker** — a CI/CD failure that cannot be auto-fixed means main is broken and deployments are stuck. Halt the orchestrator after the current stage completes.

### Drain Before Close (Stage 8)

Before posting the final observability metrics for a ticket, **drain all pending CI watchers and fix agents** for that ticket. If any are still running, wait for them to complete before closing the ticket. This ensures the ticket's issue comment reflects the full CI/CD outcome.

---

## Circuit Breakers (Orchestrator Halts Entirely)

Even in autonomous mode, **STOP the entire loop** if:
- **3 consecutive tickets are Blocked or Partial** — something systemic is wrong
- **A PR merge conflict occurs** — needs human judgment
- **Build fails on main after a merge** — main is corrupted
- **3 review iterations exhausted** on a single ticket — already handled per-ticket, but if this happens on 2 consecutive tickets, halt
- **A CI/CD fix agent reports Blocked** — a pipeline failure that cannot be auto-fixed means main is broken and deployments are stuck

When halted, report the full session summary and explain why you stopped. **On a circuit-breaker halt, do NOT close the tracking issue and do NOT emit `RUN_COMPLETE`** — leave the run "active" with a `⚠ halted — needs human` event-log comment. The dumb loop will relaunch, hit the same wall, and its own **max-iterations circuit breaker** will stop the loop and flag a human (that backstop, not a fake completion, is the correct terminal state for an unrecoverable run).

---

## Session Summary (Final Report)

After all tickets are processed (or the loop is halted), produce this summary:

```
## Session Summary

### Completed
| Ticket | Title | Impl PR | Test PR | Playwright PR | Review Iters (Impl) | Security Iters | Review Iters (Test) | Review Iters (Playwright) | Tests Added | Playwright Tests Added |
|--------|-------|---------|---------|---------------|---------------------|----------------|---------------------|---------------------------|-------------|----------------------|
| {PREFIX}-{N} | ... | #N | #N | #N | N | N | N | N | N | N |

### Partial
| Ticket | Title | What Remains |
|--------|-------|-------------|
| {PREFIX}-{N} | ... | [description] |

### Blocked
| Ticket | Title | Blocker |
|--------|-------|---------|
| {PREFIX}-{N} | ... | [what's needed] |

### Skipped
| Ticket | Title | Reason |
|--------|-------|--------|
| {PREFIX}-{N} | ... | [why skipped] |

### Milestones Reached
| Milestone | Smoke Test | Stories Included |
|-----------|-----------|-----------------|
| M1: Auth + Dashboard | Pass/Fail | #1, #2, #3 |

### Observability

**Orchestrator model:** [friendly name, e.g., `Opus 4.7`]

| Ticket | Refine | Impl | Review | Security | Test | Playwright | Total Tokens | Duration |
|--------|--------|------|--------|----------|------|------------|-------------|----------|
| AZ-XXX | Sonnet 4.6 / 12,400 | Opus 4.7 / 45,230 | Sonnet 4.6 / 18,100 | Opus 4.7 / 9,800 | Sonnet 4.6 / 22,400 | Sonnet 4.6 / 18,600 | 126,530 | 115s |

_(Per-stage cells use `{model} / {tokens}` format so cost variance by model is visible at a glance. Models are reported by each subagent in its STATUS block.)_

**Session Totals:**
- Total tokens (all agents): X
- Total duration: Xm Xs
- Tickets completed: X / Y
- Tickets partial: X
- Tickets blocked: X
- Tickets skipped: X
- Milestones reached: X
- Total implementation PRs merged: X
- Total integration test PRs merged: X
- Total UI test PRs merged: X
- Total review iterations (implementation): X
- Total security review iterations: X
- Total security findings (blocking/advisory): X/X
- Total review iterations (integration): X
- Total review iterations (Playwright): X
- Total integration tests added: X
- Total UI tests added: X
- Total files changed: X
- CI/CD watches: X passed, X failed, X fixed, X blocked

### PRD Amendments
| Ticket | Finding | Suggested PRD Update |
|--------|---------|---------------------|
| AZ-XXX | [what was discovered during development] | [what should change in the PRD] |

_(If no PRD amendments, omit this section)_
```

---
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-24 -->
<!-- pipeline: v5 -->
