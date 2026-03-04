---
name: integration-test-v2
description: "Write integration tests for a merged implementation. Branches from main, follows existing Testcontainers patterns, creates PR. Supports FIX mode to address review feedback."
argument-hint: "[story-id or issue-number]"
---

You are writing integration tests for a recently merged implementation. Your working directory is the project root (the directory containing `CLAUDE.md`).

**Mode Detection:** When `{FIX_MODE}` is `true`, skip to the Fix Mode section below. Otherwise, proceed with the full test-writing workflow.

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

**New endpoints → Endpoint integration tests:**
- Full HTTP request/response cycle
- Validation error scenarios
- Not-found scenarios
- Pagination behavior for list endpoints

**New migrations → Migration verification:**
- Only if new tables/columns were added and aren't already covered by repository tests

**Scope boundaries:**
- Integration tests exercise real SQL via Testcontainers — NOT fakes
- Do NOT duplicate unit test scenarios — unit tests cover logic with fakes, integration tests cover real infrastructure
- Focus on what CAN'T be tested with fakes: SQL queries, constraints, migrations, HTTP pipeline

## Step 3: Write Tests

Follow these patterns exactly:

### Test Class Structure

```csharp
using FluentAssertions;

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

        // Assert — verify with FluentAssertions
    }
}
```

### Key Patterns

- **Collection attribute:** Always `[Collection(DatabaseCollection.Name)]`
- **Fixture injection:** Constructor parameter `DatabaseFixture db`
- **Connection creation:** `await _db.CreateOpenConnectionAsync()`
- **Data isolation:** Each test seeds its own data with unique identifiers (e.g., append `Guid.NewGuid().ToString()[..8]` to names to prevent cross-test collisions)
- **Test naming:** `Snake_case_describing_behavior` — e.g., `Insert_stores_record_and_returns_id`
- **Assertions:** FluentAssertions — `result.Should().NotBeNull()`, `items.Should().HaveCount(3)`, etc.
- **No mocking:** NEVER use Moq, NSubstitute, or any mocking framework
- **Cleanup:** Tests share a database container but should not depend on other tests' data

## Step 4: Build & Test

Use the build and test commands from the project's `CLAUDE.md`:

1. Build the full solution
2. Run all unit tests (regression check)
3. Run integration tests

If any tests fail, fix them. You have **3 attempts** to fix failing tests before reporting as partial.

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
- FluentAssertions for all assertions
- No mocking frameworks

Relates to #{ISSUE_NUMBER}
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

## Step 8: Report

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

8. **Report:**
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
<!-- skill-version: 2.0 -->
<!-- last-updated: 2026-03-04 -->
<!-- pipeline: v2-pr-based -->
