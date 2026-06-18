# Testing Standards

## Philosophy

- Tests ship with the code — they are not an afterthought
- Tests verify behavior and outcomes, not implementation details
- If a test is brittle, the design is wrong — fix the design, not the test

## Test Integrity

A test that cannot fail is not a test. These rules apply to **every tier** (unit, integration, UI).

### Silent failures — every test must reach an assertion

Every test method must reach at least one assertion on every execution path. A test that exits without asserting reports green while the feature it claims to verify may be broken — a silently passing test is a lie. **Prohibited:**

- **Exception swallowing:** `try { /* assert */ } catch (TimeoutException) { return; }`
- **Guard-and-bail:** `if (await element.CountAsync() == 0) return;` before the real assertion
- **Conditional assertion:** `if (await element.IsVisibleAsync()) { /* assert */ }` — the assertion never runs when the element is absent

If a precondition genuinely can't be met (missing seed data, feature not deployed), the test must **fail with a clear message**, not pass quietly. A failing test is a signal.

### Assert correct behavior — fix the bug, not the test

Tests assert what the application **should** do, never what a bug currently causes it to do. If a known bug prevents the expected outcome, the test should fail — that failure is how the bug is tracked. Never rewrite an assertion to match broken behavior (e.g., asserting an error snackbar appears because delete is broken, instead of asserting the row is removed). Write the assertion for correct behavior, let it fail, and **fix the code, not the test.** A test that verifies broken behavior keeps passing long after the bug is fixed — at which point it is actively wrong and no one notices.

### Never skip tests for known bugs

Never use `Skip` / `[Fact(Skip = "...")]` (or equivalents) to disable tests for known-broken features. Skipped tests vanish from failure counts, dashboards, and CI summaries — a failing test is visible, a skipped one is forgotten. Let it run, let it fail, and track the count; when the bug is fixed the test passes automatically with no one needing to remember to unskip it.

## Frameworks

- **xUnit** — test framework
- **Shouldly** — readable assertions (`result.ShouldBe(expected)`, `items.ShouldNotBeEmpty()`, etc.)
- **Testcontainers** — Docker-based integration test infrastructure
- **Playwright** — browser-based e2e tests

## No Mocking Frameworks

- **NO Moq, NO NSubstitute, NO FakeItEasy** — ever
- Hand-roll all fakes as explicit classes in `{Project}.Fakes`
- Fakes are simple in-memory implementations of interfaces
- If a fake is painful to write, the interface is too big — split it

## Test Naming

Test names describe behavior using underscores:

```csharp
public class QueueCoordinatorTests
{
    [Fact]
    public async Task Enqueues_only_emails_within_lookahead_window()

    [Fact]
    public async Task Skips_emails_already_queued()

    [Fact]
    public async Task Does_nothing_when_no_pending_emails()
}
```

## When to Write Tests

- **Always write unit tests alongside** any new API endpoints, business logic, or behavioral changes
- **Write integration tests for changes that touch infrastructure** — new/changed API endpoints, SQL queries or repo methods, queue/storage interactions, or pipeline changes
- Integration tests use Testcontainers and verify real infrastructure behavior that unit tests with fakes cannot catch

## What NOT to Unit Test

- Dapper repository SQL (integration test territory)
- Cloud queue/blob behavior (integration test)
- Actual network connections (integration test)
- Third-party library internals (trust the library)

## Integration Test Conventions

- Each test seeds its own data with unique identifiers — no cleanup between tests
- Testcontainers launch infrastructure automatically per test run
- Use a shared fixture (`ICollectionFixture`) to start containers and run migrations once
- Use `WebApplicationFactory<Program>` with real repos + faked external services

## Pre-Existing Test Failures

- **Before making any changes**, record the current test failure count by running the full test suite
- **After making changes**, if the failure count has increased, that is a blocking issue — stop and fix it
- **Never proceed, approve, or declare work complete** while the failure count is higher than baseline
- The fact that you did not introduce a failing test is **not a justification to ignore it** — a rising failure count means the codebase is degrading and must be addressed before moving forward
- If pre-existing failures are discovered, create a follow-up ticket and surface them to the project owner — do not silently skip or filter them out

## Frontend Build Verification

When a project includes a frontend (React, Blazor WASM, or any SPA):

