# Testing Standards

## Philosophy

- Tests ship with the code — they are not an afterthought
- Tests verify behavior and outcomes, not implementation details
- If a test is brittle, the design is wrong — fix the design, not the test

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
