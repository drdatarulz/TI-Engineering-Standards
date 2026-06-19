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

- [ ] **G1 — Skill strategy: copy `v4 → v5` vs. edit in place.** *Recommend copy-to-`-v5`* (mirrors
  the existing v1–v4 archive pattern; clean version boundary; v4 keeps running while v5 is built).
  Trade: more files to maintain. Decide once; it governs all of Phase 3.
- [ ] **G2 — Pilot project.** Which repo do we roll v5 on first (FormIt, or another)? The note's
  philosophy is *pilot, don't global-sweep.* Everything in Phases 2–5 lands in the pilot first.
- [ ] **G3 — Contract tier name.** Spec uses **"Contract"** (the `WebApplicationFactory`-over-fakes
  tier). Confirm vs. "Component." *Recommend "Contract."* Affects the tier table wording.
- [ ] **G4 — CriticalPath trait.** Confirm `[Trait("CriticalPath", "true")]` as the tag that makes
  the critical-path set countable. *Recommend yes* (same idiom as `[Trait("Category","Playwright")]`).

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

- [ ] **3.1 — `refine-story-v5`:** assign each behavior a **single tier** up front (no multi-tier
  seeding); **declare critical-path** journeys; **#7** auto-reveal withheld considerations at the end
  (interactive mode only).
- [ ] **3.2 — `implement-ticket-v5`:** unit + Contract tests per the tier table (no business logic in
  Contract); **FIX-mode** carries "fix the code, not the test."
- [ ] **3.3 — `integration-test-v5`:** real-infra behavior **only** (no contract re-assertion);
  FIX-mode fix-code-not-test rule.
- [ ] **3.4 — `ui-test-v5`:** **journey-scoped**; **conditional** (skip when no UI surface or surface
  declared out-of-scope, per-surface); per-story run = **scoped `workflow_dispatch`** to the runner
  (#8); tag critical-path tests; obey the #9 anti-patterns (POM, condition-waits, no silent fails,
  no skips).
- [ ] **3.5 — `engineering-review-v5`:** **two-way** (flags *missing* AND *redundant* coverage, #2);
  **tier-boundary** checks (business logic out of Contract, contract out of Integration);
  **critical-path count** (ceiling ≤10 hard, floor ≥3 advisory); **fix-code-not-test** gate (reject a
  test edited to mask a bug); **anti-pattern** flags. Runs in all three modes (implementation,
  integration-tests, ui-tests).
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
  ticket** (#5a) → **gate audit** → inject fix tickets. Reaches **fixpoint** = no Ready tickets AND
  CLEANUP injected nothing → mark run complete + emit `RUN_COMPLETE`.
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
Phase 1 (standards) ──► Phase 3 (skills) ──► Phase 4 (orchestration) ──► Phase 5 (pilot)
        │                    ▲
        ▼                    │
Phase 2 (CI substrate) ──────┘   (skills trigger the workflows)
```

Phases 1 and 2 can run in parallel; both must land before Phase 3.
