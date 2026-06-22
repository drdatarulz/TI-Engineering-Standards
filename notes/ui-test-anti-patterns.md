# UI Test Anti-Patterns

## Silent Failures

A test that cannot fail is not a test. Any pattern that allows a test method to exit without executing its assertions is a **silent failure** — the test suite reports green while the feature it claims to verify may be broken.

### Prohibited patterns

- **Exception swallowing:** `try { /* assert */ } catch (TimeoutException) { return; }` — If the element never appears, the test passes silently instead of reporting the failure.
- **Guard-and-bail:** `if (await element.CountAsync() == 0) return;` or `if (!condition) return;` before the real assertion — If the precondition isn't met, the test exits without verifying anything.
- **Conditional assertion:** `if (await element.IsVisibleAsync()) { element.ShouldHaveText("expected"); }` — If the element isn't visible, the assertion never runs.

Every test method must reach at least one assertion on every execution path. If a precondition genuinely can't be met (missing seed data, feature not deployed), the test should **fail with a clear message**, not pass quietly. A failing test is a signal; a silently passing test is a lie.

---

## Hardcoded Waits

Never use fixed-duration waits (`Task.Delay`, `WaitForTimeoutAsync`, `Thread.Sleep`) to wait for UI state. Hardcoded waits are either too short (causing flaky failures) or too long (slowing the suite unnecessarily), and they mask the real question: *what condition are you actually waiting for?*

### Use condition-based waits instead

| Instead of | Use |
|---|---|
| `await Task.Delay(2000)` | `await element.WaitForAsync()` |
| `await page.WaitForTimeoutAsync(1000)` | `await Expect(element).ToBeVisibleAsync()` |
| `await Task.Delay(500)` before asserting text | `await Expect(element).ToHaveTextAsync("expected")` |
| `await Task.Delay(3000)` waiting for navigation | `await page.WaitForURLAsync("/expected-path")` |
| `await Task.Delay(1000)` waiting for element to disappear | `await Expect(element).ToBeHiddenAsync()` |

Condition-based waits auto-resolve as soon as the condition is met and fail fast at a configurable timeout. They make the test's intent explicit — "wait until the submit button is enabled" communicates what the test needs in a way that "wait 2 seconds" never can.

---

## Asserting Buggy Behavior

Tests must assert what the application **should** do, never what a bug currently causes it to do. If a known bug prevents the expected outcome, the test should fail — that failure is how the bug is tracked.

**Example of the violation:** A delete flow is broken due to a backend bug. Instead of asserting the row is removed after deletion, the test is rewritten to assert an error snackbar appears. The test now passes, the suite is green, and the bug is invisible.

**The rule:** Write the assertion for the correct behavior and let the test fail. Fix the bug, not the test. A test that verifies broken behavior will keep passing long after the bug is fixed — at that point it's actively wrong and no one will notice.

---

## Skipping Tests for Known Bugs

Never use `Skip` attributes, `[Fact(Skip = "...")]`, or equivalent mechanisms to disable tests that exercise known-broken features. Skipped tests disappear from the test run entirely — they don't show up in failure counts, dashboards, or CI summaries.

A failing test is visible. A skipped test is forgotten. Let it run, let it fail, and track the failure count. When the bug is fixed, the test starts passing automatically with no action needed. Skipped tests require someone to remember to unskip them — and no one does.

---

## Inline Locators in Test Methods

Test methods must not contain element locators. All locators belong in Page Object Model classes, and test methods interact with the page exclusively through POM methods.

**Prohibited:**

```csharp
// Locator lives in the test — if the selector changes, every test that uses it breaks independently
await _page.Locator(".submit-button").ClickAsync();
var name = await _page.GetByLabel("Name").InputValueAsync();
```

**Required:**

```csharp
// Locator lives in the POM — one place to update when the UI changes
await _screenPage.SubmitAsync();
var name = await _screenPage.GetNameValueAsync();
```

The POM is the single source of truth for how to find and interact with elements on a screen. When the UI changes, you update one POM method instead of hunting through dozens of test files.

---
