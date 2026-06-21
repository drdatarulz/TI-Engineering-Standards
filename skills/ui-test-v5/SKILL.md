---
name: ui-test-v4
description: "Write automated UI tests for a merged implementation. Branches from main, follows existing Page Object Model patterns, creates PR. Supports FIX mode to address review feedback."
argument-hint: "[story-id or issue-number]"
---

You are writing Playwright UI tests for a recently merged implementation. Your working directory is the project root (the directory containing `CLAUDE.md`).

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

1. Read `../TI-Engineering-Standards/CLAUDE.md` and **every file it references** — all standards files. Pay special attention to `standards/testing.md` and `standards/environments.md`.
2. Read `CLAUDE.md` — project-specific rules
3. Read `ARCHITECTURE.md` — system design, screen inventory if present

## Step 1: Understand the Implementation

### 1a. Fetch the merged implementation PR diff

```bash
gh pr diff {IMPLEMENTATION_PR} --repo {REPO_OWNER}/{REPO_NAME}
```

### 1b. Read changed files in full

For each file in the implementation diff, read the complete file to understand the full implementation — especially any new Blazor pages, routes, or UI components.

### 1c. Fetch the issue for acceptance criteria

```bash
gh issue view {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME}
```

### 1d. Read existing UI test patterns

Find and read the project's existing UI tests and page objects to understand established patterns:

- The base test class or fixture (typically in `tests/{Project}.Playwright.Tests/`)
- At least 2 existing test files to understand naming, setup, and assertion patterns
- Existing page object classes to understand the Page Object Model structure in use

## Step 2: Plan Tests

Based on what was implemented, plan which UI tests to write. Focus on **user-visible behavior** — what a real user can do in the browser.

**New pages/screens → UI flow tests:**
- Happy path user flow for each new screen (navigate, interact, verify result)
- Validation error display (submit invalid data, verify error messages appear)
- Empty state display (when no data exists)
- Navigation — can the user get to this screen and leave it correctly

**New API-backed features → End-to-end tests:**
- Create flow: fill form, submit, verify item appears in list
- Edit flow: navigate to item, change values, verify changes persist
- Delete flow: remove item, verify it disappears

**Scope boundaries:**
- UI tests exercise the real deployed UI against a real environment — NOT unit or integration test territory
- Do NOT duplicate integration test scenarios — UI tests verify what the user sees and can do, not SQL behavior
- Focus on flows a user would actually perform, not implementation internals
- Auth bypass (`Authentication:UseDevBypass`) must be enabled in the target environment — never test against real Azure AD

## Step 3: Write Tests

Follow these patterns exactly:

### Project Structure

```
tests/{Project}.Playwright.Tests/
  Pages/               # Page Object Model classes
    {Screen}Page.cs    # One page object per screen
  Tests/
    {Feature}Tests.cs  # Test classes grouped by feature
```

### Page Object Model

```csharp
namespace {ProjectName}.Playwright.Tests.Pages;

public class {Screen}Page(IPage page)
{
    private readonly IPage _page = page;

    // Locators — use semantic selectors (role, label, text) over CSS/XPath
    private ILocator SubmitButton => _page.GetByRole(AriaRole.Button, new() { Name = "Submit" });
    private ILocator NameInput => _page.GetByLabel("Name");
    private ILocator ErrorMessage => _page.GetByRole(AriaRole.Alert);

    public async Task NavigateAsync() =>
        await _page.GotoAsync("/route-to-this-screen");

    public async Task FillNameAsync(string name) =>
        await NameInput.FillAsync(name);

    public async Task SubmitAsync() =>
        await SubmitButton.ClickAsync();

    public async Task<string> GetErrorMessageAsync() =>
        await ErrorMessage.TextContentAsync() ?? string.Empty;
}
```

### Test Class Structure

```csharp
namespace {ProjectName}.Playwright.Tests.Tests;

public class {Feature}Tests : PageTest
{
    [Fact]
    public async Task User_can_create_{entity}_and_see_it_in_list()
    {
        // Arrange
        var page = new {Screen}Page(Page);
        await page.NavigateAsync();

        // Act
        await page.FillNameAsync("Test Item");
        await page.SubmitAsync();

        // Assert
        await Expect(Page.GetByText("Test Item")).ToBeVisibleAsync();
    }

    [Fact]
    public async Task Validation_error_appears_when_{field}_is_empty()
    {
        var page = new {Screen}Page(Page);
        await page.NavigateAsync();

        await page.SubmitAsync(); // submit without filling required fields

        await Expect(Page.GetByRole(AriaRole.Alert)).ToBeVisibleAsync();
    }
}
```

### Key Patterns

- **Page Object Model:** One class per screen in `Pages/` — never put locators directly in test methods
- **Semantic selectors:** Prefer `GetByRole`, `GetByLabel`, `GetByText` over CSS selectors or XPath
- **Fresh context:** Each test class gets a fresh `IBrowserContext` — no shared state between tests
- **Test naming:** `Snake_case_describing_user_action_and_expected_result`
- **Assertions:** Playwright's `Expect()` API — `ToBeVisibleAsync()`, `ToHaveTextAsync()`, `ToBeEnabledAsync()`, etc.
- **No mocking:** Tests run against the real deployed environment with auth bypass enabled
- **Environment variable:** Use `APP_BASE_URL` for the target environment URL — never hardcode URLs

