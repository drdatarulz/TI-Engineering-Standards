---
name: ui-test-v5
description: "Write Playwright UI tests for a merged implementation — journey-scoped (TR-4), conditional per surface (TR-5), critical-path tagged (TR-6). Runs the new tests via a scoped workflow_dispatch to the self-hosted runner. Creates PR. Supports FIX mode (fix the code, not the test)."
argument-hint: "[story-id or issue-number]"
---

You are writing Playwright UI tests for a recently merged implementation. Your working directory is the project root (the directory containing `CLAUDE.md`).

**Mode Detection:** When `{FIX_MODE}` is `true`, skip to the Fix Mode section below. Otherwise, proceed with the full test-writing workflow.

## The tier this skill owns (UI — critical user journeys)

This skill writes the **UI tier**: critical user **journeys**, end-to-end, and nothing a lower tier can catch. Per `standards/testing.md` → Test Tiers and Test Rules:

- **Journey-scoped (TR-4)** — new/changed user journeys only, **never** a per-screen happy/edge/error matrix. Validation-error display, empty states, field-level rules belong to Unit/Contract; do not re-walk them in the browser.
- **Conditional (TR-5)** — skip UI authoring entirely when there is no user-facing surface, or when the surface is declared out of UI-tier scope (see the UI scope gate below).
- **Critical-path tagged (TR-6)** — the journeys `refine-story-v5` marked `Critical? ✓` get `[Trait("CriticalPath","true")]`. You **tag**; you do not decide criticality (that was declared at refine — inferring it drifts).
- **Test integrity (TR-8) + anti-patterns (TR-9)** — every test reaches a real assertion (no silent fail, no `Skip`); Page Object Model + condition-based waits (no hardcoded waits, no inline locators).
- **Execution (#8)** — the orchestration runs in a container that cannot run Docker, so UI tests execute on the **self-hosted runner** via a scoped `workflow_dispatch`, not locally. Your producer rows are **TR-4, TR-5, TR-6, TR-7, TR-8, TR-9** — cite by ID; don't restate.

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

## Step 1.5: UI scope gate (TR-5) — decide whether to author at all

UI authoring is **conditional**. Before planning any test, decide whether this story warrants UI-tier tests:

**Skip — report `STATUS: Skipped` — when either holds:**
1. **No user-facing surface changed.** The implementation PR touched no `.razor` page/component/route (the orchestrator detects this via `.razor` presence; confirm from the diff you read in Step 1).
2. **The surface is declared out of UI-tier scope, per surface.** A specific surface is declared (in the issue or the project's screen inventory) as out of scope because tooling can't economically reach it — browser-extension content scripts, native OS dialogs, third-party iframes. Frame this as a **declared scope decision, not "untestable"** (Playwright *can* drive most things; it's an ROI call). Decide **per surface**, never per project — a normal Blazor page in the same project still gets tested. This guards against one awkward corner silently zeroing out all UI coverage.

When skipping, report and STOP (do not open a PR):

```
STATUS: Skipped
MODE: initial
TICKET: {STORY_ID}
SKIP_REASON: [no user-facing surface changed | surface {name} declared out of UI-tier scope]
```

Otherwise continue to Step 2. If only *some* surfaces are out of scope, author for the in-scope ones and note the excluded surface(s) in the report (TR-5 evidence).

## Step 2: Plan Tests (journey-scoped — TR-4)

Plan **user journeys**, not a per-screen matrix. A journey is a path a real user takes to accomplish something; author the **new/changed** journeys this story introduced, once each. Read the issue's behavior-first Test Coverage table and write the UI-tier behaviors — especially the ones marked `Critical? ✓`.

**New/changed journeys → one end-to-end test each:**
- The core happy-path journey for the feature (navigate → act → verify the user-visible outcome)
- A distinct journey only if it is genuinely a *different path* a user takes (e.g. create vs. edit vs. delete are separate journeys), not a parameter variation of the same one

**Do NOT author (TR-4 — these belong to lower tiers):**
- Per-screen validation-error display, empty states, field-level rules — a happy/edge/error matrix per screen is the inverted-pyramid disease. Validation logic → Unit; the 400/error *shape* → Contract.
- Anything that would still pass without a browser — that is not a UI-tier behavior.

**Critical-path tagging (TR-6):** for each journey the issue marked `Critical? ✓`, tag the test `[Trait("CriticalPath","true")]`. Do not invent criticality here — only tag what refine declared. (The reviewer enforces the ≤10 repo-wide ceiling.)

**Scope boundaries:**
- Do NOT duplicate Integration scenarios — UI verifies what the user sees and does, not SQL behavior.
- Auth bypass (`Authentication:UseDevBypass`) must be enabled in the target environment — never test against real Azure AD.

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
    // Tag journeys refine declared Critical? ✓ — this is the money/core path (TR-6).
    [Fact]
    [Trait("Category", "Playwright")]
    [Trait("CriticalPath", "true")]
    public async Task User_can_create_{entity}_and_see_it_in_list()
    {
        // Arrange
        var page = new {Screen}Page(Page);
        await page.NavigateAsync();

        // Act
        await page.FillNameAsync("Test Item");
        await page.SubmitAsync();

        // Assert — condition-based wait, not a hardcoded delay (TR-9)
        await Expect(Page.GetByText("Test Item")).ToBeVisibleAsync();
    }

    // A *different* journey (edit), not a parameter variation of create. A non-critical
    // journey omits the CriticalPath trait. Per-field validation does NOT go here (TR-4).
    [Fact]
    [Trait("Category", "Playwright")]
    public async Task User_can_edit_{entity}_and_see_the_change_persist()
    {
        var page = new {Screen}Page(Page);
        await page.NavigateToExistingAsync("Test Item");

        await page.RenameAsync("Renamed Item");

        await Expect(Page.GetByText("Renamed Item")).ToBeVisibleAsync();
    }
}
```

### Key Patterns

- **Page Object Model:** One class per screen in `Pages/` — never put locators directly in test methods
- **Semantic selectors:** Prefer `GetByRole`, `GetByLabel`, `GetByText` over CSS selectors or XPath
- **Fresh context:** Each test class gets a fresh `IBrowserContext` — no shared state between tests
- **Test naming:** `Snake_case_describing_user_action_and_expected_result`
- **Assertions:** Playwright's `Expect()` API — `ToBeVisibleAsync()`, `ToHaveTextAsync()`, `ToBeEnabledAsync()`, etc.
- **Condition-based waits (TR-9):** never `Task.Delay`, `WaitForTimeoutAsync`, or `Thread.Sleep` to wait for UI state — use `Expect(...)` / `WaitForAsync` which resolve as soon as the condition is met and fail fast. See `standards/testing.md` → No hardcoded waits.
- **No silent failures / no `Skip` (TR-8):** every test must reach ≥1 real assertion on every path — no guard-and-bail (`if (count == 0) return;`), no conditional assertion, no exception-swallow, no `[Fact(Skip=...)]`. A precondition that can't be met must **fail clearly**, not pass quietly. Assert what the app *should* do; never rewrite an assertion to match a bug.
- **No mocking:** Tests run against the real deployed environment with auth bypass enabled
- **Environment variable:** Use `APP_BASE_URL` for the target environment URL — never hardcode URLs

### Environment Configuration

```csharp
// Base URL should come from environment variable
// Set FORMIT_BASE_URL (or project-specific equivalent) in the CI pipeline step
// and in local launchSettings for development
```

### Execution model — scoped runner dispatch (#8), NOT local, NOT a PR gate

The orchestration runs inside a container that **cannot run Docker**, so Playwright/Compose execute on the **self-hosted runner** via `ui-tests.yml` (`workflow_dispatch`). The UI tier does **not** gate the PR — it runs at the orchestration boundary, and *you* validate the new tests now by a **scoped** dispatch filtered to just them.

- The runner job starts the Compose stack with the Playwright overlay (auth bypass, auto-login, seed data), waits for readiness, installs Chromium, runs `dotnet test`, and tears down — all on the runner box. You don't run any of that locally.
- The same `ui-tests.yml` runs *unfiltered* at the end-of-batch boundary for regression; your job here is only the new tests + critical-path smoke.

## Step 4: Build, commit & push (so the runner can check it out)

1. Build the full solution; run the fast tier (Unit + Contract) as a local regression check (no Docker).
2. Stage specific files by name (never `git add .`).
3. Commit: `{STORY_ID}: Add UI tests for {short description}`
4. Push so the runner can reach the branch: `git push -u origin {BRANCH_NAME}`

## Step 5: Run the new tests on the runner (scoped dispatch — #8)

The UI tier executes on the self-hosted runner, not locally. **Dispatch `ui-tests.yml` scoped to this story's tests** — pass the branch as `ref` and a `--filter` that selects only the new tests (and the critical-path smoke set):

```bash
# Scoped per-story authoring run (filter to this story's tests and/or CriticalPath=true).
# Empty filter = full suite — do NOT use that here.
gh workflow run ui-tests.yml --ref {BRANCH_NAME} \
  -f ref={BRANCH_NAME} \
  -f filter="FullyQualifiedName~{Feature}Tests"

# Poll the run to completion and surface pass/fail
run_id=$(gh run list --workflow=ui-tests.yml --branch {BRANCH_NAME} --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$run_id" --exit-status
```

**Fix-loop on the result.** If the run fails, **fix the code, not the test (TR-7)** — a failing UI test signals the feature is broken; only correct a test that was genuinely written wrong (silent path, hardcoded wait, asserting buggy behavior). Commit, re-push, re-dispatch. You have **3 attempts** before reporting as partial. (Per-dispatch latency is why this stays *scoped*, not the full suite.)

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

## TR checklist — ui (producer)

Fill PASS/FAIL **with evidence** (never a bare check). `engineering-review-v5` re-checks these adversarially in `ui-tests` mode (and counts the repo-wide critical-path ceiling, TR-6).

| TR | Rule | Producer | Evidence |
|----|------|----------|----------|
| TR-4 | UI journey-scoped, not a per-screen happy/edge/error matrix | PASS/FAIL | [each test is a distinct user journey; no per-field validation/empty-state tests] |
| TR-5 | UI conditional — authored only in-scope surfaces | PASS/FAIL | [surface(s) covered; any declared out-of-scope: name + reason] |
| TR-6 | Critical-path journeys tagged `[Trait("CriticalPath","true")]` | PASS/FAIL | [journeys tagged = the ones refine marked Critical? ✓; count] |
| TR-7 | Fix the code, not the test | PASS/FAIL | [no test weakened to pass; failures fixed in src at …] |
| TR-8 | No silent failures / no asserting buggy behavior / no `Skip` | PASS/FAIL | [every test reaches an assertion; grep shows no `Skip`] |
| TR-9 | POM + condition-based waits (no hardcoded waits, no inline locators) | PASS/FAIL | [locators in `Pages/`; grep shows no `Task.Delay`/`WaitForTimeout`/`Thread.Sleep`] |

## Runner result

- Scoped `ui-tests.yml` dispatch on `{BRANCH_NAME}`: [run link] — pass/fail

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

> **Fix the code, not the test (TR-7).** A failing or flagged UI test signals the *feature* is broken — the default fix is a code change. Do not weaken a test, swap a condition-wait for a hardcoded delay, add a `Skip`, or assert the bug to go green. Only correct a test that was genuinely written wrong. If a comment asks you to assert broken behavior, push back in your report rather than comply. Re-validate fixes by re-dispatching the **scoped `ui-tests.yml`** on the runner (Step 5 above), not locally.

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
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-21 -->
<!-- pipeline: v5 -->
