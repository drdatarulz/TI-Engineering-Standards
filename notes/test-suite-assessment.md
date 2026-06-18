# Test Suite Assessment — Inverted Pyramid & Go-Forward Strategy

> **Status:** Working note / assessment (2026-06-16 → 2026-06-17). Not yet implemented.
> **Origin:** Measured against the **FormIt** project, but the root cause and the recommended
> fixes are generic to the TI agentic pipeline — hence kept here in the standards repo.
> **Related:** `standards/testing.md` (the standard this critiques); the FormIt repo's
> `docs/testing-strategy-plan.md` (CI tier implementation plan, FormIt-specific).
>
> This document captures a working conversation about why agentic development over-produces
> tests, what the data actually shows, how to pare back safely, and when to run the suite in CI.
> It is meant to be read top-to-bottom and continued in a later session.

---

## 1. The Question

> "We are writing way too many tests. We love tests and want tests, but we subscribe to the
> testing pyramid: most tests unit, then integration, then UI. Agentic development is generating
> too many. Assess."

---

## 2. Diagnosis — the pyramid is inverted (an "ice-cream cone")

Measured footprint of the FormIt suite (xUnit `[Fact]`/`[Theory]` method counts):

| Layer | Tests | Share | Cost to run |
|---|---:|---:|---|
| **Domain** (pure unit, fakes) | 66 | 1.6% | milliseconds |
| Api.Tests (in-proc HTTP + fakes) | 1,000 | 23.6% | fast (no Docker) |
| McpServer.Tests (fakes) | 509 | 12.0% | fast (no Docker) |
| **Integration** (Testcontainers / real SQL) | 1,913 | 45.1% | Docker, slow |
| **Playwright** (full browser stack) | 757 | 17.8% | Docker Compose, slowest |
| **Total** | **~4,245** | 100% | — |

A healthy pyramid is roughly **70 / 20 / 10** unit / integration / UI. FormIt is top-heavy:
the single largest tier (Integration, 45%) is the slowest-but-one, and the **slowest 63%**
(Integration + Playwright) carries verification load that belongs in fast unit tests.

**Corroborating signals:**
- **Pure-unit starvation:** only 66 Domain tests (1.6%). Business logic is largely validated
  *through the database and the browser* rather than in isolation.
- **Per-feature duplication:** "Form" is exercised across 18 Domain + 69 Api + 111 Integration +
  **313 Playwright** files — the same behavior re-verified at every layer, weighted toward the
  most expensive one.
- **Maintenance tax already visible:** 4 of the 5 most recent commits at time of assessment were
  Playwright stabilization ("batch 6", "batch 7", "Stabilize GherkinRuleEditor…",
  "Stabilize FormOverlaySlot…"). The inverted pyramid is already costing firefighting time.

### 2a. Honest correction to the headline numbers

The first framing ("1.6% unit") was rhetorically selective. Three of the five tiers were used in
the 70/20/10 comparison (Domain + Integration + Playwright = 64.6%), quietly dropping
**Api.Tests (23.6%) + McpServer.Tests (12%) = ~36%**.

Two legitimate inferences from that gap:

1. **The inversion is real but milder than "1.6% unit" implies.** Api.Tests and McpServer.Tests
   are fast, fakes-based, in-process tests. Counting them as unit-ish, the *fast* tier is **~37%**
   (66 + 1,000 + 509 = 1,575), not 1.6%. So the shape is **~37% fast / ~45% integration /
   ~18% UI** — top-heavy, not collapsed.
2. **~36% of the suite does not slot cleanly into unit/integration/UI.** Api.Tests and
   McpServer.Tests are *endpoint / HTTP-boundary tests with fakes* — not pure unit (they test
   through the API seam), not integration (no real infra), not UI. That is a real fourth category
   — **component / contract tests** — and the fact that it is a *third of everything* means the
   suite is **not actually organized as a pyramid**. There is a large middle tier the standard
   never names, and that undefined ownership is itself a driver of duplication: when no rule says
   which tier owns endpoint behavior, every tier tests it "to be safe."

---

## 3. Root cause — it is the *shape* of the pipeline, not any single test

No individual test is obviously wrong. The pipeline's structure guarantees the count regardless:

