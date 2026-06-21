# v5 Implementation Plan

> **Purpose:** the execution sequence for building v5. The *what/why* lives in
> [`notes/v5-changes.md`](v5-changes.md) (the spec); this is the *how/when* (the build order).
> **Created:** 2026-06-19. **Status:** ready to execute.
> **Principle:** **define → seed → enforce** — the standard defines a rule, `refine-story-v5` seeds
> it, `engineering-review-v5` enforces it. So we build **standards → CI substrate → skills →
> orchestration**, each layer testable before the next.

---

## Start here when you're back

1. Skim **Phase 0** and answer the four decision gates (5 min) — they unblock everything.
2. Then execute **Phase 1** (the `standards/testing.md` v5 rewrite) — already in progress when we
   paused; it's the keystone and low-risk.
3. Proceed down the phases in order.

**Already done:** #9 UI-test anti-patterns are live in `standards/testing.md` (commit `de70473`).
**Deferred (do NOT build):** #4 mutation testing (paydown only); the concurrent overseer (upgrade to #6).

---

## Phase 0 — Decision gates (lock before building)

These are quick calls that shape later phases. Recommendation given for each.
**Resolved 2026-06-21:** all four gates decided. Phase 0 complete.

- [x] **G1 — Skill strategy: copy `v4 → v5` vs. edit in place. → COPY-TO-`-v5`.** Mirrors the existing
  v1–v4 archive pattern; clean version boundary; v4 keeps running while v5 is built. Trade accepted:
  more files to maintain. Governs all of Phase 3.
- [x] **G2 — Pilot project. → DECIDED (user-owned).** Pilot repo selected; the user handles v5
  integration there in a separate instance. The Phase 1/3 standards-and-skills work is **repo-agnostic**,
  so the build here doesn't depend on the pilot's identity.
- [x] **G3 — Tier names. → CONFIRMED: Unit / Contract / Integration / UI**, "Contract" locked
  (over "Component"). The four-tier model stands as specced.
  - **Documentation directive (2026-06-21):** when `testing.md` / the tier table is written, document
    Contract as the **no-infra sibling of Integration**, not a wholly separate tier. Both run the
    endpoint inside the real .NET host (`WebApplicationFactory`) — same host machinery; the *only*
    difference is fakes (Contract, contract-only, no Docker — "nothing special needed") vs. the real
    database (Integration). Use this to explain *why* Contract is fast: integration-style wiring tests
    with the slow dependency faked out.
- [x] **G4 — CriticalPath trait. → `[Trait("CriticalPath", "true")]`.** Same idiom as
  `[Trait("Category","Playwright")]`; makes the set countable via `--filter`/grep (the reason
  floor/ceiling work without a denominator).

---

## Phase 1 — Standards foundation  *(keystone; low-risk doc work)*

**Goal:** `standards/testing.md` becomes the v5 source of truth; kill the live contradiction (it
still says UI/integration "gate every PR").

- [ ] **1.1 — Add a "Test Tiers" section** (thread A): the tier table (Unit / Contract / Integration /
  UI — *owns* / *never put here*), with the governing rule above it: *"test each behavior once, at the
  cheapest tier that can catch its failure mode."*
- [ ] **1.2 — Add the precise prohibition:** *"do not exercise business logic through the HTTP/fakes
  host — the Contract tier asserts the contract only."* (Plus optional one-line pointer from
  `CLAUDE.md` "Things NOT To Do.")
- [ ] **1.3 — Rewrite "When to Write Tests"** so endpoints don't mandate **both** unit *and*
  integration. Logic → unit; contract/seam → Contract tier; real-infra behavior → integration.
- [ ] **1.4 — Rewrite "CI/CD Testing Tiers"** to the v5 trigger model: fast tier → every PR;
  integration → **required pre-merge check** (branch up to date); UI → **orchestration boundary via
  `workflow_dispatch`**, *not* a per-PR gate; all on the **self-hosted runner**. Remove "Playwright
  gates every PR."
- [ ] **1.5 — Add the critical-path UI rule** to Playwright Conventions: floor 3 / ceiling 10,
  `[Trait("CriticalPath","true")]`, ceiling = hard cap, floor = advisory; declared at refine, counted
  at review.
