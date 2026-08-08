# Parallel Orchestration Plan

> **Purpose:** let **more than one orchestrator run at once inside a single repo**, so a batch of
> tickets finishes as fast as their dependencies allow instead of strictly one-at-a-time. A new
> **planner skill** turns a ticket list into a dependency graph + a shared ticket pool; you then
> launch as many orchestrators ("workers") as you like against it. The workers coordinate
> peer-to-peer through **one shared plan ticket** — no central dispatcher.
> **Created:** 2026-08-05. **Last updated:** 2026-08-05 (shared-pool model — lanes removed).
> **Status:** DRAFT — for discussion, not yet executed.
> **Principle:** compose N of the existing single-driver loops; don't multi-thread one. The
> coordination machinery is **inert without a plan ticket** — a plain `./scripts/orchestrate.sh`
> run behaves exactly as it does today.

---

## The idea in one paragraph

Today one orchestrator drives a repo: you give it a ticket scope and it runs it one at a time
(fresh-context relaunch per ticket). This plan lets **several orchestrators run against the same
repo at once**, each pulling work from a **shared pool** on the plan ticket. There are **no lanes
and no pre-assignment** — a worker wakes up, reads the pool, and takes the next ticket whose
dependencies are all satisfied and that nobody else has claimed. Correctness (what must run before
what) lives entirely in a flat **dependency graph**; workers just race for ready tickets and a
lightweight **claim handshake** stops two of them from grabbing the same one.

---

## Concepts

- **Plan ticket** — one GitHub issue (label `orchestration-plan`) that is the single **coordination
  surface** for a parallel run. Its **body** holds the static plan (the ticket pool + the
  dependency graph), written once by the planner. Its **comments** are the append-only coordination
  log — claims and completions. Everything a worker needs to decide "what do I do next?" is one
  fetch of this issue.
- **Dependency graph** — a flat, per-ticket edge list: `blocked → blockers`, where a ticket may
  have many blockers. This is the **only** carrier of correctness — a ticket runs only once *every*
  blocker is `✓ completed`. It knows nothing about workers or ordering beyond the edges.
- **Ticket pool** — the flat set of tickets in scope for the run. No partition, no lane. A ticket
  is **ready** when it is in the pool, not yet completed, unclaimed, and all its blockers are
  completed.
- **Worker** — one orchestrator instance with an id (`--worker w2`, or auto-generated if omitted —
  see Worker identity below). The id is an **ephemeral process identity** — it names *which
  orchestrator*, not *which work* (work is the shared pool). It keys the worker's lock, run log,
  and its own run-state tracking issue, and it stamps the worker's claims. Stable across that
  worker's relaunches; distinct between workers.
- **Claim handshake** — how a worker takes a ticket without another worker double-taking it. To
  take `#5`, a worker appends a claim comment stamped with its id; the **earliest** such claim wins
  the acquisition race (see below). Loser moves on; winner works it. The claim comment does **only
  this one job** — break the acquisition tie at the instant two workers grab the same ticket.
- **Ownership** — who is *currently* working a ticket. This lives in the winner's **run-state
  tracking issue** (`Current ticket: #5 @ stage n @token <claim-id>`), which the skill already
  maintains every stage — **not** in the claim comment. The `@token` is the winning claim's comment
  ID (monotonic); **ownership = the live worker holding the highest token for a ticket**, which is
  what lets a reclaim supersede and a falsely-reaped worker yield (see reaper). The split is
  deliberate: a claim comment lingers after the claimer has lost or died, so if ownership were read
  off claims a leftover could poison resolution later (a live loser's stale claim spuriously
  "re-winning" a reaper-reclaimed ticket). Because ongoing ownership is the tracking issue, a
  leftover claim comment is **inert by construction** — which is exactly what makes it safe to leave
  claims lying around and sweep them only at end-of-run.
- **Done-signal** — how "a dependency is satisfied" is known. When a worker takes a ticket through
  checkpoint, it appends `✓ completed #<id>` to the plan ticket, and **that record is the truth.**
  It matches the skill's own rule that "done" is a **written completion record, not an inferred
  status** (`orchestrate-v5/SKILL.md:231` — the completion record is authoritative, explicitly
  *not* board status). Why **not** "PR merged to main": a single v5 ticket produces *multiple* PRs
  (implement → integration → ui each open one), so a merge is an ambiguous, mid-pipeline event that
  fires before the ticket has passed checkpoint. Why a **comment**, not a body edit: many workers
  editing one body race (GitHub edits are last-write-wins, no locking); append-only comments don't.

