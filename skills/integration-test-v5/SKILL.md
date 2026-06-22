---
name: integration-test-v5
description: "Write integration tests for a merged implementation — real-infrastructure behavior ONLY (no contract re-assertion, TR-3). Branches from main, follows existing Testcontainers patterns, creates PR. Supports FIX mode (fix the code, not the test) to address review feedback."
argument-hint: "[story-id or issue-number]"
---

You are writing integration tests for a recently merged implementation. Your working directory is the project root (the directory containing `CLAUDE.md`).

**Mode Detection:** When `{FIX_MODE}` is `true`, skip to the Fix Mode section below. Otherwise, proceed with the full test-writing workflow.

## The tier this skill owns (Integration — real infra only)

This skill writes the **Integration tier** and only behavior that **real infrastructure** can catch — SQL, constraints, migrations, transactions, queue/blob. Per `standards/testing.md` → Test Tiers and **TR-3**: do **not** re-assert the HTTP contract (routing, model binding, validation shape, status/error mapping, serialization) — that is the Contract tier's job and was already covered by `implement-ticket-v5` in the merged implementation PR. Consume the issue's behavior-first Test Coverage table: write the tests for behaviors assigned the **Integration** tier, once each. Your producer rows are **TR-3, TR-7, TR-8** — cite by ID; don't restate.

## Provided by Orchestrator

- **Story ID:** {STORY_ID}
- **Ticket Title:** {TICKET_TITLE}
- **Issue Number:** {ISSUE_NUMBER}
- **Branch:** {BRANCH_NAME}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}
- **Implementation PR:** {IMPLEMENTATION_PR} (the already-merged implementation PR number)

When running standalone (placeholders appear literally), resolve from context:
```bash
REPO_NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_OWNER=$(echo "$REPO_NWO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO_NWO" | cut -d/ -f2)
```

## Step 0: Load Context

1. Read `../TI-Engineering-Standards/CLAUDE.md` and **every file it references** — all 12 standards files. Pay special attention to `standards/testing.md`.
2. Read `CLAUDE.md` — project-specific rules
3. Read `ARCHITECTURE.md` — system design, database schema

## Step 1: Understand the Implementation

### 1a. Fetch the merged implementation PR diff

```bash
gh pr diff {IMPLEMENTATION_PR} --repo {REPO_OWNER}/{REPO_NAME}
```

### 1b. Read changed files in full

For each file in the implementation diff, read the complete file to understand the full implementation.

### 1c. Fetch the issue for acceptance criteria

```bash
gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME}
```

### 1d. Read existing integration test patterns

Find and read the project's integration test fixtures and existing tests to understand the established patterns:

- The `DatabaseFixture` and `DatabaseCollection` classes (typically in a `Fixtures/` folder within the integration test project)
- At least 2 existing test files to understand naming, setup, and assertion patterns
- Any existing endpoint tests

## Step 2: Plan Tests

Based on what was implemented, plan which integration tests to write:

**New repositories → Repository integration tests:**
- Happy path for each public method (CRUD operations)
- Edge cases: empty results, not-found, boundary values
- Unique constraint violations where applicable

**New endpoints → Integration tests for the real-infra behavior only:**
- The endpoint's effect on **real persisted state** (a POST actually writes the row; a GET reads what SQL stored; pagination returns the right rows from a real result set)
- Behavior that depends on **real constraints/transactions** (a duplicate request hits the unique constraint; a multi-step write rolls back on failure)
- **Do NOT** re-assert the HTTP contract through the endpoint — validation-error *shape*, 404 *mapping*, model binding, serialization. Those are Contract-tier behaviors (`Api.Tests`, faked) and re-testing them here is the inverted-pyramid disease the v5 model exists to stop (TR-3). If the only thing a proposed endpoint test checks is "returns 400 for a bad body," delete it — it already exists one tier down.

**New migrations → Migration verification:**
- Only if new tables/columns were added and aren't already covered by repository tests

