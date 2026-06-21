# v5 Pipeline & Standards Changes

> **Status:** Design spec, in progress (2026-06-17 → 2026-06-18). Mostly decided; not yet implemented
> (except #9, which is live).
> **Origin:** Grew out of [`notes/test-suite-assessment.md`](test-suite-assessment.md) — the
> inverted-pyramid assessment. That document is the *why*; this one is the *what we're changing*.
> Section references like "§3" / "§7" point back to the assessment.
> **Scope:** Going-forward changes to the TI pipeline skills and standards that will constitute **v5**.
> Paydown of *existing* tests is explicitly out of scope (see #4).

## Status at a glance

| Item | Topic | Status |
|---|---|---|
| Trigger model | fast/PR, integration/required-pre-merge, UI at boundary | Decided |
| Fix-code-not-test | a failing test → fix the code, not the test | Decided |
| A | the "in-between" contract tier — keep, narrow to the seam | Resolved |
| B | validate new UI tests per-story + critical-path smoke (3–10) | Resolved |
| #1 | integration = required **pre-merge** check | Resolved |
| #2 | subtractive redundancy check in `engineering-review` | Resolved |
| #3 | UI test **volume** — conditional + journey-scoped | Resolved |
| #4 | mutation-testing safety mechanism | **Deferred** (paydown only) |
| #5 | ratio→cleanup, fix-code-not-test home, no-Docker fast tier | Resolved |
| #6 | orchestration architecture (mode-switching + dumb loop) | Resolved |
| #7 | `refine-story` auto-reveals withheld considerations | Resolved |
| #8 | execution model — self-hosted runner | Resolved |
| #9 | UI anti-patterns into `testing.md` | **Done** (committed `de70473`) |
| #10 | checklist enforcement — TR rules, dual producer/reviewer sign-off | Resolved |
| — | concurrent overseer | Shelved (upgrade) |
| — | batch blame / nightly | Not concerns |

---

## Cross-cutting decisions

- **Trigger model.** Fast tier runs on **every PR**. The integration tier is a **required
  pre-merge check on the PR branch** — it runs *before* the merge and **blocks** it until green
  (not "on merge"/post-merge, which can't gate). **Both the fast tier and the integration tier gate
  the merge** — if either fails, **do not merge** (hard stop). The branch must be **up to date with
  `main`** before merging so integration re-runs against latest `main` (catches PR-A/PR-B
  interactions); a merge queue automates this only if merge traffic ever makes it painful. UI tier
  does **not** gate; it runs at the orchestration boundary.
- **UI tier timing.** Run the Playwright suite at the **end of an orchestration batch**, then fall
  into the fix loop. **Drop the nightly.** The same `workflow_dispatch` trigger serves on-demand
  human runs.
- **Fix the code, not the test.** A failing test is a signal that the *underlying code* is wrong —
  the default response is a **code change, not a test change**. Editing a test is reserved only for a
  test that was genuinely written poorly; we never modify a test just to make it pass.
- **Blame is not a concern.** Per-story attribution of UI failures doesn't matter — the suite runs at
  the end and **the fix is the only thing that matters**; the failure itself is the context.

---

## Test-tier & UI-test decisions (threads A–B)

- **A. The "in-between" tier — keep it, but narrow it hard.** Tests that use the .NET
  hosting framework (e.g. `WebApplicationFactory`) over **fakes** are testing **our wiring of the
  framework** (routing, model binding, validation, serialization shape, status/error mapping, auth
  wiring) — that seam *is* our code, and no cheaper tier can catch it. So we **keep** the tier. What
  we **stop** is using it to re-run **business-logic scenarios** (happy/edge/error walks) — that
  duplicates the unit tier and is the inverted-pyramid disease. The precise rule is *"contract only,
  business logic goes down to unit."*

  **Actionable for v5 — three parts:**

  1. **`standards/testing.md` gets a "Test Tiers" table** that names each tier and states *what it
     owns* and *what to never put there*. The table is the explicit "when we want them / when we
     don't":

     | Tier | Owns | Never put here |
     |---|---|---|
     | **Unit** (domain, fakes) | Business logic, branches, edge cases | HTTP concerns |
     | **Contract** (host + fakes, no Docker) | Routing, model binding, validation, serialization shape, status/error mapping, auth wiring | **Business-logic scenarios** — those belong in Unit |
     | **Integration** (host + real infra) | SQL, constraints, migrations, transactions | Re-asserting the contract — that's the Contract tier's job |
     | **UI** (Playwright) | Critical user journeys | Anything a lower tier can catch |

     Governing rule above the table: *"test each behavior once, at the cheapest tier that can catch
     its failure mode."*
  2. **Precise prohibition, not a ban.** State explicitly: *"do not exercise business logic through
     the HTTP/fakes host — the Contract tier asserts the contract only."* A flat ban on the tier
     would throw away the seam coverage we're keeping. Optional louder signal: a one-line pointer in
     CLAUDE.md's "Things NOT To Do" referencing the tier table.
  3. **Enforcement makes it real (two skills).** `refine-story-v5` assigns each behavior **one** tier
     up front so the matrix is never seeded multi-tier; `engineering-review-v5` checks the boundary
     **both ways** — flags business logic sitting in the Contract tier *and* contract re-assertion
     sitting in Integration. Standard defines it → refine seeds it → review keeps it honest.

  New projects inherit this automatically: standard ships the tier table, project CLAUDE.md inherits
  it, review gate enforces it from day one — no per-project decision needed.

- **B. Validate new UI tests as they're written.** A test that has never been executed is
  a hypothesis, not a test; in agentic flow the UI test's first run is the *first time anything has
  observed the running feature*. Waiting until the end of a batch to run all of them for the first
  time risks building later stories on top of an already-broken earlier one. Split the work by job:

  - **Authoring correctness → per story.** After authoring a story's UI tests, `ui-test-v5` **runs
    just those new tests** and fix-loops right there before the story's test cycle is declared done.
    **Execution goes through the #8 path, not locally** — the orchestration runs inside a Docker
    container and *cannot run Docker itself*, so Playwright/Compose must execute on the self-hosted
    runner. Mechanically: a **scoped `workflow_dispatch`** of `ui-tests.yml` against the story's
    branch, **filtered to the new tests**; the skill polls the run and fix-loops on the result.
    (Latency per dispatch is why this stays *scoped*, not the full suite.)
  - **Regression → end-of-batch boundary.** The end-of-orchestration run stays — same `ui-tests.yml`
    on the runner but **unfiltered (full suite)** — its job narrowed to catching regressions a
    *later* story introduced into an *earlier* story's UI.
  - **Critical-path smoke set, run per story alongside the new tests** (same scoped runner dispatch).
    Catches in-batch regressions story-by-story instead of all at the end.

  **Critical-path set — the cap (this is the reviewable rule):**
  - It's an **absolute band, not a percentage.** A percentage *of total tests* backfires — the suite
    grows to thousands, 1% becomes a per-story suite, and runtime creeps back up. The critical path
    is a roughly-fixed, product-shaped concept (auth, core create→read flow, the money path), not a
    function of test count.
  - **Floor 3 / ceiling 10.** At least ~3 critical-path journeys once a UI exists; **never more than
    10.** Reviewable by *counting* — no denominator. An absolute ceiling is self-limiting:
    per-story critical-path runtime stays bounded forever regardless of suite size.
  - Optional secondary guardrail only: a *% of UI tests* (never total) upper bound — the absolute
    ceiling will almost always bind first.
  - **Where the rule is documented:** in `standards/testing.md` — the single source of truth both
    skills cite (same pattern as the thread-A tier table), so neither skill carries its own drifting
    copy. It lands with the **broader v5 `testing.md` rewrite**, not piecemeal — unlike the #9
    anti-patterns (purely additive), this rule references the tier table and the not-yet-built
    `engineering-review-v5`, so it's entangled with the v5 skill work.
  - **How it's enforced (the mechanic):** the cap is only enforceable if "critical-path" is a **tag**.
    UI tests covering a critical journey get `[Trait("CriticalPath", "true")]` (same xUnit idiom as
    the existing `[Trait("Category","Playwright")]`), which makes the set **countable**
    (`dotnet test --filter "CriticalPath=true"` or a grep) — *that countability is exactly why
    floor/ceiling work and a percentage didn't: a count needs no denominator.*
    - `refine-story-v5` **declares** which of a story's journeys are critical (where the journey's
      importance is understood) → the `ui-test` author applies the tag.
    - `engineering-review-v5` **counts the repo-wide tagged set.** **Ceiling ≤10 is the hard gate**
      (REQUEST_CHANGES → demote the least-critical; bounds both bloat and per-story runtime). **Floor
      ≥3 is advisory** (can't force existential journeys onto a one-page app) — flag, don't block.
    - Don't have an agent infer criticality from nothing — it drifts; the declaration is human/refine
      input, the count is mechanical.

---

## Pipeline-shape changes (#1–#5) — closing the additive ratchet

The assessment's core thesis (§3) is that the pipeline only ever *adds* tests. Threads A and B fixed
where *new* tests go and *when* they run; these items close the gaps in the mechanism that stops
over-*production*.

- **#1 — Gating wording. RESOLVED.** "Integration on merge" can't gate (post-merge = already
  landed). Corrected in the trigger model above: integration is a **required pre-merge
  check**, branch must be **up to date with `main`** before merge. Merge queue only if traffic
  demands.
- **#2 — The subtractive step. RESOLVED.** Add a **redundancy / "lowest sufficient tier" check to
  `engineering-review-v5`** — reject a test when the *same behavior* is already covered at a
  *cheaper* tier, always cutting the **more expensive** duplicate. It needs no new skill or step:
  the orchestrator already runs `engineering-review` at all three test phases (Stage 3
  `implementation`, Stage 5 `integration-tests`, Stage 7 `ui-tests`), each with its own
  reject→fix loop. Pipeline ordering makes the check well-defined — by the time each review runs,
  the cheaper tiers have already merged to `main`, so each phase only asks "am I duplicating
  something cheaper that already exists?" (downward-only).
- **#3 — UI test *volume*. RESOLVED.** Collapse the heaviest tier with two levers. UI authoring is
  **skipped** when *either*: (1) the story changed **no user-facing surface** (orchestrator already
  detects this via `.razor` presence in Stage 2d), or (2) the surface is **declared out of scope for
  the UI tier** — tooling can't economically reach it (browser-extension content scripts, native OS
  dialogs, third-party iframes). Note on (2): frame it as a *declared scope decision*, **not** an
  "untestable" technical fact — e.g. Playwright *can* test Chrome extensions (persistent headed
  context, `--load-extension`, reachable MV3 service workers), it's just awkward/low-ROI. Declare it
  **per surface, not per project** — the guardrail against one untestable corner silently zeroing out
  all UI coverage (a normal Blazor page in the same project still gets tested). When UI authoring
  *does* run, it's **journey-scoped** — new/changed user journeys only, never a per-screen
  happy/edge/error matrix (that matrix belongs to unit/contract per the thread-A tier table).
- **#4 — Consolidation safety mechanism. DEFERRED (out of scope for going-forward v5).** Mutation
  testing (Stryker.NET) + coverage delta is a safety net for *bulk-deleting tests that already
  exist* — i.e. the paydown work, which is parked. Plain English: *coverage* = which code lines ran
  during tests (cheap, but running ≠ asserting); *mutation testing* = plant a bug, re-run tests, see
  if they catch it; *mutation score* = % of planted bugs caught (a real quality measure, but slow —
  re-runs the suite once per bug, hours). Going forward we are **not** deleting a backlog; we are
  *preventing over-creation* (right tier up front + the #2 reviewer rejecting a redundant test
  **before it merges**, justified by naming the cheaper test that already covers it). That stands on
  reviewer reasoning, **not** mutation scores. Mutation testing goes in the box labeled *"if/when we
  ever clean up the existing pile."* No Stryker, no coverage-delta gate in v5.
- **#5 — Smaller loose ends. RESOLVED.**
  - **(a) Pyramid ratio → end-of-run (CLEANUP mode), NOT per-ticket.** A single ticket has no
    meaningful ratio (a pure-logic ticket is all-unit, a migration all-integration) — forcing a
    per-ticket ratio is perverse. The ratio comes out right *emergently* if every ticket follows
    "cheapest sufficient tier" (tier table + #2). The ratio *number* is computed at the **end-of-run
    review** — this is the assessment's §7 #4 "periodic detector," now **run-completion-triggered**
    rather than clock-triggered (consistent with replacing nightly with the orchestration boundary).
    **Not just a report:** when the ratio crosses an **unfavorable threshold**, it **creates a tracked
    ticket on the project board** so the drift is *in someone's face*, not buried and unseen. See #6.
  - **(b) "Fix the code, not the test" → FIX-mode skills + review gate.** The rule lives in the
    FIX-mode instructions of `implement-ticket`, `integration-test`, `ui-test`, and especially
    `ci-fix` (the auto-fixer is most tempted to "make it green" by weakening a test).
    `engineering-review` enforces it: if a previously-failing test now passes because the *test*
    changed rather than the *code*, reject unless explicitly justified.
  - **(c) No fast project secretly needs Docker → standard line + self-enforcing.** The tier table
    states fast-tier projects must not reference Testcontainers/Docker; the per-PR fast job runs with
    **no Docker daemon**, so a violation fails CI loudly and immediately. Optional:
    `engineering-review` flags a Testcontainers import appearing in a fast-tier project.

---

## Architecture & execution (#6–#9)

- **#6 — Orchestration architecture: one mode-switching orchestrator + a dumb relaunch loop.
  RESOLVED.** Replaces the earlier "two orchestrators" / long-lived-overseer framing.

  **The problem (measured):** the current orchestrator is reliable for ~3 tickets but at **5–10
  tickets it starts forgetting workflow steps** — context degradation *within a run*. The constraints
  that ruled out the fancier designs (confirmed via Claude Code docs, 2026-06-18): **subagents cannot
  spawn subagents** (no 3-deep nesting → can't have overseer → per-ticket-orchestrator →
  stage-agents), and **an agent cannot clear its own context** mid-run. The supported way to get
  fresh context per unit of work is **process re-invocation** (a fresh `claude -p` session).

  **The design — ONE orchestrator skill that self-selects a mode from durable state on each launch:**
  - **WORKING mode** — Ready tickets exist → process up to **N** (config; default ~3, the measured
    reliability threshold), **checkpoint each ticket's state** to the board / tracking issue as it
    finishes, then **exit**. Because it's a fresh top-level session, it can still spawn its **stage
    subagents** (refine/implement/review/… — 1-level nesting, supported), so there's **no per-stage
    context rot inside a ticket** either.
  - **CLEANUP mode** — no Ready tickets → run the **end-of-run oversight**: full UI suite (thread B,
    via `workflow_dispatch` to the self-hosted runner, #8), **pyramid ratio** + **drift ticket** on
    unfavorable threshold (#5a), **gate audit** (did every ticket really pass review/security/tests),
    inject any resulting **fix tickets**, then exit.

  **The dumb relaunch loop** (bash; its only job is restart — all intelligence is in the
  orchestrator):
  - Relaunches the orchestrator until the run reaches a **fixpoint**: **no Ready tickets AND a CLEANUP
    pass that injected nothing new.** (CLEANUP injecting fix tickets → back to WORKING → re-verify;
    correct and non-infinite.)
  - At the fixpoint the orchestrator **marks the run complete** (durable flag/label/field on the
    tracking issue) **and emits a `RUN_COMPLETE` sentinel** on stdout; the loop checks the flag (or
    greps the sentinel) and **breaks.**
  - **Three dumb guards** (the only state the loop needs): `timeout` on each session (hang →
    kill+relaunch+recover), **relaunch-on-exit** (crash watchdog), **max-iterations cap** +
    circuit-breaker (runaway backstop → halt & flag a human).
  - **Mid-chunk crash recovery:** on startup the orchestrator resets any ticket left `In-progress` by
    a dead session back to Ready (or resumes it).

  **Limiter and loop are optional.** With the N-limiter off, one session runs **top-to-bottom** (small
  runs, no bash needed). With it on + the loop, it chunks. **Same single skill both ways** — no second
  process, no scheduler.

  **State** lives in the **project board** (ticket queue + status: Ready → In-progress → Done) and the
  **per-run tracking issue** (body = live current-state incl. ratio; comments = append-only event log;
  on the board; serves #5a "in someone's face").

  **One trade, named:** oversight is a *mode* of the same orchestrator, so it shares fate with it —
  there's no *independent* live observer beyond the loop's `timeout`+restart catching a hung/crashed
  session. The separate **concurrent overseer** (a second always-fresh watcher process) stays **on the
  shelf as the upgrade** if a true independent second set of eyes is ever wanted. Chosen "one
  artifact" over that independence — right for now.

- **#7 — `refine-story`: auto-reveal withheld considerations at the end. RESOLVED (keep it simple).**
  The current `refine-story` skill is good and **stays as-is** — this is one small addition, not a
  redesign. At the end of an **interactive** refinement, the skill should **automatically volunteer
  anything it considered but chose not to surface** — things it weighed and set aside, or thought the
  human might want to consider but didn't raise — *without the human having to ask for it.* Today the
  user prompts this manually almost every time (sometimes repeatedly, until it stops being
  productive); baking it in removes the manual ask. The human can still keep probing in conversation
  as needed.
  - **No taxonomy / structure** — don't over-engineer *what* it reveals (no assumptions/ambiguities/
    exclusions buckets); just surface the withheld considerations plainly.
  - **Autonomous / orchestrator mode (`ORCHESTRATOR_MODE = true`): do NOT do this.** Interactive-only
    — no self-review, no escalation, just skip.

- **#8 — Test execution model (was the deferred Docker problem). RESOLVED.** Tests **execute in CI on
  a self-hosted GitHub Actions runner**, not inside the YOLO orchestration container. The orchestrator
  (and the per-PR / per-merge gates) **trigger** runs via **`workflow_dispatch`** — a GitHub-side
  *trigger* (call the Actions API: "start this workflow"), distinct from the **runner
  agent**, the program that sits on the user's box polling GitHub *outbound* for jobs and executes
  them locally. Because the runner and the orchestration container are **decoupled** (separate
  network namespaces), Testcontainers/Playwright run as the runner box's *own* Docker workloads with
  normal host networking — the host-perspective `localhost` the tests assume — so the
  Docker-in-Docker / localhost problem **disappears.** Full loop: dispatch → GitHub queues
  for `runs-on: self-hosted` → runner agent grabs it, runs tests on the user's box → poll
  pass/fail → handle fallout.
  - **Self-hosted runners are free** (GitHub bills no minutes when you bring compute) — so use the
    runner for **builds and all test tiers**, not just UI. Likely faster than 2-core hosted runners
    (more cores, warm Docker cache, no cold start).
  - **Run the runner in WSL2/Linux** so SQL Server + Playwright Linux containers run cleanly.
  - **Persistent-runner hygiene:** a persistent runner doesn't get a fresh env per run — add clean
    steps or move to ephemeral runners later.
  - **Operational risk (user owns):** availability. (a) "forgot to start it" → **install the runner
    as a service** (auto-start on boot, restart on crash) — kills this failure mode now. (b)
    "computer is off" → **Azure on-demand runners** the user turns on — future option. (c) Security:
    self-hosted + untrusted PRs is a known risk but N/A here (private, first-party repos) — one line
    in the standard, not a blocker.
  - **Mechanics (mental model):** you never command the runner directly — the runner only executes
    **committed workflow files** (`.github/workflows/*.yml`). The only lever is "run *this*
    workflow with *these* inputs" (`gh workflow run …`) then poll results. Jobs run **directly on the
    Linux runner host** (not job-in-a-container); the test process uses the **host's Docker** to spin
    up SQL Server / browsers as **sibling** containers (prereq: runner's user can reach Docker).
    Self-test path: dispatch workflow with `echo` → `docker run --rm hello-world` → `dotnet test`.
  - **Concrete workflow set** (all `runs-on: self-hosted`): `fast-tests.yml` → on `pull_request`
    (per-PR gate); `integration-tests.yml` → required pre-merge check; `ui-tests.yml` → on
    `workflow_dispatch` — fired **two ways**: *scoped* (branch ref + filter input) for the per-story
    authoring run and critical-path smoke (thread B), and *unfiltered* for the end-of-batch full
    suite. Status confirmed working in a separate session (2026-06-18).

- **#9 — Fold UI-test anti-patterns into the standards. DONE (committed `de70473`).**
  `notes/ui-test-anti-patterns.md` (SDET-reviewed) had five rules; applied to `standards/testing.md`:
  - **General → new "Test Integrity" section** (applies to *all* tiers): **Silent failures** (every
    test must reach ≥1 assertion on every path; no exception-swallow / guard-and-bail /
    conditional-assert — a precondition that can't be met must *fail clearly*), **Asserting buggy
    behavior** (assert what the app *should* do, let it fail, **fix the bug not the test** — this is
    v5 #5b), **Skipping tests for known bugs** (no `Skip` — a failing test is visible, a skipped one
    is forgotten).
  - **UI-specific → folded into "Playwright Conventions":** **Hardcoded waits** banned in favor of
    condition-based waits (Instead-of/Use table); **Page Object Model** mandated (no inline locators).
  - **Still owed (separate, broader work):** `testing.md` still describes the *old* trigger model
    (UI/integration "gate every PR"), which **contradicts** the v5 trigger decisions above — it needs
    a broader v5 rewrite. The anti-patterns were **purely additive** and landed independently.

---

## Checklist enforcement (#10)

- **#10 — Checklist enforcement: TR rules + dual producer/reviewer sign-off. RESOLVED.** The v5 rules
  above are scattered in prose across six skills, which makes "enforce" (the third leg of
  *define → seed → enforce*) a vibe rather than a mechanic. #10 gives it a concrete form:
  consolidate the rules into one **numbered, ID'd checklist** that producers self-check and the
  reviewer independently re-checks. Observed motivation: sub-agents follow rules markedly better when
  handed an explicit checklist to *use* — not just told the rules in prose.

  **The canonical list — "Test Rules" (TR-*) in `standards/testing.md`.** One numbered block (under
  the tier table — the same single source both skills already cite). Stable IDs are the anti-drift
  glue: skills never restate a rule, they cite `TR-3`. Each rule is tagged **[CI]** (a job/branch
  protection catches it mechanically — the checklist just points at the job, doesn't re-derive) or
  **[JUDGMENT]** (needs reasoning — this is where the checklist carries the weight).

  | ID | Rule | Owner-producer(s) | Tag |
  |---|---|---|---|
  | TR-1 | Each behavior assigned exactly one tier (no multi-tier seeding) | refine | JUDGMENT |
  | TR-2 | No business logic in Contract tier | implement | JUDGMENT |
  | TR-3 | No contract re-assertion in Integration | integration-test | JUDGMENT |
  | TR-4 | UI journey-scoped, not a per-screen happy/edge/error matrix | ui-test | JUDGMENT |
  | TR-5 | UI conditional — skip when no surface or surface declared out-of-scope (per surface) | ui-test | JUDGMENT |
  | TR-6 | Critical-path tagged; floor 3 (advisory) / ceiling 10 (hard) | refine (declare) + ui (tag); **≤10 repo-wide count = reviewer-only** | CI (count) + JUDGMENT |
  | TR-7 | Fix the code, not the test | implement, integration, ui (+ ci-fix) | JUDGMENT |
  | TR-8 | No silent failures / no asserting buggy behavior / no `Skip` | implement, integration, ui | CI (`Skip`/waits) + JUDGMENT |
  | TR-9 | POM + condition-based waits (no hardcoded waits, no inline locators) | ui-test | CI (grep) + JUDGMENT |
  | TR-10 | Redundancy / lowest sufficient tier (cut the more expensive duplicate, downward-only) | **reviewer-only** | JUDGMENT |
  | TR-11 | No Testcontainers/Docker in fast tier | implement | CI (no-daemon job) |

  **Two independent sign-offs per applicable row — a grid on the ticket.** The deliverable is a small
  table: TR rows down the side, an **implementer/producer column** and a **reviewer column**, each
  cell a PASS/FAIL **with evidence** (a line reference or pasted command output), never a bare check —
  the evidence requirement is the teeth that stops rubber-stamping.

  - **Decision: who gets the checklist → both, differentiated** (not identical). Producers self-check
    *constructively* before declaring done ("I assigned each behavior one tier; here's the table");
    the reviewer re-checks *adversarially* ("find a behavior tested at two tiers and cut the
    expensive one"). Identical lists were rejected — the reviewer would just re-tick the producer's
    boxes and the second pass would be worthless.
  - **Decision: enforcement form → emit a filled-in checklist with evidence** (not reference-only). A
    referenced checklist gets skimmed; requiring it as an output artifact forces per-item engagement
    and produces a durable record.

  **Not every row has both boxes.**
  - A producer only ticks rows it **owns** (the implementer never sees TR-3 or TR-10). The producer
    columns are sparse.
  - The **reviewer column is the one constant** — present on every applicable row.
  - Some rules are **reviewer-only** because no single producer has the vantage to judge them at the
    moment it works: **TR-10** (redundancy) needs a *cross-tier* view — each producer runs from fresh
    context seeing only its own tier, so it structurally can't tell its test duplicates a cheaper one;
    the reviewer can, because by the time it runs the cheaper tiers have already merged to `main`
    (the downward-only property). **TR-6's ≤10** needs a *repo-wide* count spanning all UI tests, not
    just this ticket's — also reviewer-only. (TR-6 is a hybrid: the producer ticks "I tagged this
    story's critical journeys"; the ceiling cell is the reviewer's.)
  - **General principle:** a rule is producer-checkable only when the producer has the context to
    judge it at the moment it works; rules needing a vantage no single producer has (cross-tier,
    repo-wide) fall to the reviewer alone.

  **[CI] vs [JUDGMENT] split.** Anything greppable/countable is more reliably caught by CI than by an
  agent self-attesting, so the checklist *defers* to CI on those — the cell links the job rather than
  re-deriving. The checklist's real job is the [JUDGMENT] calls (TR-2, TR-3, TR-4, TR-10). A reviewer
  FAIL on any [JUDGMENT] item → REQUEST_CHANGES, bounced back to whichever skill owns that row.

  **Reviewer runs are mode-scoped.** `engineering-review-v5` emits only the rows relevant to the stage
  it's reviewing (implementation run → TR-2/7/8/11; integration run → TR-3/7/8; ui run →
  TR-4/5/6/7/8/9), with **TR-10 on every run** (redundancy can appear at any tier).

  **Bonus — feeds the CLEANUP gate-audit (#6).** Because producer checklists land in the issue
  comment / PR body and the reviewer checklist is the review comment, both are durable artifacts. The
  orchestrator's CLEANUP-mode gate-audit can then verify "did every ticket's review actually post a
  filled-in checklist," giving the audit something concrete to confirm instead of vibes.

  **Open call (not yet decided):** whether the grid is **one block per ticket** (refine/implement/
  integration/ui append to the same table as the ticket moves through stages) or **one grid per
  stage's PR**. Since v5 splits work across three PRs, current lean is **per-stage grids** the
  reviewer fills at each stage — flagged here, not locked.

---

## Deferred / shelved

- **Concurrent overseer** — a second always-fresh watcher process for *independent* live oversight.
  Shelved as the upgrade to #6 if a true second set of eyes is ever wanted.
- **#4 mutation testing (Stryker.NET) + coverage delta** — paydown safety tool; out of scope for
  going-forward v5 (see #4).
- **Running tests from inside the YOLO Docker container** — resolved by #8 (decouple execution onto a
  self-hosted runner); no longer a blocker.
- **Batch blame / attribution** — explicitly not a concern (oversight runs at the end; the fix is
  what matters).
- **Nightly "heartbeat"** — dropped; not a concern.