---

## The claim handshake (the heart of it)

A shared pool means two workers can eye the same ticket at the same instant. Taking a ticket is a
handshake, resolved entirely through GitHub's own append-only, monotonically-ID'd comment stream —
no coordinator, no lock service. Three cheap layers make it safe: **spread the picks** so
collisions are rare, a **settle delay** so the resolving read is complete, and a **pre-dispatch
recheck** so the expensive path is double-guarded.

**Pick to avoid collisions (layer 1).** Do **not** have every worker grab the topmost ready ticket —
that makes N workers deterministically collide on the same one and burn N claim-rounds resolving it.
Each worker picks a **randomized (or worker-index-offset) ready ticket**, so claims rarely collide
at all and the handshake below becomes the rare safety net, not the common path.

**To claim `#5`:**
1. Append a claim comment to the plan ticket: `🔒 claim #5 · w2`.
2. **Wait a short jittered settle delay (~5-10s), then** re-read the plan ticket's claim comments
   for `#5`. The delay lets the claim stream propagate so the read is *complete* — see "Why the
   delay" below.
3. **The earliest claim wins the acquisition.** "Earliest" = **lowest comment ID** (GitHub comment
   IDs are monotonic and unique — no nonce needed). Ignore claims by a worker whose tracking issue
   is stale (dead — see reaper).
4. If my claim is the earliest → **I won**: edit my claim comment to flag it `taken` (`🔒 claim #5 ·
   w2 · taken`), and set `Current ticket: #5 @token <my claim's comment ID>` in my tracking issue —
   **that** is now the ownership record. If not → **I lost**: just go pick another ready ticket. I
   leave my losing claim comment where it is (it's inert — see Ownership; end-of-run cleanup will
   remove it), and I do *not* re-claim `#5` unless it later frees up.
5. **Pre-dispatch recheck (layer 3).** On a win, right before handing `#5` to `implement-ticket-v5`,
   do one more cheap read: "do I still hold the highest live token for `#5`?" This catches any
   residual race at the exact point where a double-run would waste real effort, for near-zero cost.
   The same check gates every later mutating action too (push, open PR, `✓ completed`) — that's the
   fencing-token yield that stops a falsely-reaped worker from clobbering its reclaimer. Then move
   `#5` to In Progress and run the pipeline.

**Why the delay (layer 2).** The winner is fixed by server-assigned comment ID, *not* by who reads
first — so two simultaneous reads can't both win **as long as each read is complete**. The one real
risk is a *stale* read: a worker re-reads before another's lower-ID claim has propagated, sees only
its own, and wrongly declares itself earliest. A short jittered wait closes exactly that window.
(Honest caveat, ED-3: GitHub's read-your-writes / gap-free-ordering behavior on the comments list is
treated here as a **hypothesis**, not a confirmed guarantee — which is *why* the settle delay is the
prudent default instead of trusting an immediate re-read. If we confirm the guarantee, the delay can
shrink or go.)

**Leftover claims are inert, so cleanup waits for the end.** Because ongoing ownership is the
tracking issue (see Ownership), a losing or dead claim comment left on the thread affects nothing —
no worker reads claims to decide who's *currently* on a ticket. So losers do **not** sweep
mid-journey (that was the resume-hole risk we rejected); the thread is tidied once, at shutdown.

**On completion**, the worker appends `✓ completed #5`. The `taken` flag on its claim stays as the
"this one was a winner, keep it" marker for end-of-run cleanup.

### The reaper (dead-worker recovery)

A worker that wins `#5` then dies mid-work would wedge it. Recovery is the existing orphan-recovery
(`orchestrate-v5/SKILL.md:229`) generalized to N workers, and it needs three parts — a **liveness
signal** to detect death, a **fencing token** so a *false* death can't double-run, and **partial-
work handling** so a reclaim doesn't duplicate artifacts.

