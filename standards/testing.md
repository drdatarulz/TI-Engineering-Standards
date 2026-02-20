# Testing Standards

## Philosophy

- Tests ship with the code — they are not an afterthought
- Tests verify behavior and outcomes, not implementation details
- If a test is brittle, the design is wrong — fix the design, not the test

## Frameworks

- **xUnit** — test framework
- **FluentAssertions** — readable assertions (`.Should().Be()`, `.Should().HaveCount()`, etc.)
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

## CI/CD Testing Tiers

| Tier | Tests | When | Infrastructure |
|------|-------|------|---------------|
| Unit tests | `*.Tests` projects (fakes) | Every PR / merge to main | None |
| Integration tests | `Integration.Tests` (Testcontainers) | Every PR / merge to main | Docker on build agent |
| Environment smoke tests | Deployment runbook checks | After deploying to dev, staging | Real resources |
| Playwright UI tests | `Playwright.Tests` | After deploying to dev, staging | Real deployed environment |

- Unit and integration tests gate merges — both must pass before code reaches main
- Smoke and Playwright tests gate promotions — must pass in dev before promoting to staging, must pass in staging before promoting to prod
- No integration, smoke, or Playwright tests run against production

## Playwright Conventions

- Page Object Model with helper classes
- Each test creates a fresh `IBrowserContext` for cookie/storage isolation
- Dev auth bypass for test environments — no real Azure AD in tests