### Environment Configuration

```csharp
// Base URL should come from environment variable
// Set FORMIT_BASE_URL (or project-specific equivalent) in the CI pipeline step
// and in local launchSettings for development
```

### Docker-Based CI Execution

Playwright tests run in CI against a Docker Compose stack, not against a deployed environment. The CI pipeline:

1. Starts the full Docker Compose stack with the Playwright overlay (`docker-compose.yml` + `docker-compose.playwright.yml`)
2. The Playwright overlay enables auth bypass, auto-login, and seeds test data
3. Waits for API health (`/health/ready`) and Client readiness
4. Installs Playwright Chromium browser
5. Runs `dotnet test` with `FORMIT_BASE_URL=http://localhost:{client-port}`
6. Tears down Docker Compose (always, even on failure)

**Key points:**
- Auth bypass is enabled via the Docker Compose Playwright overlay, not via deployed environment config
- Seed data is loaded by a `playwright-seed` service in the overlay
- Playwright test failures **block the PR** — no `continue-on-error`
- No Playwright tests run post-deploy; smoke tests (health checks) are the post-deploy gate

## Step 4: Build & Test

Use the build and test commands from the project's `CLAUDE.md`:

1. Build the full solution
2. Run all unit tests (regression check)
3. Run UI tests against the local or dev environment — set `APP_BASE_URL` to the target

If tests fail, fix them. You have **3 attempts** to fix failing tests before reporting as partial.

## Step 5: Commit & Push

- Stage specific files by name (never `git add .`)
- Commit message: `{STORY_ID}: Add UI tests for {short description}`
- Push: `git push -u origin {BRANCH_NAME}`

## Step 6: Create Pull Request

```bash
gh pr create --base main --head {BRANCH_NAME} --title "{STORY_ID}: UI tests" --body "$(cat <<'EOF'
## Summary

Playwright UI tests for the implementation merged in PR #{IMPLEMENTATION_PR}.

## Test Coverage

| Test Class | Scenarios | Status |
|------------|-----------|--------|
| `{Feature}Tests` | [count] scenarios | Pass |

## Tests Added

- [List each test method and what user flow it verifies]

## Patterns Followed

- Page Object Model with dedicated page classes in `Pages/`
- Semantic selectors (role, label, text) — no CSS/XPath
- Fresh browser context per test class
- Auth bypass enabled in target environment
- `APP_BASE_URL` used for environment URL

Relates to #{ISSUE_NUMBER}
EOF
)"
```

## Step 7: Post Issue Comment (Audit Trail)

```bash
gh issue comment {ISSUE_NUMBER} --repo {REPO_OWNER}/{REPO_NAME} --body "$(cat <<'EOF'
## Playwright Tests Added

**PR:** #[PR_NUMBER]
**Implementation PR:** #{IMPLEMENTATION_PR}

**Tests written:**
- [List test classes and scenario counts]

**Scenarios covered:**
- [User flows, validation scenarios, empty states]

**Status:** Ready for engineering review
EOF
)"
```

## Step 8: Cleanup — Return to main and remove branch

After the PR is created and pushed, return to `main` so the machine is clean for the next task:

```bash
git checkout main
git pull --ff-only
git branch -d {BRANCH_NAME}
git push origin --delete {BRANCH_NAME}
```

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
- Screens tested: [list]
- User flows covered: [list]
- Validation scenarios: [list]
- Edge cases: [list]

BUILD: pass | fail
UNIT_TESTS: pass | fail
PLAYWRIGHT_TESTS: pass | fail

CONCERNS:
- Any gaps in test coverage and why
```

---

## Fix Mode (When `{FIX_MODE}` is `true`)

When invoked with `{FIX_MODE}=true`, you are addressing review feedback on an existing UI test PR.

### Provided by orchestrator:
- **PR Number:** {PR_NUMBER}
- **Iteration:** {ITERATION}
- **Story ID:** {STORY_ID}
- **Branch:** {BRANCH_NAME}
- **Repo Owner:** {REPO_OWNER}
- **Repo Name:** {REPO_NAME}

### Fix Workflow:

1. **Load standards** — Read all standards files, `CLAUDE.md`, `ARCHITECTURE.md`

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
   {STORY_ID}: Address UI test review feedback (iteration {ITERATION})
   ```
   ```bash
   git push origin {BRANCH_NAME}
   ```

8. **Cleanup: Return to main and remove branch:**
   ```bash
   git checkout main
   git pull --ff-only
   git branch -d {BRANCH_NAME}
   git push origin --delete {BRANCH_NAME}
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
   - All UI tests pass: yes/no
   - All unit tests pass: yes/no
   - Full solution builds: yes/no

   UNRESOLVED:
   - Any review comments that could not be addressed and why
   ```

---
<!-- skill-version: 4.0 -->
<!-- last-updated: 2026-03-23 -->
<!-- pipeline: v4 -->