**Scope boundaries (TR-3):**
- Integration tests exercise real SQL via Testcontainers — NOT fakes
- Do NOT duplicate Unit scenarios (logic with fakes) **or** Contract scenarios (HTTP wiring with fakes). The Integration tier covers **only** what CAN'T be reached one tier down: real SQL queries, constraints, migrations, transactions, queue/blob.
- A useful test: *"would this still pass against the fakes host?"* If yes, it belongs in Unit or Contract, not here.

## Step 3: Write Tests

Follow these patterns exactly:

### Test Class Structure

```csharp
using Shouldly;

namespace {ProjectName}.Integration.Tests.Repositories;

[Collection(DatabaseCollection.Name)]
public class {ClassName}Tests
{
    private readonly DatabaseFixture _db;

    public {ClassName}Tests(DatabaseFixture db)
    {
        _db = db;
    }

    [Fact]
    public async Task Method_name_describes_expected_behavior()
    {
        // Arrange — seed unique test data
        await using var connection = await _db.CreateOpenConnectionAsync();

        // Act — exercise the real repository/endpoint

        // Assert — verify with Shouldly
    }
}
```

### Key Patterns

- **Collection attribute:** Always `[Collection(DatabaseCollection.Name)]`
- **Fixture injection:** Constructor parameter `DatabaseFixture db`
- **Connection creation:** `await _db.CreateOpenConnectionAsync()`
- **Data isolation:** Each test seeds its own data with unique identifiers (e.g., append `Guid.NewGuid().ToString()[..8]` to names to prevent cross-test collisions)
- **Test naming:** `Snake_case_describing_behavior` — e.g., `Insert_stores_record_and_returns_id`
- **Assertions:** Shouldly — `result.ShouldNotBeNull()`, `items.Count.ShouldBe(3)`, etc.
- **No mocking:** NEVER use Moq, NSubstitute, or any mocking framework
- **Cleanup:** Tests share a database container but should not depend on other tests' data

## Step 4: Build & Test

Use the build and test commands from the project's `CLAUDE.md`:

1. Build the full solution
2. Run the fast tier (Unit + Contract) as a regression check
3. Run integration tests (Testcontainers — needs the Docker daemon)

If a test fails, **fix the code, not the test (TR-7)** — a failing test signals the code is wrong; only correct a test that was genuinely written wrong, never weaken one to pass. Every test must reach a real assertion — no silent passes, no `Skip`, no asserting buggy behavior (TR-8). You have **3 attempts** to fix failing tests before reporting as partial.

## Step 5: Commit & Push

- Stage specific files by name (never `git add .`)
- Commit message: `{STORY_ID}: Add integration tests for {short description}`
- Push: `git push -u origin {BRANCH_NAME}`

## Step 6: Create Pull Request

```bash
gh pr create --base main --head {BRANCH_NAME} --title "{STORY_ID}: Integration tests" --body "$(cat <<'EOF'
## Summary

Integration tests for the implementation merged in PR #{IMPLEMENTATION_PR}.

## Test Coverage

| Test Class | Scenarios | Status |
|------------|-----------|--------|
| `ClassNameTests` | [count] scenarios | Pass |

## Tests Added

- [List each test method and what it verifies]

## Patterns Followed

- Testcontainers with `DatabaseFixture` / `DatabaseCollection`
- Data isolation via unique test data per test
- Shouldly for all assertions
- No mocking frameworks

## TR checklist — integration (producer)

Fill PASS/FAIL **with evidence** (never a bare check). `engineering-review-v5` re-checks these adversarially in `integration-tests` mode.

| TR | Rule | Producer | Evidence |
|----|------|----------|----------|
| TR-3 | No contract re-assertion in Integration | PASS/FAIL | [every test exercises real SQL/constraints/transactions; none would pass against the fakes host] |
| TR-7 | Fix the code, not the test | PASS/FAIL | [no test weakened to pass; failures fixed in src at …] |
| TR-8 | No silent failures / no asserting buggy behavior / no `Skip` | PASS/FAIL | [every test reaches an assertion; grep shows no `Skip`] |

Relates to #{ISSUE_NUMBER}

<!-- Use "Relates to", NEVER "Closes/Fixes/Resolves #N" (here OR in commit messages). The ticket
     still has the UI stage + checkpoint to go; the orchestrator closes it at Stage 8. -->
EOF
)"
```

