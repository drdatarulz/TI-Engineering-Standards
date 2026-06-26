# v5 Round-Out Plan

> **Purpose:** finish the v5 skill suite. The initial v5 build
> ([`v5-implementation-plan.md`](v5-implementation-plan.md) + [`v5-changes.md`](v5-changes.md))
> rebuilt the **eight pipeline skills** to the four-tier + TR model. This plan covers the
> **six remaining v4-only skills** — giving each a v5 that inherits the established v5 "ways"
> plus one new cross-cutting pattern (the three-part proactive contribution step).
> **Created:** 2026-06-26. **Status:** LOCKED — ready to execute (decisions resolved; build all at once).
> **Principle (carried over):** **define → seed → enforce**, single source of truth in
> `standards/testing.md`, cite TR by ID, never restate.

---

## Skills needing a v5

| Skill | Type | v5 effort |
|---|---|---|
| `add-story-v5` | additive / interactive (writes tickets) | Medium |
| `prd-to-backlog-v5` | additive / batch (writes tickets) | Medium |
| `triage-v5` | interactive / diagnostic (writes tickets) | Medium |
| `reconcile-backlog-v5` | orchestrates add-story + refine | Low (re-point + inherit) |
| `conformance-v5` | read-only audit | High (audit the new testing standard) |
| `security-review-v5` | reviewer | Low / TBD (orthogonal to testing overhaul) |

`monitor-v5` is already v5-native (no v4 origin). The other eight pipeline skills are done.

---

## Cross-cutting v5 patterns to apply

### 0. Grounded + adversarial discipline (confirm, don't guess; falsify, don't rubber-stamp)
The observed failure mode of Opus 4.8 in this dev process: it **reasons forward from a plausible
model and asserts it without confirming** — sending real effort down confident-but-wrong paths.
Two distinct, paired mechanisms; they fail together, so we bake in both:

- **Pattern G — Grounded claims.** Any factual claim about how the code behaves (what a
  type/payload contains, what an endpoint returns, what an effect is keyed on, where a value flows)
  must be traced to an **observed source location (`file:line`)** before it's written as fact.
  Unverified = labeled a **hypothesis** ("assumed; not yet traced to source"), never shipped as
  established. Generalizes triage's hypothesis-vs-conclusion guard (#4) beyond runtime errors.