- [ ] **1.6 — Add the "no-Docker fast tier" line** (#5c): fast-tier projects must not reference
  Testcontainers/Docker; the per-PR fast job runs with no Docker daemon.
- [ ] **1.6a — Add the "Test Rules" (TR-*) checklist** (#10): one numbered, ID'd block under the tier
  table (TR-1…TR-11), each tagged **[CI]** or **[JUDGMENT]**, with the owner-producer(s) and which
  rows are **reviewer-only** (TR-10, TR-6 ceiling). This is the single source both producer and
  reviewer skills cite by ID — it must land before Phase 3.
- [ ] **1.7 — Sweep sibling standards** for contradictions with the new trigger/tier model
  (`api-integration.md`, `architecture.md`, `environments.md`); fix references.
- [ ] **Deliverable:** updated `standards/testing.md` (+ any sibling tweaks); commit. **Review gate:**
  read the diff end-to-end before moving on.

---

## Phase 2 — CI / execution substrate  *(#8 / #1; runner already proven)*

**Goal:** make the trigger model real on the pilot repo; independently testable without skill changes.

- [ ] **2.1 — Author the three workflows** (all `runs-on: self-hosted`):
  - `fast-tests.yml` → on `pull_request` (Domain + Contract/fakes projects; no Docker).
  - `integration-tests.yml` → required pre-merge check (Testcontainers).
  - `ui-tests.yml` → on `workflow_dispatch`, accepting **inputs**: `ref` (branch) + `filter`
    (scoped per-story run) — also runnable unfiltered (full boundary run).
- [ ] **2.2 — Confirm the no-Docker fast job** genuinely has no Docker daemon, so a stray
  Testcontainers reference fails loudly (validates 1.6).
- [ ] **2.3 — Branch protection on the pilot repo:** `integration-tests` (and `fast-tests`) required
  to merge; **require branch up to date with `main`**. Merge queue only if traffic demands.
- [ ] **2.4 — Self-test the runner path:** dispatch a workflow `echo` → `docker run --rm hello-world`
  → a real `dotnet test` (the path you already proved).
- [ ] **Deliverable:** three workflows committed to the pilot repo + branch-protection configured.

---

## Phase 3 — v5 skills  *(define → seed → enforce; depends on Phase 1, G1)*

Apply G1 (copy vs. edit). Each skill cites `standards/testing.md` rather than re-stating rules.
**Checklist (#10) threads through every skill below:** each producer **emits its owned TR rows**
(PASS/FAIL + evidence) before declaring done; the reviewer emits the **full mode-scoped grid**.

- [ ] **3.1 — `refine-story-v5`:** assign each behavior a **single tier** up front (no multi-tier
  seeding); **declare critical-path** journeys; **#7** auto-reveal withheld considerations at the end
  (interactive mode only). **#10:** emit producer rows TR-1, TR-6 (tagging declaration).
- [ ] **3.2 — `implement-ticket-v5`:** unit + Contract tests per the tier table (no business logic in
  Contract); **FIX-mode** carries "fix the code, not the test." **#10:** emit producer rows
  TR-2, TR-7, TR-8, TR-11.
- [ ] **3.3 — `integration-test-v5`:** real-infra behavior **only** (no contract re-assertion);
  FIX-mode fix-code-not-test rule. **#10:** emit producer rows TR-3, TR-7, TR-8.
- [ ] **3.4 — `ui-test-v5`:** **journey-scoped**; **conditional** (skip when no UI surface or surface
  declared out-of-scope, per-surface); per-story run = **scoped `workflow_dispatch`** to the runner
  (#8); tag critical-path tests; obey the #9 anti-patterns (POM, condition-waits, no silent fails,
  no skips). **#10:** emit producer rows TR-4, TR-5, TR-6 (tag), TR-7, TR-8, TR-9.
- [ ] **3.5 — `engineering-review-v5`:** **two-way** (flags *missing* AND *redundant* coverage, #2);
  **tier-boundary** checks (business logic out of Contract, contract out of Integration);
  **critical-path count** (ceiling ≤10 hard, floor ≥3 advisory); **fix-code-not-test** gate (reject a
  test edited to mask a bug); **anti-pattern** flags. Runs in all three modes (implementation,
  integration-tests, ui-tests). **#10:** emit the **full mode-scoped reviewer grid** (impl → TR-2/7/8/11;
  integration → TR-3/7/8; ui → TR-4/5/6/7/8/9; **TR-10 every run**), each cell PASS/FAIL + evidence;
  [CI] cells link the job rather than re-deriving; any [JUDGMENT] FAIL → REQUEST_CHANGES back to the
  owning skill.
- [ ] **3.6 — `ci-fix-v5`:** carry the fix-code-not-test rule (most tempted to "make it green").
- [ ] **3.7 — Update `CLAUDE.md`** standards index + skills table to v5; archive v4 per G1.
- [ ] **Deliverable:** `-v5` skills + updated `CLAUDE.md`.

---

## Phase 4 — Orchestration architecture  *(#6; depends on Phase 3)*

**Goal:** one mode-switching orchestrator + a dumb relaunch loop; no second process, no scheduler.

- [ ] **4.1 — `orchestrate-v5` mode switch:** read durable state on launch → **WORKING** (process up
  to **N**, default ~3; checkpoint each ticket; exit) or **CLEANUP** (no Ready tickets → end-of-run
  oversight; exit).
- [ ] **4.2 — State machine** on the project board + per-run tracking issue: Ready → In-progress →
  Done; tracking-issue **body = live state**, **comments = event log**; startup **crash recovery**
  (reset stale In-progress → Ready).
- [ ] **4.3 — CLEANUP mode:** full UI suite (unfiltered runner dispatch) → **pyramid ratio + drift
  ticket** (#5a) → **gate audit** (incl. **#10:** confirm each ticket's review posted a filled-in
  reviewer checklist grid — concrete artifact, not vibes) → inject fix tickets. Reaches **fixpoint** =
  no Ready tickets AND CLEANUP injected nothing → mark run complete + emit `RUN_COMPLETE`.
- [ ] **4.4 — The dumb bash driver loop:** relaunch until `RUN_COMPLETE` (or tracking-issue flag);
  guards = `timeout` per session, relaunch-on-exit, **max-iterations cap** + circuit-breaker.
  Limiter/loop **optional** (small runs go top-to-bottom, no bash).
- [ ] **Deliverable:** `orchestrate-v5` skill + driver script.

---

## Phase 5 — Pilot & validate

- [ ] **5.1 —** Run v5 end-to-end on the pilot repo with a small batch (3–5 tickets).
- [ ] **5.2 — Verify:** fast/PR + integration/pre-merge gates fire; tier boundaries enforced; UI runs
  on the runner (scoped per-story + full at boundary); loop chunks at N and relaunches; CLEANUP fires
  ratio/drift/gate-audit; crash recovery works.
- [ ] **5.3 — Tune N** to the observed reliability threshold.
- [ ] **5.4 —** Capture lessons; only then consider rolling v5 to other repos.

---

## Phase 6 — Process documentation, diagrams & templates  *(after pilot; docs describe what shipped)*

**Goal:** bring the *process-documentation layer* in line with v5. This layer is heavily v4-coded and
will **directly contradict** the new model until updated (e.g. the master doc still says "Playwright
runs in CI on every PR"). Sequenced **after Phase 5** so docs describe what actually shipped, not what
was planned. Apply **G1** (copy-to-`-v5` vs. edit in place) per artifact.

- [ ] **6.1 — `workflow/agentic-development-workflow.md`** (master process doc): rewrite to the v5
  model — four-tier testing (Unit/Contract/Integration/UI), the **trigger model** (fast/PR,
  integration/required-pre-merge, UI at orchestration boundary via `workflow_dispatch`),
  **self-hosted runner** execution (#8), the **mode-switching orchestrator + dumb loop** (#6, replaces
  the v4 supervisor/worker description), and the **TR checklist** dual sign-off (#10). Remove
  "Playwright gates every PR" and Docker-required-locally framing.
- [ ] **6.2 — `workflow/workflow-diagram.html`**: regenerate for the v5 pipeline (currently labeled
  "v4 pipeline"). **Note:** hand-built HTML — regeneration is real work, not a tweak. G1 call:
  new `workflow-diagram-v5.html` vs. edit in place.
- [ ] **6.3 — `workflow/README.md`**: update the stage list, drop the "v4 pipeline" labels, point at
  the v5 diagram, refresh `-v4`→`-v5` skill names.
- [ ] **6.4 — `workflow/screen-inventory-template.md`**: add the **per-surface UI-scope decision**
  (#3 / TR-5) — record per surface whether it's in/out of UI-tier scope.
- [ ] **6.5 — `templates/CLAUDE-project.md`**: update test-run patterns to the four tiers + trigger
  model; add the Contract tier; reference the TR checklist; refresh skill names per G1.
- [ ] **6.6 — `developer-tools/`**: document the **self-hosted runner** setup (#8 — install-as-service,
  WSL2/Linux, Docker access, persistent-runner hygiene) — likely a new doc alongside the existing
  hooks/VM-scripts.
- [ ] **6.7 — Index `workflow/` in `CLAUDE.md`** — the folder is currently **not referenced** in the
  standards index, which is exactly why it's easy to forget. Add it (and `templates/`,
  `developer-tools/` if not present).
- [ ] **Deliverable:** v5 process docs + diagram + templates; `CLAUDE.md` indexes the workflow layer.

---

## Cross-cutting / housekeeping

- [ ] Retire `notes/ui-test-anti-patterns.md` (now folded into the standard) — or keep for the SDET
  review history. Your call.
- [ ] Once v5 is proven, update the standards-repo `CLAUDE.md` skills table and move v4 skills to
  `skills/archive/` (per G1).
- [ ] Keep `v5-changes.md` and this plan in sync if decisions change mid-build.

---

## Dependency map (quick reference)

```
Phase 0 (decisions)
        │
        ▼
Phase 1 (standards) ──► Phase 3 (skills) ──► Phase 4 (orchestration) ──► Phase 5 (pilot) ──► Phase 6 (docs)
        │                    ▲
        ▼                    │
Phase 2 (CI substrate) ──────┘   (skills trigger the workflows)
```

Phases 1 and 2 can run in parallel; both must land before Phase 3. Phase 6 (process docs, diagram,
templates) comes **last** so it documents what actually shipped, not what was planned.