## Step 7: Post Issue Comment (Audit Trail)

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
## Integration Tests Added

**PR:** #[PR_NUMBER]
**Implementation PR:** #{IMPLEMENTATION_PR}

**Tests written:**
- [List test classes and scenario counts]

**Scenarios covered:**
- [Happy paths, edge cases, error scenarios]

**Status:** Ready for engineering review
EOF
)"
```

## Step 8: Cleanup — Return to main (do NOT delete the PR branch)

After the PR is created and pushed, return to `main` so the next task starts clean:

```bash
git checkout main
git pull --ff-only
```

**Do NOT delete the branch — local or remote.** It is the open PR's head; `git push origin --delete` would **close the PR**, and a headless/autonomous run has no human to recover it. The orchestrator removes the branch when it merges the PR (`gh pr merge --delete-branch`); a lingering local branch is harmless since the next stage checks out `main` anyway.

## Step 9: Report

```
STATUS: Complete | Partial | Blocked
MODE: initial
TICKET: {STORY_ID}
BRANCH: {BRANCH_NAME}
PR_NUMBER: [number]
IMPLEMENTATION_PR: {IMPLEMENTATION_PR}

TESTS_ADDED:
- TestClass: [count] scenarios
- TestClass: [count] scenarios

COVERAGE:
- Repository methods tested: [list]
- Endpoint scenarios tested: [list]
- Edge cases: [list]

BUILD: pass | fail
UNIT_TESTS: pass | fail
INTEGRATION_TESTS: pass | fail

CONCERNS:
- Any gaps in test coverage and why
```

---

## Fix Mode (When `{FIX_MODE}` is `true`)

When invoked with `{FIX_MODE}=true`, you are addressing review feedback on an existing integration test PR.

> **Fix the code, not the test (TR-7).** If an integration test fails or is flagged, the default fix is a code change — do not weaken, delete, or rewrite a test to make it pass. Only correct a test that was genuinely written wrong (asserts buggy behavior, has a silent path, re-asserts the contract instead of real-infra behavior). If a comment asks you to assert broken behavior, push back in your report rather than comply.

### Provided by orchestrator:
- **PR Number:** {PR_NUMBER}
- **Iteration:** {ITERATION}
- **Story ID:** {STORY_ID}
- **Branch:** {BRANCH_NAME}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}

### Fix Workflow:

1. **Load standards** — Read all 12 standards files, `CLAUDE.md`, `ARCHITECTURE.md`

2. **Fetch review comments:**
   ```bash
   gh api repos/{REPO_OWNER}/{REPO_NAME}/pulls/{PR_NUMBER}/comments --jq '.[] | {path: .path, line: .line, body: .body}'
   ```
   Also check top-level review bodies:
   ```bash
   gh api repos/{REPO_OWNER}/{REPO_NAME}/pulls/{PR_NUMBER}/reviews --jq '.[] | select(.state == "CHANGES_REQUESTED") | {body: .body}'
   ```

3. **Parse feedback** — Identify file, line, and required fix for each comment

4. **Read affected files** — Read each file mentioned

5. **Apply fixes** — Address each review comment

6. **Build & test** — Full build + all test suites (3 attempts max)

7. **Commit & push:**
   ```
   {STORY_ID}: Address integration test review feedback (iteration {ITERATION})
   ```
   ```bash
   git push origin {BRANCH_NAME}
   ```

8. **Cleanup: Return to main (leave the PR branch)** — Switch back to `main` so the next task starts clean. Do **NOT** delete the branch — it is the open PR's head; deleting the remote branch closes the PR. The orchestrator removes it on merge:
   ```bash
   git checkout main
   git pull --ff-only
   ```

9. **Report:**
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
   - All integration tests pass: yes/no
   - All unit tests pass: yes/no
   - Full solution builds: yes/no

   UNRESOLVED:
   - Any review comments that could not be addressed and why
   ```

---
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-21 -->
<!-- pipeline: v5 -->