- **Pattern D — Adversarial self-review.** A mandatory step that treats your **own just-produced**
  spec/ticket as a suspect to cross-examine, not a product to defend. Re-trace every asserted data
  flow / type / contract to source and try to **prove it wrong**. Reframes the existing
  confirmatory gap-analysis ("review for gaps") into a falsifying one ("attempt to break each
  claim I just made").

Why both: the **adversarial posture decides *what* to re-check; the grounding standard decides
*whether it's true*.** Adversarial-without-grounding "corrects" right things into wrong ones;
grounded-without-adversarial never doubts the confident-but-wrong claims (the ones that *feel*
obviously right — exactly the class that slips through).

Pipeline: **ground → adversarially attack → surface (the three-part contribution step) → escalate
genuine forks.**

Specifics to capture in each skill:
- **Scope-fork detection** — does the chosen approach secretly change blast radius or which test
  tiers apply? (From the real example: a "frontend-only" fix whose option (c) re-introduced the
  .NET tiers the ticket said didn't apply.)
- **Headless behavior** — G and D need source access, not a human, so they run **always**
  (including `ORCHESTRATOR_MODE`). Only the *escalation of a genuine scope-fork* is gated: headless,
  default to the **smallest-scope** option **and** record the fork as a flag/follow-up — never
  silently pick the big one.

Motivating example (real interaction, current refine-story-v5): the first refine pass asserted a
`overallGrade` data flow ("App captures it from `handleGenerateComplete`") it never traced to the
type — the POST `RiskAssessmentResponse` doesn't carry that field; it only exists on the GET
response. A second, *adversarial* pass grepped the type and collapsed the theory in ~2 minutes.
**This means refine-story-v5 has the gap today** — see Open Decision #2 (patch refine, don't exempt it).

### 1. Three-part proactive contribution step  ← the new headline pattern
At a standing, near-final checkpoint, **Claude volunteers its own input on the ticket
automatically** — because that's the question the team always asks Claude when writing a
ticket. Three forward-looking parts:

- **What we missed** — gaps Claude sees in the ticket
- **What we should consider** — angles, options, risks worth raising
- **What I'd add** — Claude's own recommendations to strengthen it

Plus a fourth flavor, kept from refine's existing section: **what was considered and discarded**.

Rules of the step:
- Plain prose, **no taxonomy buckets**. Surfaced **without being asked**, every ticket.
- Runs **just before** the ticket is finalized / written to GitHub.
- **Skipped in `ORCHESTRATOR_MODE` / headless** (no human in the loop).
- Applies to all ticket-producers: `add-story`, `prd-to-backlog`, `triage`, `reconcile-backlog`.
- **Backport [DECISION PENDING]:** refine-story-v5 currently has only the narrow "auto-reveal
  discarded" version (lines 203–207). Upgrade it to the fuller three-part version for consistency,
  even though we agreed not to otherwise touch the existing v5 skills?

### 2. Four-tier test vocabulary, cite TR by ID, never restate
Drop the old 3-row `Unit / Integration / UI — Yes/N-A` template the v4 ticket-writers carry.
Reference `standards/testing.md` and `TR-n` by ID only.

### 3. Single owner for the behavior→tier table
`refine-story-v5` owns the enforced behavior-first table (TR-1) + critical-path declaration
(TR-6). Ticket-creators emit a **coarse one-line test intent** and **defer** the real table
to refine. No duplication, no drift.

### 4. `gh ... --limit 1000` guard
Every board/issue listing — `gh` defaults to 30 and silently drops the newest items
(e.g. a just-injected ticket sorts last). Same lesson already baked into orchestrate-v5.

### 5. Non-interactive / `ORCHESTRATOR_MODE` path
Where another skill or the orchestrator invokes headlessly (reconcile calls add-story;
the orchestrator may inject follow-ups), support a non-interactive path with best-judgment defaults.

---

## Per-skill scope

- **triage-v5** — three-part contribution as the closing step before ticket write; tag bugs on
  auth/money/critical journeys for TR-6; four-tier vocab; `--limit` guard. Stays "never writes code."
  **Plus evidence-first runtime diagnosis (see #4 below).**
- **add-story-v5** — contribution step; defer tier table to refine; **callable non-interactive
  mode** (reconcile + orchestrator follow-ups); `--limit` guard.
- **prd-to-backlog-v5** — contribution step on the decomposition; **nominate the repo-wide
  critical-path journeys** (ceiling 10) at backlog level so refine/ui-test draw from a budgeted
  pool; `--limit` guard.
- **reconcile-backlog-v5** — re-point Phase 5 to `add-story-v5` / `refine-story-v5`; contribution
  step on classifications; `--limit` guard. Mostly inherits.
- **conformance-v5** — audit the **new** testing standard: Contract tier exists & uses
  WebApplicationFactory (TR-2 no-logic), inverted-pyramid / redundancy (TR-10), critical-path
  count ≤ 10 / ≥ 3 (TR-6), no `Skip` / silent failures (TR-8), POM + condition-based waits (TR-9),
  no Docker in fast tier (TR-11); audit CI tiering (`fast`/`integration`/`ui` workflows) and
  orchestration vendoring (`scripts/orchestrate.sh`). Read-only; no contribution step.
- **security-review-v5** — TBD. Light align (`--limit`, tracking-issue / event-log vocabulary,
  fail-open / silent-provider-error overlap that engineering-review-v5 added) vs leave at v4.

---

## Decisions (LOCKED)
1. **Patch existing v5 skills, don't just add.** The original "only add new v5 skills, don't touch
   existing ones" rule is **superseded** — these things evolve, and the grounded+adversarial gap is
   literally in `refine-story-v5` today. We **patch** where the standard has moved on. (Kevin, 2026-06-26.)
2. **`refine-story-v5` gets patched** for Patterns G + D, and its narrow auto-reveal is upgraded to
   the fuller three-part contribution step. It's the skill where the miss happened; it leads, not exempt.
3. **security-review** → make `security-review-v5` (light v5 align: `--limit` guard, tracking-issue /
   event-log vocabulary, fail-open / silent-provider-error overlap). Part of "do them all."
4. **Build order doesn't matter — build all at once.** Each new `-v5` scaffolds as a verbatim copy of
   its v4 origin first (so each per-skill edit diffs cleanly against v4), per the original v5 build
   convention. refine-story-v5 is patched in place against its current state.
5. **Grounded + adversarial is encoded as a STANDARD, not just skill behavior.** Memory does not
   propagate (it's local to one repo path / machine / instance); the standards repo + skills do, via
   auto-sync. So Pattern 0 lives in a source-of-truth standards file and the skills **cite it by ID**
   — the same `define → seed → enforce` shape as the TR rules. Without this, "every instance gets the
   habit on v5 upgrade" doesn't actually hold. (Kevin, 2026-06-26.)

## Foundational work item — the propagation backbone (do FIRST)
Encode Pattern 0 as a standard so it reaches every project/instance from source:
- **New `standards/engineering-discipline.md`** — universal working discipline, citeable rule IDs
  mirroring `TR-n`:
  - **ED-1 — Grounded claims.** Trace any factual claim about code behavior to an observed
    `file:line` before writing it as fact; unverified = labeled hypothesis.
  - **ED-2 — Adversarial self-review.** Treat your own just-produced output as a suspect; try to
    falsify each claim before finalizing.
  - **ED-3 — Hypothesis vs. conclusion labeling.** A claim without grounding evidence is written as
    a hypothesis with "evidence needed: …", never as established fact.
  - **ED-4 — Scope-fork detection.** Check whether the chosen approach silently changes blast radius
    or which test tiers apply; surface the fork instead of hiding it.
- **Index it in `CLAUDE.md`** Standards Index table + a short "How To Work (Universal)" block for
  salience.
- v5 skills **cite `ED-1`/`ED-2`/etc. by ID** (never restate). The plan's "Patterns G/D" are the
  skill-side application of `ED-1`/`ED-2`.
- The local memory entry (`grounded-and-adversarial`) stays as a personal stopgap, but the **standard
  is the source of truth**.

## Still to confirm (non-blocking)
- **Patterns G + D on the *other* existing v5 skills** (`implement-ticket-v5`, `engineering-review-v5`).
  Recommended yes (the discipline is universal; engineering-review already has partial adversarial DNA
  via the phantom-AC check) — but it expands blast radius beyond the six + refine. **Not auto-included;**
  confirm before touching impl/review so we don't quietly balloon scope.

## Build footprint (what will change when we execute)
- **Foundational (first):** new `standards/engineering-discipline.md` (ED-1..ED-4) + `CLAUDE.md`
  Standards-Index entry and "How To Work (Universal)" block.
- New skill dirs (scaffold-from-v4 then edit): `add-story-v5`, `prd-to-backlog-v5`, `triage-v5`,
  `reconcile-backlog-v5`, `conformance-v5`, `security-review-v5`.
- Patched in place: `refine-story-v5`.
- `CLAUDE.md` skills-table re-point once each lands.

**This plan doc is the only change so far.**

---

### Triage-only pattern: evidence-first runtime diagnosis  (the #4 bake-in)

From a real triage miss (issue #3): a separate triage instance reasoned **forward from the
symptom** ("reports fail → must be missing blob storage") and landed on a confident-but-wrong
root cause that would have sent someone to "fix" already-correct bicep. The actual stack trace
was sitting in Log Analytics the whole time — pulling it collapsed the theory in ~2 minutes and
pointed straight at `MigraDocReportPdfRenderer:35`. The bug in the render path sat untouched
while effort was aimed at correct infrastructure.

Principle: **for a runtime failure, the cheapest disambiguating move is to retrieve the real
exception before theorizing about infrastructure** — reason *backward from the error*, not
*forward from the symptom*. (Same "lowest sufficient" instinct as the testing model, applied to
diagnosis: a stack trace is near-free and decisive; an infra theory is expensive and speculative.)

Bake into `triage-v5` as three concrete pieces:

1. **Evidence-first investigation order.** When the symptom is a runtime failure (5xx, crash,
   unhandled exception, worker dying), the FIRST move is to pull the actual exception + stack
   trace from the **dev environment's runtime logs** — before any infrastructure hypothesis.
   Add to the investigation toolkit: query Log Analytics / container-app logs
   (`az containerapp logs show`, `az monitor log-analytics query`), not just local `docker logs`.

2. **Attempt-and-surface, don't theorize past a gap.** Triage *attempts* to pull running logs;
   if it can't (no creds/access, env down), it says so explicitly and marks the root cause
   **unconfirmed** — it does NOT silently skip the log and reason forward anyway. Missing
   evidence becomes a stated gap, not an invisible assumption. ("the ability, or at least the attempt")

3. **Hypothesis vs. conclusion guard.** A root cause for a runtime error may be written as
   *established* only if backed by an actual error line / stack trace; otherwise it is tagged a
   **hypothesis** with "evidence needed: pull `<log>`". Analogous to engineering-review-v5's
   phantom-acceptance-criteria check — stops a confident-but-wrong root cause from reaching the
   ticket as fact.

Dovetails with the three-part contribution step: "what we missed" naturally surfaces
*"I theorized X but couldn't confirm — grab the exception at `<path>` first."*

---

## Observations integrated
All three of Kevin's observations are folded in:
1. The three-part proactive contribution step (Pattern 1).
2. Evidence-first runtime diagnosis for triage (the #4 bake-in).
3. Grounded + adversarial discipline (Pattern 0, Patterns G + D).
