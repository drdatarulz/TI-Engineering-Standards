# Testing Standards

## Philosophy

- Tests ship with the code — they are not an afterthought
- Tests verify behavior and outcomes, not implementation details
- If a test is brittle, the design is wrong — fix the design, not the test

## Test Tiers

> **Governing rule: test each behavior once, at the cheapest tier that can catch its failure mode.**

Every behavior belongs to exactly one tier — the cheapest one whose machinery can actually observe that behavior's failure. Re-testing the same behavior at a more expensive tier buys no additional defect detection and is the single largest driver of slow, flaky suites (the "inverted pyramid"). Each tier *owns* a class of failure and must not reach for failures another tier already owns.

| Tier | Runs in | Owns | Never put here |
|---|---|---|---|
| **Unit** (domain + fakes) | Plain process, no host | Business logic, branches, edge cases, validation rules | HTTP concerns |
| **Contract** (host + fakes, no Docker) | Real .NET host (`WebApplicationFactory`) over fakes | Routing, model binding, request/response validation, serialization shape, status/error mapping, auth wiring | **Business-logic scenarios** — those belong in Unit |
| **Integration** (host + real infra) | Real .NET host + real infrastructure (Testcontainers) | SQL, constraints, migrations, transactions, queue/blob behavior | Re-asserting the contract — that's Contract's job |
| **UI** (Playwright) | Full browser + Compose stack | Critical user journeys, end-to-end | Anything a lower tier can catch; per-screen happy/edge/error matrices |

**Contract is Integration's no-infra sibling, not a separate kind of test.** Both run the endpoint inside the *real* .NET host (`WebApplicationFactory`) — identical host machinery (routing, model binding, the middleware pipeline). The *only* difference is the slow dependency: Contract fakes it out (no Docker, nothing special needed, milliseconds), Integration uses the real thing (SQL Server via Testcontainers, seconds). That is exactly why Contract is fast — it is an integration-style wiring test with the slow dependency faked out. Read the two rows together: Contract owns the wiring seam, Integration owns what only real infrastructure can exercise.

**The Contract tier asserts the contract only.** Do not exercise business logic through the HTTP/fakes host — a happy/edge/error walk of a domain rule belongs in Unit, where it runs in milliseconds without the host. The Contract tier exists to test *our wiring of the framework* (the seam no cheaper tier can reach), not to re-run logic scenarios one tier up. A Contract test that varies business inputs to check business *outcomes* is the inverted-pyramid disease: cut it and push the scenario down to Unit.

A feature still spans tiers — a vertical slice naturally has some Unit logic, a Contract wiring test, maybe one UI journey. What is banned is the **same behavior** appearing at two tiers. Decompose the feature into behaviors; each behavior lands once, at its cheapest sufficient tier. No coverage is lost.

### Test Rules (TR) checklist

The tier model is only real if it is enforced. These are the canonical **Test Rules** — the single source of truth every skill cites *by ID* (a skill never restates a rule, it cites `TR-3`). Stable IDs are the anti-drift glue. Each rule is owned by one or more **producer** skills (refine / implement / integration-test / ui-test) and independently re-checked by the **reviewer** (`engineering-review`). Each is tagged **[CI]** — a job or branch-protection rule catches it mechanically, so the checklist cites the job rather than re-deriving — or **[JUDGMENT]** — it needs reasoning, and this is where the checklist carries the weight.

| ID | Rule | Owner-producer(s) | Tag |
|---|---|---|---|
| TR-1 | Each behavior assigned exactly one tier (no multi-tier seeding) | refine | JUDGMENT |
| TR-2 | No business logic in the Contract tier | implement | JUDGMENT |
| TR-3 | No contract re-assertion in Integration | integration-test | JUDGMENT |
| TR-4 | UI journey-scoped, not a per-screen happy/edge/error matrix | ui-test | JUDGMENT |
| TR-5 | UI conditional — skip when no user-facing surface, or surface declared out-of-scope (per surface) | ui-test | JUDGMENT |
| TR-6 | Critical-path tagged; floor 3 (advisory) / ceiling 10 (hard) | refine (declare) + ui-test (tag); **≤10 repo-wide count is reviewer-only** | CI (count) + JUDGMENT |
| TR-7 | Fix the code, not the test | implement, integration-test, ui-test (+ ci-fix) | JUDGMENT |
| TR-8 | No silent failures / no asserting buggy behavior / no `Skip` | implement, integration-test, ui-test | CI (`Skip`/waits) + JUDGMENT |
| TR-9 | POM + condition-based waits (no hardcoded waits, no inline locators) | ui-test | CI (grep) + JUDGMENT |
| TR-10 | Redundancy / lowest sufficient tier (cut the more expensive duplicate, downward-only) | **reviewer-only** | JUDGMENT |
| TR-11 | No Testcontainers/Docker in the fast tier | implement | CI (no-daemon job) |

