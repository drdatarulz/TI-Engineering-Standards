---
name: implement-ticket-v5
description: "Implement a single ticket following TI Engineering Standards — writes Unit + Contract tests per the issue's behavior-first tier table (no business logic in Contract). Pushes branch, creates PR, posts issue comment. Supports FIX mode (fix the code, not the test) to address review feedback on an existing PR."
argument-hint: "[issue-number or full ticket details]"
---

You are implementing a single ticket. Your working directory is the project root (the directory containing `CLAUDE.md`).

**Mode Detection:** When `{FIX_MODE}` is `true`, you are in FIX mode — skip to the Fix Mode section below. Otherwise, proceed with the full implementation workflow.

## Test tiers this skill owns (Unit + Contract)

This skill writes the **fast tier** — Unit and Contract tests — and **only** those. Integration tests (`integration-test-v5`) and UI tests (`ui-test-v5`) are separate stages and PRs. **Consume the issue's behavior-first Test Coverage table** (seeded by `refine-story-v5`) rather than re-deriving coverage: write the test for each behavior whose assigned Tier is **Unit** or **Contract**, at that tier, once. Per `standards/testing.md` → Test Tiers and Test Rules:

- **Unit** (`{Project}.Domain.Tests`) — business logic, branches, edge cases, validation rules, over fakes, no host.
- **Contract** (`{Project}.Api.Tests`) — endpoint wiring through `WebApplicationFactory` over fakes: routing, model binding, validation shape, status/error mapping, serialization, auth. **No business logic here (TR-2)** — a happy/edge/error walk of a domain rule belongs in Unit.
- **No Testcontainers/Docker in either fast-tier project (TR-11)** — they must run with no Docker daemon.
- These are the producer rows you sign off at the end: **TR-2, TR-7, TR-8, TR-11**. Cite the rules by ID; don't restate them.

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
- Extract the Story ID (`{PREFIX}-{issue#}`) from the issue title or Story ID custom field

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

## Scope Deferral Rules (Non-Negotiable)

- **NEVER check off an acceptance criterion that you did not implement.** A checked checkbox means the code exists in this PR. If you cannot implement a criterion, leave it unchecked.
- **If you must defer scope**, create a follow-up ticket AND:
  1. Leave the deferred criteria **unchecked** on the original issue
  2. Create the follow-up issue with `gh issue create`
  3. **Add the follow-up to the project board immediately** — use `gh project item-add` with the project number from `CLAUDE.md`. Set Status, Type, Priority, Component, and Story ID fields. A ticket that isn't on the board doesn't exist.
  4. Link the follow-up as a sub-issue of the relevant milestone (if one exists)
  5. Note the deferral and follow-up ticket number in your PR description and issue comment
- **Prefer reporting STATUS: Partial** over silently deferring scope. If a significant portion of the acceptance criteria cannot be completed, report it — don't create follow-up tickets to mask incomplete work.

## Implementation Workflow (Initial Mode)

### 1. EXPLORE (before writing code)
- Read all existing code in the affected area
- Understand the patterns already established for this component
- Check the Fakes project for existing fakes you'll need or need to extend
- Identify which files need to change and what new files are needed

### 1.5. EXTERNAL API SPEC VALIDATION (HARD GATE — see `standards/api-integration.md`)

**Check:** Does this ticket involve writing or modifying C# models for an external third-party API? Signs: files under `Providers/*/`, `[JsonPropertyName]` attributes for external responses, `HttpClient` calls to third-party endpoints, or the ticket references a third-party provider by name.

**If YES:**

1. Identify the provider name(s) from the code path (e.g., `Providers/Athena/`, `Providers/PropertyLens/`)
2. Check for the spec on disk:
   ```bash
   ls docs/api-specs/{provider}* 2>/dev/null
   ```
3. **If NO spec exists:** STOP. Do not write any provider models. Report:
   ```
   STATUS: Blocked
   MODE: initial
   TICKET: {STORY_ID}
   BLOCKED_REASON: External API integration requires a spec file at docs/api-specs/{provider}-*.json but none was found. Cannot write provider models without a verified API contract. Obtain the spec (OpenAPI, ArcGIS layer definition, or documented response schema) before implementation can proceed.
   CHECKLIST_ITEM: "External API spec on disk" — FAILED
   ```

4. **If the spec EXISTS:** Read it and validate the ticket's Technical Approach against it:
   - Do the field names in the TA match the spec? (e.g., spec says `Pixel_Risk_Score`, TA says `pixel_risk_score` → mismatch)
   - Do the types in the TA match the spec? (e.g., spec shows an object, TA says `decimal?` → mismatch)
   - If mismatches are found, use the **spec** as the source of truth, not the TA. Log each deviation.