**Liveness — a process-level ping, not a stage-level one.** The tracking issue only updates every
*stage*, and a big implement runs 30–45 min silent — so "issue quiet" ≠ "worker dead." Fix: the
**loop** (the worker's persistent identity, which outlives individual sessions) writes a liveness
timestamp on a fixed cadence, independent of stage progress. Cadence is throttle-conscious —
GitHub's secondary rate limit bites on content writes:

- The 45s heartbeat stays **local** (stdout + run log + cheap reads) — no content write.
- The liveness **write** fires every **TTL/4**. The invariant: *N pings per TTL window survives
  N−1 consecutive dropped writes before a false reap* — so TTL/4 (4 pings/window) tolerates **2**
  consecutive failed writes with margin, vs. TTL/2's zero. Express it as the **fraction TTL/4**, not
  a fixed number, so the margin holds if the TTL is ever retuned. Still frugal: at a 20-min TTL
  that's one write every 5 min/worker (~1/min total across five workers) — ~6× *lighter* than a
  45s ping.
- **Write mechanism:** the ping is an **in-place edit of a single per-worker `❤ wK alive` comment**
  (created once at loop startup, re-stamped each TTL/4). Not a fresh comment each time (thread
  spam), and **not** a body edit (that would collide with the session's stage/operator-slot writes
  to the body and risk clobbering them). The reaper reads that one comment's `updatedAt`.
- Because the ping is stage-independent, the TTL no longer has to clear a 40-min stage — it only
  covers transient API blips, so **TTL drops to ~10–20 min** (from the 90m session timeout).

`wK` is **dead** when its liveness comment's `updatedAt` is older than the TTL.

**Fencing token — so a false death can't double-run (the load-bearing part).** Takeover without
*relinquish* is just a race with extra steps: if `wK` was only paused past the TTL, a naive "resume
my own ticket" rule makes it resume `#5` *while the reclaimer works it* → double-run. So every
acquisition — first-time **or** reclaim — carries a **monotonic token = the winning claim's comment
ID**. A worker records ownership as `Current ticket: #5 @token <id>`, and:

- **Ownership = the live worker holding the *highest* token for `#5`.** A reclaim posts a new claim
  → higher token → **definitively supersedes** the dead worker's.
- **Before resuming, and before any mutating action** (push, open PR, post `✓ completed`), a worker
  re-checks it still holds the highest live token for `#5`. If a higher one exists it was
  superseded: it **yields** — abandons `#5` and returns to the pool. So a resurrected `wK` sees the
  reclaimer's higher token and stands down instead of resuming.

This also settles the brief window where a resurrected worker and its reclaimer both show
`Current: #5`: highest token wins, no cross-worker issue edits needed (the dead worker's stale
`Current` is simply outvoted — nobody reaches into anyone else's issue).

**Partial-work handling — adopt or tear down, never blind-restart.** A worker rarely dies at a clean
stage boundary; it may have left a branch, pushed commits, an open PR, `#5` at In Progress, and a
`ci-fix` background poller. A from-scratch restart makes a *second* branch/PR. So on reclaim, apply
the existing nuance (`SKILL.md:229`): if the dead worker's PR exists and is mid-review-loop,
**adopt** it and resume from there; if there's no usable state, **tear it down** (branch, PR, board
status) before re-running. Reclaim is adopt-or-teardown, not "free to pool and forget."

Note: the reaper keys on **tracking-issue liveness + tokens**, never on claim comments — leftover
claims never enter into it.

### End-of-run cleanup (thread tidiness)

Claim comments accumulate all run (losers and superseded winners), and that's fine — they're inert.
The thread is tidied **once, at the fixpoint**, never mid-journey:

- **When?** A worker reaching the run's fixpoint (`pool − done` empty — see the worker loop) does
  this as its last act before shutdown, gated on the *real* run-complete condition so nothing is
  in flight (no acquisition is mid-handshake once every ticket is `✓ completed`).
- **What?** Walk the plan ticket's claim comments and **delete every one *not* flagged `taken`** —
  i.e. every failed attempt. `taken` claims (winners) are left as an audit trail beside the
  `✓ completed` markers.
- **Overlap is harmless.** Several workers may hit the fixpoint together and run this at once;
  deleting an already-deleted comment is an idempotent 404 — ignore it. The pass is thorough
  because every worker sweeps the whole thread.
- **Residual litter (accepted):** a claim that was flagged `taken` but whose worker then died before
  completion (the reaper redid the ticket elsewhere) survives cleanup. Harmless; making it spotless
  would require cross-referencing `✓ completed`, which reintroduces the coupling we avoided.

---

## A worker's loop (mode selection)

On each fresh relaunch, a worker:

1. Fetches the plan ticket (pool + graph from the body; claims + completions from the comments).
2. Computes `done` (has `✓ completed`), `held` (a **live** worker holds the highest token for it —
   read from tracking issues; a **dead** holder, liveness past TTL, does not count), and
   `ready = pool − done − held`, keeping only tickets whose blockers ⊆ `done`. (Ownership is read
   from tracking issues, not claim comments — see Ownership.)
3. **If `ready` is non-empty:** pick one **at random** (not the topmost — see claim handshake layer
   1), run the claim handshake. On win, take it through the pipeline, post `✓ completed`, then
   **exit for relaunch** (fresh context per ticket, exactly as today). On loss, drop it from the
   candidate set and try the next.
4. **If `ready` is empty but `pool − done` is not:** everything left is blocked or claimed → write
   `Run state: WAITING` to the worker's tracking issue and exit; the loop backs off (~5 min) and
   relaunches to re-scan.
5. **If `pool − done` is empty:** all scoped work is complete → fall to CLEANUP / the run's
   fixpoint.

---

## Runtime pieces to build

### 1. Worker-aware plumbing

Two assumptions today enforce single-driver-per-repo and must become worker-scoped:

- **The lock.** `orchestrate-loop.sh:108` keys the `flock` on the project basename — one loop per
  project. Key it on `project + worker` so each worker holds its own lock.
- **Worker id — generate ONCE in the loop, never per session.** If `--worker` is omitted, the loop
  auto-generates an id at startup, **before the relaunch `while` loop**, and `export`s it (same
  mechanism as `ORCHESTRATE_N`, `orchestrate-loop.sh:135`) so every relaunched `claude -p` inherits
  the *same* id. Format: `w-$(date +%Y%m%d-%H%M%S)-$$` (timestamp + loop PID — the PID makes it
  collision-proof even if two workers launch in the same millisecond; label-safe). **Getting this
  wrong breaks everything:** an id generated fresh inside each session would make every relaunch
  look like a new worker — new tracking issue, blind to its own in-flight claim, resuming nothing.
- **The run-state tracking issue.** Everything queries `--label orchestration-run --state open --jq
  '.[0]'` (loop stop-check `orchestrate-loop.sh:218`, heartbeat `:157`, status
  `orchestrate-status.sh:19`, find-or-create `orchestrate-v5/SKILL.md:178`). Each worker needs its
  **own** tracking-issue identity — label `orchestration-run-<worker>` or a worker field the
  queries filter on. Threading a worker id through those ~8 query sites + the loop + status is the
  bulk of the mechanical work. (Net: **one shared plan ticket + N per-worker run-state issues.**)
- **Log / status filenames** (`orchestrate-loop.sh:139`) — key on `project + worker`.

### 2. The pool, the claim handshake, and the reaper

New logic in `orchestrate-v5` mode selection: the worker's loop above (scan → claim → work →
complete), the claim resolution (earliest claim by comment ID breaks acquisition; ownership +
fencing token recorded in the tracking issue; highest live token wins), the reaper (orphan-recovery
keyed on tracking-issue liveness + token, with adopt-or-teardown of partial work), and the
end-of-run cleanup pass (delete untaken claims at the fixpoint). Plus, in `orchestrate-loop.sh`, the
**TTL/4 liveness ping** — an in-place edit of the worker's single `❤ alive` comment (process-level,
throttle-conscious). This is the genuinely new coordination code.