**Dual sign-off with evidence.** Each applicable row gets two independent checks, recorded as a grid on the ticket: a **producer** column and a **reviewer** column, every cell PASS/FAIL **with evidence** — a line reference or pasted command output, never a bare check. The evidence requirement is the teeth that stops rubber-stamping. The two checks are *differentiated, not identical*: the producer self-checks **constructively** ("I assigned each behavior one tier — here's the table"); the reviewer re-checks **adversarially** ("find a behavior tested at two tiers and cut the expensive one").

**Sparse producer columns, constant reviewer column.** A producer fills only the rows it *owns* (the implementer never sees TR-3 or TR-10). The reviewer column is present on every applicable row. Some rules are **reviewer-only** because no single producer has the vantage to judge them at the moment it works:

- **TR-10 (redundancy)** needs a *cross-tier* view — each producer runs from fresh context seeing only its own tier, so it structurally cannot tell its test duplicates a cheaper one. The reviewer can, because by the time it runs the cheaper tiers have already merged to `main` (the downward-only property).
- **TR-6's ≤10 ceiling** needs a *repo-wide* count across all UI tests, not just this ticket's. (TR-6 is a hybrid: the producer ticks "I tagged this story's critical journeys"; the ceiling cell is the reviewer's.)

**General principle:** a rule is producer-checkable only when the producer has the context to judge it at the moment it works; rules needing a vantage no single producer has (cross-tier, repo-wide) fall to the reviewer alone.

**Reviewer runs are mode-scoped.** `engineering-review` emits only the rows relevant to the stage it reviews — implementation run → TR-2/7/8/11; integration run → TR-3/7/8; ui run → TR-4/5/6/7/8/9 — with **TR-10 on every run** (redundancy can surface at any tier). A reviewer FAIL on any [JUDGMENT] row → REQUEST_CHANGES, bounced back to the skill that owns the row.

## Test Integrity

A test that cannot fail is not a test. These rules apply to **every tier** (Unit, Contract, Integration, UI) and are formalized as TR-7, TR-8, and TR-10 above.

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

Route each behavior to its tier using the governing rule — *the cheapest tier that can catch its failure mode* — never "write a test at every tier." Decompose the change into behaviors and place each one once:

- **Business logic, branches, validation rules → Unit.** Always, alongside the change. Pure logic never needs the host.
- **Endpoint wiring (routing, model binding, validation shape, status/error mapping, serialization, auth) → Contract.** One wiring test per endpoint seam — *not* a re-walk of the logic scenarios already covered at Unit.
- **Behavior only real infrastructure can exercise (SQL, constraints, migrations, transactions, queue/blob) → Integration.** Only when the change actually touches infrastructure.
- **Critical user journeys → UI.** Journey-scoped and conditional (see Playwright Conventions) — never a per-screen matrix.

An API endpoint does **not** automatically get both a unit *and* an integration test. The logic lands in Unit, the wiring seam in Contract, and Integration appears only if the endpoint genuinely exercises real infrastructure. This is TR-1, seeded by `refine-story` and enforced by `engineering-review`.

## What NOT to Unit Test

- Dapper repository SQL (integration test territory)
- Cloud queue/blob behavior (integration test)
- Actual network connections (integration test)
- Third-party library internals (trust the library)

## Contract Test Conventions

- Use `WebApplicationFactory<Program>` with **all external dependencies faked** (`{Project}.Fakes`) — no Docker, no real database, no Testcontainers (TR-11)
- Assert the **HTTP contract only**: status codes, error-response shape, serialization, model-binding/validation behavior, routing, auth wiring (TR-2)
- Do **not** vary business inputs to assert business outcomes — that scenario belongs in a Unit test against the domain logic
- A Contract test should be indistinguishable from its Integration sibling except for the faked dependency; if it asserts something the fake can't meaningfully exercise, it is in the wrong tier

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

Tests execute in CI on a **self-hosted GitHub Actions runner** — the runner brings the compute (GitHub bills no minutes), and Docker workloads (SQL Server, browsers) run as the runner box's own containers with normal host networking. *When* a tier runs is governed by whether its feedback is worth its latency:

| Tier | Workflow | Trigger | Gates merge? |
|------|----------|---------|--------------|
| Fast (Unit + Contract) | `fast-tests.yml` | every `pull_request` | **Yes** — hard stop |
| Integration | `integration-tests.yml` | required pre-merge check (branch up to date with `main`) | **Yes** — hard stop |
| UI (Playwright) | `ui-tests.yml` | `workflow_dispatch` at the orchestration boundary | No |
| Environment smoke | HTTP health-check pipeline step | after deploying to dev, staging | deployment gate |

- **The fast tier gates every PR** — Unit + Contract (fakes, no Docker) — for sub-minute feedback on every push.
- **No Docker in the fast tier.** Fast-tier projects must not reference Testcontainers or Docker. The per-PR `fast-tests.yml` job runs with **no Docker daemon**, so a stray Testcontainers reference fails loudly and immediately (TR-11). That self-enforcement is what keeps the per-PR gate genuinely fast.
- **Integration is a required pre-merge check, not post-merge.** "On merge" can't gate — the code has already landed. It runs on the PR branch and **blocks** the merge until green. The branch must be **up to date with `main`** before merging, so integration re-runs against the latest `main` and catches PR-A/PR-B interactions. A merge queue automates this only if merge traffic ever makes it painful.
- **Both the fast tier and integration gate the merge** — if either fails, do not merge (hard stop).
- **The orchestrator enforces the gate; the human keeps an override.** Merges in v5 go through `orchestrate-v5`, which polls each PR's `fast-tests` + `integration-tests` checks and **will not merge a red PR**. No branch-protection setup is assumed — the gate lives in the orchestrator. A human can still **force-merge** when they judge it right; on the Free plan there's no hard block, and that manual override is intentional, not a hole.
- **These three are test workflows, not a build/deploy pipeline.** `fast-tests.yml` and `integration-tests.yml` trigger on `pull_request`; `ui-tests.yml` on `workflow_dispatch`. **None run on push to `main`.** A project keeps its own main-push workflow for build, version-stamp, frontend build, and deploy (including feeding any `workflow_run`-based CD). When adopting v5, pull the *tests* out of that workflow into the tiers and leave the build/deploy half in place — don't delete it.
- **UI does not gate.** Playwright runs at the **end of an orchestration batch** via `workflow_dispatch` — fired *scoped* (branch ref + filter input) for per-story authoring and critical-path smoke runs, and *unfiltered* for the end-of-batch regression sweep. The same trigger serves on-demand human runs. There is **no nightly run and no per-PR Playwright gate.**
- Smoke tests gate deployments — must pass after deploying to dev and staging.
- No Playwright, integration, or smoke tests run against production.

## Playwright Conventions

- Each test creates a fresh `IBrowserContext` for cookie/storage isolation
- Dev auth bypass for test environments — no real Azure AD in tests
- Semantic selectors preferred (`GetByRole`, `GetByLabel`, `GetByText`) over CSS selectors
- Shouldly assertions (same as all other test tiers)
- Tests tagged with `[Trait("Category", "Playwright")]` for CI filtering

### Critical-path journeys — floor 3 / ceiling 10

UI tests covering a critical user journey (auth, the core create→read flow, the money path) are tagged `[Trait("CriticalPath", "true")]` — the same xUnit idiom as `[Trait("Category", "Playwright")]`. Tagging makes the set **countable** (`dotnet test --filter "CriticalPath=true"` or a grep), which is exactly why the cap is an absolute band, not a percentage: a count needs no denominator, whereas a percentage of a growing suite lets per-story runtime creep back up.

- **Floor 3 (advisory):** once a UI exists, aim for at least ~3 critical-path journeys. Advisory — a one-page app may legitimately have fewer; flag, don't block.
- **Ceiling 10 (hard):** never more than 10 critical-path journeys repo-wide. Over the ceiling, `engineering-review` issues REQUEST_CHANGES and the least-critical journey is demoted. The absolute ceiling keeps per-story critical-path runtime bounded forever, regardless of total suite size.
- **Declared at refine, tagged at author, counted at review.** `refine-story` declares which journeys are critical — where journey importance is understood; don't let an agent infer criticality, it drifts. `ui-test` applies the tag. `engineering-review` counts the repo-wide tagged set. This is TR-6.

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

In the v5 pipeline these tests run on the **self-hosted runner** via `ui-tests.yml` (`workflow_dispatch`), not as a per-PR gate — see CI/CD Testing Tiers. The same Docker Compose stack runs there; the steps above are for local debugging. Playwright failures do **not** block the PR; they are handled at the orchestration boundary.