5. **When writing provider models**, enforce these rules:
   - Every `[JsonPropertyName("...")]` value MUST match the exact field name from the spec or example response
   - Every C# property type MUST be compatible with the spec-defined type (object → class/dictionary, number → decimal/int, string → string)
   - Do not invent fields that are not in the spec
   - If intentionally skipping spec fields, add a one-line comment listing what was skipped

6. **After writing models**, run a self-check:
   - List every `[JsonPropertyName]` in the new/modified model files
   - Verify each one appears in the spec
   - Verify type compatibility
   - Include the validation result in the REPORT under a `SPEC_VALIDATION:` section

**If NO** (internal API or no provider models involved): skip this step.

### 2. PLAN (before writing code)
- Determine implementation approach based on existing patterns in the codebase
- Verify the approach respects the build order: Domain -> Fakes -> Infrastructure -> Api
- If anything is architecturally ambiguous, note it in your report — do your best interpretation but flag it

### 3. IMPLEMENT
- Follow the build order — don't jump ahead
- Write fakes for any new interfaces immediately
- Write tests alongside each piece of implementation, not after
- **Infrastructure drift check:** If you changed any provider section in `appsettings.json` (e.g., `UseStub`, `BaseUrl`, `TimeoutSeconds`, new provider sections), check `infra/modules/container-app.bicep` for the corresponding environment variable. If the bicep env var exists, update it to match. If a new setting has no bicep env var and the deployed default would be wrong (e.g., `UseStub` flipped from `true` to `false`), add the env var — and if it's a secret, add it to `infra/modules/keyvault.bicep` and `infra/main.bicep` as well. Non-secret config that matches the baked-in `appsettings.json` default does not need a bicep entry.

### 4. TEST

Use the build and test commands from the project's `CLAUDE.md`:
- Build the full solution
- Run the **fast tier** — the Unit (`Domain.Tests`) and Contract (`Api.Tests`) projects. These run with **no Docker daemon** (TR-11); if a test needs Testcontainers it is mis-tiered — move that behavior to the Integration stage, don't add Docker to the fast tier.
- All tests must pass — both new and existing
- If a test fails, **fix the code, not the test (TR-7).** A failing test is a signal the code is wrong; the default response is a code change. Only edit a test if it was genuinely written wrong (e.g. asserts the bug instead of the correct behavior) — never weaken or delete a test to make it pass. You have 3 attempts to fix failing tests before reporting as partial.
- Every test must reach a real assertion — no silent passes, no `Skip`, no asserting buggy behavior (TR-8).
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

- New Unit tests: [count]
- New Contract tests: [count]
- All fast-tier tests pass: yes/no
- Full solution builds: yes/no

## TR checklist — implementation (producer)

Fill PASS/FAIL **with evidence** (line reference or pasted command output — never a bare check). `engineering-review-v5` re-checks these adversarially in `implementation` mode.

| TR | Rule | Producer | Evidence |
|----|------|----------|----------|
| TR-2 | No business logic in the Contract tier | PASS/FAIL | [Contract tests assert wiring/status/shape only; logic scenarios live in Domain.Tests at lines …] |
| TR-7 | Fix the code, not the test | PASS/FAIL | [no test weakened/deleted to pass; failures fixed in src at …] |
| TR-8 | No silent failures / no asserting buggy behavior / no `Skip` | PASS/FAIL | [every new test reaches an assertion; grep shows no `Skip`] |
| TR-11 | No Testcontainers/Docker in the fast tier | PASS/FAIL | [no Testcontainers reference in Domain.Tests/Api.Tests; fast job ran with no daemon] |

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

SPEC_VALIDATION: (only if external API models were written)
- Spec file: docs/api-specs/{provider}-openapi.json
- Fields validated: [count] of [count] JsonPropertyName attributes match spec
- Type mismatches: [none | list]
- Skipped spec fields: [none | list]

CONCERNS:
- Anything that felt wrong, might need revisiting, or affects future tickets

BLOCKED_REASON: (only if STATUS is Blocked)
- What's blocking and what decision is needed
```

If STATUS is Blocked, explain clearly what decision or dependency you need. Do NOT guess or improvise around blockers.

---

## Fix Mode (When `{FIX_MODE}` is `true`)

When invoked with `{FIX_MODE}=true`, you are addressing review feedback on an existing PR. Do NOT re-explore or re-plan from scratch.

> **Fix the code, not the test (TR-7).** A failing or flagged test is a signal the *code* is wrong — the default fix is a code change. Do **not** weaken, delete, or rewrite a test to make it pass or to silence the reviewer. The only time a test changes is when it was genuinely written wrong (asserts buggy behavior, has a silent path, uses a hardcoded wait); fixing *that* is correcting the test, not gaming it. If a review comment seems to ask you to assert broken behavior, push back in your report rather than comply.

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
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-21 -->
<!-- pipeline: v5 -->