1. **Test-writing is purely additive across three skills and three PRs.**
   `implement-ticket-v4` writes unit tests → `integration-test-v4` adds integration tests (PR #2)
   → `ui-test-v4` adds UI tests (PR #3). Each runs from fresh context, blind to the others' actual
   test bodies. **No stage ever subtracts.**
2. **Each tier carries its own multiplicative mandate.** "happy + edge + not-found + validation +
   constraint *for each public method / endpoint / screen*" appears independently in the
   integration skill, the UI skill, *and* the review checklist. Count ≈ (methods × ~5 scenarios)
   replicated at **every** tier.
3. **The standard itself prescribes the duplication.** `standards/testing.md` (lines ~43–45)
   mandates *both* a unit test *and* an integration test for "new/changed API endpoints." Api.Tests
   (WebApplicationFactory + fakes) and Integration.Tests (WebApplicationFactory + real DB) are
   therefore two HTTP-level suites over the same endpoints **by design**.
4. **Anti-duplication guardrails are one-directional and qualitative.** The skills say "don't
   re-test SQL at the UI layer," but explicitly permit re-testing the same CRUD happy-path at unit,
   integration, *and* UI. They forbid the cheap overlap and wave through the expensive one.
5. **`engineering-review-v4` is a one-way ratchet.** It can REQUEST_CHANGES for *missing*
   "happy/edge/error per method" coverage (up to 3 iterations × 3 stages) but has no rule to flag
   *redundant* or *over*-testing. Every feedback loop pushes the count **up**.
6. **No pyramid ratio, per-tier budget, or "lowest sufficient tier" rule exists anywhere** — not in
   `standards/testing.md`, not in any skill. Full-matrix coverage at every layer is the *default*.

---

## 4. How to pare back — safely

### Principle: don't do a blind global sweep. Fix the faucet before you mop.

A one-time "read all 4,000 tests and delete redundant ones" pass is the tempting move and the
wrong *first* move:

- **Deletion is asymmetric.** Wrongly removing a test that would have caught a regression costs far
  more than keeping a redundant one. An agent making thousands of keep/cut calls without the
  originating story context will have a real error rate.
- **It treats the symptom.** If the pipeline keeps over-producing, the problem returns in months.
- **"Fewer tests" is the wrong goal.** The goal is **less cost** (runtime, flakiness, maintenance)
  at **constant defect-detection**. Optimizing raw count would push toward deleting cheap fast unit
  tests — exactly backwards from what an inverted pyramid needs.

### The safety mechanism: measure, don't vibe

The standing objection to consolidation is "how do we know we didn't lose coverage?" There is an
objective answer: **mutation testing (e.g. Stryker.NET) + coverage delta.** If you remove a test and
branch coverage / mutation score does **not** drop, it was redundant *by definition* — something
else already kills that mutant. Every consolidation PR should show before/after on:

- (a) suite wall-clock runtime,
- (b) flaky rate,
- (c) mutation score.

**Runtime down + mutation score flat = pure win.**

### Sequencing

1. **One-time cleanup — scoped & piloted, not global.** Pick the single hottest area first
   (on FormIt: Forms — 313 Playwright files), consolidate the expensive tiers there (the browser
   tests and the integration tests), and prove it with the metrics above before touching anything
   else. The pilot also *calibrates the criteria* the ongoing process reuses.
2. **Long-term — preventive per-ticket (primary), periodic sweep (safety net only).**
   - **Per-ticket is where context is richest.** At the end of a ticket's test cycle the agent knows
     *why* each test exists and what the lower tiers just covered — the cheapest, most accurate
     moment to ask "is this already tested one tier down?" A holistic sweep months later has the
     *least* context and the *most* risk; it is the worst place to make cut decisions.
   - **The fix is a missing subtractive step, not a new skill.** Add a consolidation gate at the end
     of the ticket's full test cycle (after `ui-test-v4`, when all tiers exist) that reviews the
     *whole ticket's* test footprint across tiers and enforces "lowest sufficient tier."
   - **Flip `engineering-review-v4` to a two-way gate** — it already checks for *missing* coverage;
     it should equally flag *redundant* coverage.
   - **The periodic holistic run is a detector, not the main mechanism.** Run on a cadence (or when
     suite runtime crosses a threshold); have it report the pyramid ratio + hot spots and *propose*
     consolidations as a reviewed PR — never auto-delete.

Mental model: **per-ticket prevention keeps it from growing back; the one-time pilot pays down what
exists; the periodic sweep is the smoke detector.** Global-sweep-only = mopping with the faucet on.

---

## 5. Recommended changes to standards & skills

In priority order — the leverage is in the standard and the three test-writing skills, not in any
test file:

1. **Add a governing principle to `standards/testing.md`:** *"Test each behavior once, at the
   cheapest tier that can catch its failure mode."* This reframes layers as **non-overlapping
   responsibilities**:
   - **unit** → logic / branches,
   - **integration** → SQL / constraints / migrations / pipeline,
   - **UI** → critical user journeys only.
2. **Fix `standards/testing.md` lines ~43–45** so endpoints don't mandate both unit *and*
   integration. Logic → unit; integration only when real infra is exercised.
3. **Make UI tests opt-in per story, capped at critical paths.** Playwright should be smoke / journey
   coverage (dozens, not hundreds). This alone kills the flakiness firefighting.
4. **Make `engineering-review-v4` two-way:** add an over-coverage / redundancy check, and verify the
   pyramid *ratio*, not just per-method completeness.
5. **Resolve the Api.Tests vs Integration.Tests overlap** — pick one HTTP-level suite per endpoint
   (real DB) and push everything else down to true unit tests against domain logic. Name the
   "component/contract" tier explicitly so ownership is defined.
6. **Change the `refine-story-v4` Test Coverage table** to assign each behavior a *single* tier up
   front, so the matrix is never seeded multi-tier.

---

## 6. When to run the tests in CI/CD

Constraint: the integration + unit battery is ~15–20 min; it must **not** block every commit. The
answer is to stop treating "the tests" as one thing and run each tier when its feedback is worth its
cost.

1. **Tiered triggers — fast tests per-PR, slow tests on merge.** Gate every PR on only the fast layer
   (Domain + Api + McpServer fakes-based tests — seconds, no Docker). Run the slow Integration +
   Playwright battery on **merge to main**, not per-commit. Sub-minute feedback on every push; the
   expensive suite runs once per merge. A post-merge failure reverts / rolls forward — rare, because
   the fast tier already caught most breakage.
2. **Nightly (+ on-demand) for the heaviest tier.** Push Playwright specifically to a **scheduled
   nightly** run plus a manual `workflow_dispatch` trigger. Browser tests are the slowest and
   flakiest; they don't need to run on every merge to be valuable. Keep only a tiny critical-path
   browser smoke set in the per-merge gate.
3. **Path-filtered / changed-scope runs.** Run only the tiers a change touches — a Domain-only PR
   skips Playwright; a migration PR runs Integration. GitHub Actions `paths` filters or a
   `dotnet test` filter by changed project gives most of the speedup with none of the risk.

**Recommendation:** Do #1 now (matches current state — tests just got running): fast tier blocks PRs,
full suite runs on merge to main. Add #2 (nightly Playwright) the moment the merge run crosses
~10 minutes. Treat #3 as a later optimization.

This reinforces the pyramid work: the more behavior pushed down into the fast tier, the more the
per-PR gate covers. **When you run tests and how they're shaped are the same problem.**

---

## 7. Go-forward (recommended order)

1. **Process fix first (stop the bleeding).** Update `standards/testing.md` with the lowest-tier
   rule, add the end-of-ticket consolidation gate, and make the review two-way.
2. **Piloted paydown.** Consolidate one hot area's expensive tiers (FormIt: Forms); report
   before/after on runtime + mutation score; use it to calibrate criteria.
3. **CI tiering.** Implement §6 #1 (fast-per-PR / full-on-merge); the FormIt repo's
   `docs/testing-strategy-plan.md` holds the project-specific pipeline blueprint.
4. **Periodic detector.** Add the holistic sweep as a cadence job that *reports* and *proposes*,
   never auto-deletes.

**Metric that governs all of it:** optimize **cost at constant defect-detection**, not test count.

---

## 8. → Moved to its own document

The working-session decisions that grew out of this assessment now live in their own spec:
**[`notes/v5-changes.md`](v5-changes.md)** — the going-forward **v5 pipeline & standards changes**.

This assessment (§§1–7) remains the *origin and rationale*; `v5-changes.md` is the *actionable spec*
(trigger model, test tiers, the subtractive review gate, UI-test volume, the orchestration
architecture, the self-hosted-runner execution model, and the UI-test anti-patterns now in
`standards/testing.md`).