### 3. The dependency gate + `WAITING` backoff

Reuse the existing `AWAITING_HUMAN` pattern (`orchestrate-v5/SKILL.md:341`): a tracking-issue body
flag that changes how the loop relaunches. A worker with no ready ticket writes `Run state:
WAITING`; the loop, on seeing it, **sleeps a backoff then relaunches** — versus `AWAITING_HUMAN`,
where it stops entirely (`orchestrate-loop.sh:237`). The **deadlock trip** (decision #5): when
*every live worker is WAITING and none is In Progress*, sustained 2–3 cycles, set `Run state: STUCK`
and stop relaunching rather than spin to `--max-iter`. A lone waiter is normal and never trips it.
The "thrash" is fine — it's the same fresh-relaunch the loop already does; the backoff just paces it.

### 4. Aggregate status

Teach `orchestrate-status.sh` (or a sibling) to read the plan ticket + all worker tracking issues
and print one view: `w1: #4 @ stage 4 · w2: WAITING · pool 6/9 done`.

---

## The planner skill (`orchestrate-plan-v5`)

A new authoring skill in the v5 family. It does **not** spawn workers and does **not** need to know
how many you'll run — it produces the plan; you decide worker count at launch.

**Input:** a ticket list — e.g. *"plan tickets #1–#15."*

**What it does:**
1. Reads each ticket (title, body, acceptance criteria, milestone) to **infer the dependency
   graph** — what must run before what, and what is independent.
2. **Shows you the proposed graph** and waits for a one-look confirm before committing (see below).
3. On confirm, writes the **plan ticket** (pool + graph) and prints example launch commands.

**Output:** the plan ticket (open, labeled `orchestration-plan`) + a reminder that you launch
`./scripts/orchestrate.sh --worker <id>` as many times as you want workers.

### Why the confirm gate (the one non-negotiable)

There is **no machine-readable dependency data in the repo** — story ordering is written as prose
("within a milestone, order stories so each builds on the previous one … A comes first,"
`standards/story-writing-standards.md:121`), never as a `depends-on: #4` field. So the planner is
**inferring** the graph from ticket content (ED-1 territory), and the graph is now the *sole*
carrier of correctness. A wrong edge either wastes time (needless waiting) or, worse, runs a
dependent ticket too early and breaks a build. A ten-second human eyeball is cheap; a bad edge is
expensive. Planner proposes; human confirms; then it commits. (Consistent with ED-4 / the cold-read
discipline: surface the fork, don't silently commit a guess.)

---

## Plan-ticket format (worked example)

Pool `#1..#9`, two dependencies: `#4` needs **all** of `#1,#2,#3` (a many-to-many gate lanes could
never express), and `#8` needs `#7`. Everything else is free.

```markdown
# Orchestration Plan — <run name>
Label: orchestration-plan

## Tickets (the pool)
#1 #2 #3 #4 #5 #6 #7 #8 #9

## Dependencies   (blocked → blockers; runs only when EVERY blocker is ✓ completed)
#4 → #1, #2, #3
#8 → #7
# all other tickets: none
```

Comments accrue over the run (append-only, the coordination log):

```
🔒 claim #1 · w1 · taken     # won → flagged taken, w1's tracking issue now holds #1
🔒 claim #2 · w2 · taken
🔒 claim #3 · w1 · taken      # w1 won the #3 race
🔒 claim #3 · w2              # lost #3 (higher ID); left inert, w2 moves to #5
✓ completed #1
✓ completed #2
✓ completed #3
🔒 claim #4 · w1 · taken      # #4's blockers now all ✓ → ready → claimed
...
# at the fixpoint, cleanup deletes the one untaken `🔒 claim #3 · w2`; taken claims stay
```

Launch (however many workers you want — here two):

```bash
./scripts/orchestrate.sh --worker w1
./scripts/orchestrate.sh --worker w2
```

Both workers chew through the free tickets (`#1,#2,#3,#5,#6,#7,#9`), racing and resolving claims as
they go. `#4` stays out of every worker's `ready` set until `#1,#2,#3` are all `✓ completed`, then
the next worker to scan claims it. `#8` waits on `#7` the same way. No lanes, no pre-assignment,
automatic load-balancing.

---

## What we deliberately do NOT build

- **A central dispatcher / coordinator.** Claiming is peer-to-peer, resolved through GitHub's
  append-only comment ordering. No extra service, no single point of failure — consistent with the
  stateless-relaunch design.
- **Merge serialization between workers.** If two workers touch the same files, their merges race —
  but that is the **same** situation as two human developers, and git resolves it the same way
  (rebase / re-run CI). Not a new problem parallelism introduces; nothing special to build.

---

## Backward compatibility (hard requirement)

The coordination machinery must be **inert without a plan ticket / `--worker`.** A plain
`./scripts/orchestrate.sh` must behave **exactly as today**: one lock, one `orchestration-run`
issue, no pool, no claims, no dependency checks. This keeps the change an additive upgrade rather
than a rewrite, and is the safety net for every existing single-driver run.

---

## Open decisions (for discussion)

1. **Done-signal** — **RESOLVED (2026-08-05):** worker appends `✓ completed #<id>` to the plan
   ticket after checkpoint; that record is the truth (per-ticket, append-only comment; not a body
   edit, not a PR merge).
2. **Claim/coordination surface** — **RESOLVED (2026-08-08):** claims and completions are
   append-only comments on the **plan ticket** (one fetch gives a worker everything). The claim
   comment does one job — **break the acquisition race** (earliest comment ID wins). **Ongoing
   ownership lives in the winner's tracking issue** (`Current ticket`), so leftover claims are inert
   and can't poison later resolution. Winner flags its claim `taken`; losers leave theirs. No
   mid-journey sweeps — a single **end-of-run cleanup** at the fixpoint deletes all untaken claims.
3. **Worker identity** — **RESOLVED (2026-08-08):** id keys lock/log/tracking-issue and stamps
   claims; join key to the worker's tracking issue for the liveness/reaper check. **Auto-generated
   once in the loop and exported if `--worker` is omitted** (`w-<datetime>-<pid>`) — launch-and-
   forget. **Explicit `--worker w2`** when you want that exact worker resumable across a loop
   restart (an auto-id does not survive a restart: the loop mints a new id and abandons the old
   worker's tracking issue + in-flight claim — the reaper recovers the *work* to the pool, but the
   stale worker issue is cosmetic litter). Generate-once-not-per-session is a hard rule — see the
   plumbing section.
4. **Dead-worker TTL** — **RESOLVED (2026-08-08):** the loop's **TTL/4 liveness ping** (in-place
   `❤ alive` comment, independent of stage progress) decouples "quiet" from "dead," so the
   alive-but-mid-long-stage worry is gone and the TTL can be short (~10–20 min, covering only
   transient API blips). See the reaper's Liveness part.
5. **Wait bound (deadlock trip)** — **RESOLVED (2026-08-08):** measured **run-wide, not per-worker**
   — a lone waiter is normal (it's waiting on a peer's blocker). Trip only when **every live worker
   is `WAITING` and none is In Progress** (nobody can make progress → nothing will complete →
   nothing will unblock), sustained **2–3 backoff cycles** to rule out a transient (a claim
   handshake in flight, a completion marker still propagating). On trip: set `Run state: STUCK`,
   **stop relaunching** (park like the milestone `AWAITING_HUMAN` gate — don't spin to `MAX_ITER`),
   and report which tickets are unready and why (usually a blocker parked in Waiting/Blocked, or a
   bad edge).
6. **Planner autonomy** — **RESOLVED (2026-08-08):** **propose-and-confirm only** — no autonomous
   mode. The planner infers the graph, shows it, and writes the plan ticket only on human confirm
   (plus the ED-5 cold read). A silent autonomous path would ship an unconfirmed *inferred* graph
   with zero checks — not worth the risk for the one skill whose single output is the correctness
   graph everything else depends on.

---

## Suggested build order

Each step is independently useful.

1. **Worker-aware plumbing** (lock + tracking-issue identity + log/status keys). After this, N
   hand-launched workers with **manually disjoint `--tickets` scopes** coexist — parallelism with
   no coordination yet (the "just tell one to run `#1,#3` and another `#2`" case).
2. **Shared pool + claim handshake + reaper.** Workers now self-select from one pool safely — no
   manual scoping, no double-runs.
3. **Dependency graph + `WAITING` gate.** Workers respect blockers; ordering is enforced.
4. **`orchestrate-plan-v5`** — the planner: ticket list → proposed graph → confirm → writes the
   plan ticket.
5. **Aggregate status** across workers.

---

## Versioning: upgrade v5, don't cut a v6

**Recommendation: keep this in the v5 generation — additive upgrade, no v6.**

The v4→v5 bump was a **generation** change: the four-tier test model + TR enforcement forced *every*
pipeline skill to be rebuilt and re-synced (`CLAUDE.md` → "v5 is the only synced generation"). A
version bump is the marker for "the skill contract itself changed."

Parallel orchestration changes **none** of that. The test model, TR, ED discipline, and all twelve
pipeline/authoring skills are **untouched**. The blast radius is exactly:

- `orchestrate-v5/SKILL.md` — patched (pool/claim/reaper + dep-gate), backward-compatible.
- `orchestrate-loop.sh` / `orchestrate-status.sh` — patched.
- `orchestrate-plan-v5` — one new skill, joins the v5 family.

Cutting a v6 would force re-versioning and re-syncing all thirteen skills for zero contract change —
pure churn — and would spoil the clean "v5 is the only synced generation" state. Reserve v6 for the
next time the **testing model or core pipeline contract** actually changes (the same trigger that
justified v5). This is an in-place v5 upgrade.