- **The frontend build is a required gate** — it must pass before any commit, same as `dotnet build`
- **Test runners are not build validators** — tools like Vitest, Jest, and Karma transpile files individually and do NOT perform full type checking. A passing test suite does not prove the frontend compiles.
- **Always run the frontend build command** (e.g., `npm run build`, which typically runs `tsc -b && vite build`) in addition to tests
- If a change touches shared types, DTOs, or interfaces consumed by the frontend, verify the frontend build even if no frontend files were directly modified

This applies to implement agents, review agents, and integration test agents — any agent that commits code must verify both backend and frontend builds pass.

## CI/CD Testing Tiers

| Tier | Tests | When | Infrastructure |
|------|-------|------|---------------|
| Unit tests | `*.Tests` projects (fakes) | Every PR / merge to main | None |
| Integration tests | `Integration.Tests` (Testcontainers) | Every PR / merge to main | Docker on build agent |
| Playwright UI tests | `Playwright.Tests` | Every PR (CI) | Docker Compose stack on build agent |
| Environment smoke tests | HTTP health check pipeline step | After deploying to dev, staging | Real resources |

- Unit, integration, and Playwright tests gate merges — all must pass before code reaches main
- Playwright tests run in CI against a Docker Compose stack (API + Client + SQL Server + seed data) with auth bypass enabled
- Smoke tests gate deployments — must pass after deploying to dev and staging
- No Playwright, integration, or smoke tests run against production

## Playwright Conventions

- Each test creates a fresh `IBrowserContext` for cookie/storage isolation
- Dev auth bypass for test environments — no real Azure AD in tests
- Semantic selectors preferred (`GetByRole`, `GetByLabel`, `GetByText`) over CSS selectors
- Shouldly assertions (same as all other test tiers)
- Tests tagged with `[Trait("Category", "Playwright")]` for CI filtering

### No hardcoded waits

Never use fixed-duration waits (`Task.Delay`, `WaitForTimeoutAsync`, `Thread.Sleep`) to wait for UI state — they are either too short (flaky) or too long (slow), and they hide *what* you are actually waiting for. Use condition-based waits, which auto-resolve as soon as the condition is met and fail fast at a configurable timeout:

| Instead of | Use |
|---|---|
| `await Task.Delay(2000)` | `await element.WaitForAsync()` |
| `await page.WaitForTimeoutAsync(1000)` | `await Expect(element).ToBeVisibleAsync()` |
| `await Task.Delay(500)` before asserting text | `await Expect(element).ToHaveTextAsync("expected")` |
| `await Task.Delay(3000)` waiting for navigation | `await page.WaitForURLAsync("/expected-path")` |
| `await Task.Delay(1000)` waiting for element to disappear | `await Expect(element).ToBeHiddenAsync()` |

### Page Object Model — no inline locators

Test methods must not contain element locators. All locators live in Page Object Model (POM) classes; tests interact with the page exclusively through POM methods. The POM is the single source of truth for how to find and interact with a screen — when the UI changes, you update one POM method instead of hunting through dozens of test files.

```csharp
// Prohibited — locator in the test; every test using it breaks independently when the selector changes
await _page.Locator(".submit-button").ClickAsync();

// Required — locator in the POM; one place to update
await _screenPage.SubmitAsync();
```

### Running Playwright Tests Locally

Playwright tests run against a full Docker Compose stack with seed data and auth bypass enabled.

```bash
# 1. Install Playwright browsers (one-time)
pwsh tests/{Project}.Playwright.Tests/bin/Debug/net10.0/playwright.ps1 install chromium

# 2. Start the stack with Playwright overlay
docker compose -f docker-compose.yml -f docker-compose.playwright.yml up -d --build

# 3. Wait for readiness
until curl -sf http://localhost:5001/health/ready; do sleep 2; done
until curl -sf http://localhost:5002; do sleep 2; done

# 4. Run tests
FORMIT_BASE_URL=http://localhost:5002 dotnet test tests/{Project}.Playwright.Tests/

# 5. Tear down
docker compose -f docker-compose.yml -f docker-compose.playwright.yml down
```

The `docker-compose.playwright.yml` overlay enables auth bypass (`Authentication__UseDevBypass: true`), auto-login, and runs seed data SQL after migrations complete. Seed data files live in `playwright/seed-data.sql` and grow as test stories are implemented.

In CI, the same Docker Compose stack runs as a parallel job in `ci.yml`. Playwright failures block the PR.
