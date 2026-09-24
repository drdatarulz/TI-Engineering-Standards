# Parallel Orchestration Plan

> **Purpose:** let **more than one orchestrator run at once inside a single repo**, so a batch of
> tickets finishes as fast as their dependencies allow instead of strictly one-at-a-time. A new
> **planner skill** turns a ticket list into a dependency graph + a shared ticket pool; you then
> launch as many orchestrators ("workers") as you like against it. The workers coordinate
> peer-to-peer through **one shared plan ticket** — no central dispatcher.
> **Created:** 2026-08-05. **Last updated:** 2026-09-24.
> **Status:** DRAFT — happy-path design done; **all three blockers now resolved** (B1, B2 on
> 2026-08-08; B3 on 2026-09-24). Round-1 cold read (CR-1…CR-12) all resolved. The **round-2 cold
> read (2026-08-08)** found 3 blockers (B1–B3) + 6 should-fixes (S1–S6) + 5 nits (N1–N5); **B1–B3 and
> S4 are resolved, plus S1, S2, S3, S5, S6 and new finding M1 (2026-09-24); only nits N4–N5 remain open.** See **Second cold-read findings** below.
> The core ownership model held; scope is **model A (full shared pool)**. Working the remaining S/N
> one at a time. **Added 2026-09-24:** usage-limit wait (U1, runtime piece #5) — in scope for this
> build, not a separate change. **Rebase note (2026-09-24):** DS-112 (PR #18, deploy-pipeline hard bar on C5) is now
> merged to `main`; the elected CLEANUP runner (B2) inherits that bar. `SKILL.md` citations below
> were re-grounded against `main` @ `96ead7a`.
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

## Deployment topology (foundational — read first)

**Each worker runs in its own separate clone (or git worktree) of the repo; they share only the
remote.** There is **no shared working tree** — a worker doing `git checkout`/branch/commit only ever
touches its own local checkout, exactly like a developer on their own machine. What is **shared** is
the **remote repo, the GitHub Project board, the issues (plan ticket + per-worker tracking issues),
and the `gh` token / rate-limit budget** — which is why all the coordination (claims, ownership,
reaper, rate-limit budgeting) lives on that GitHub surface, never on the filesystem. Operationally:
launch each worker from *its own* clone directory (so `--project-dir "$(pwd)"` resolves to a distinct
tree per worker). This is the premise that makes "two workers merging is just two developers merging"
(see §What we do NOT build) actually true rather than hand-waving.

---

## Concepts

- **Plan ticket** — one GitHub issue (label `orchestration-plan`) that is the primary **coordination
  surface** for a parallel run. Its **body** holds the static plan (the ticket pool + the
  dependency graph), written once by the planner. Its **comments** are the append-only coordination
  log — claims and completions. A worker's scan is *mostly* this one issue, but not *only* it:
  ownership/liveness come from enumerating the per-worker tracking issues, and `blocked` from a
  board-status read (CR-8, CR-10). **Exactly one is kept live** — the planner applies
  `orchestration-run`'s newest-wins dedupe rule (`SKILL.md:185`) to the `orchestration-plan` label,
  closing any stale older plan ticket (CR-9).
- **Dependency graph** — a flat, per-ticket edge list: `blocked → blockers`, where a ticket may
  have many blockers. This is the **only** carrier of correctness — a ticket runs only once *every*
  blocker is `✓ completed`. It knows nothing about workers or ordering beyond the edges.
- **Ticket pool** — the flat set of tickets in scope for the run. No partition, no lane. A ticket
  is **ready** when it is in the pool, not yet completed, not held by a live worker, not parked in
  board Waiting/Blocked, and all its blockers are completed — `ready = pool − done − held −
  blocked`, blockers ⊆ `done` (the one canonical form).
- **Worker** — one orchestrator instance, **running in its own clone/worktree** (see Deployment
  topology), with an id (`--worker w2`, or auto-generated if omitted — see Worker identity below).
  The id is an **ephemeral process identity** — it names *which orchestrator*, not *which work* (work
  is the shared pool). It keys the worker's lock, run log, and its own run-state tracking issue, and
  it stamps the worker's claims. Stable across that worker's relaunches; distinct between workers.
- **Claim handshake** — how a worker takes a ticket without another worker double-taking it. To
  take `#5`, a worker appends a claim comment stamped with its id; the **earliest** such claim wins
  the acquisition race (see below). Loser moves on; winner works it. The claim comment does **only
  this one job** — break the acquisition tie at the instant two workers grab the same ticket.
- **Ownership** — who is *currently* working a ticket. This lives in the winner's **run-state
  tracking issue** (`Current ticket: #5 @ stage n @token <claim-id>`), which the skill already
  maintains every stage — **not** in the claim comment. The `@token` is the worker's claim comment
  ID (monotonic). **Ownership = the *earliest* live claim (lowest token) — the incumbent wins as
  long as it's alive; a challenger yields.** This is the *same* rule as acquisition (earliest wins),
  now applied to ongoing ownership too — see the reaper for why the flip from "highest wins" matters
  (it kills a takeover livelock). The split (ownership in the tracking issue, not the claim) is
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
   **refresh my own liveness ping, then read**: "am I the *earliest* live claim for `#5`?" (Ping
   first so a live worker always counts itself live.) If an earlier live claim exists, the incumbent
   is back — **I yield** (I'm the challenger). If the read fails or is rate-limited, **I neither
   proceed nor yield — I back off and retry until I get a definite answer** (S1). This same check
   gates every later mutating action (push, open PR, `✓ completed`), and is what makes
   "incumbent-wins-if-alive" hold. Then move
   `#5` to In Progress and run the pipeline.

**Why the delay (layer 2).** The winner is fixed by server-assigned comment ID, *not* by who reads
first — so two simultaneous reads can't both win **as long as each read is complete**. The one real
risk is a *stale* read: a worker re-reads before another's lower-ID claim has propagated, sees only
its own, and wrongly declares itself earliest. A short jittered wait closes that window. A 10-sample
baseline probe (2026-08-08, CR-6) measured read-your-own-writes as **effectively immediate — visible
on the first read, ~1s dominated by `gh` call overhead, zero stale reads** — so **~5s settle delay
gives ≈5× margin.** Caveat (ED-3): that probe was single-client (cross-worker visibility could be
marginally worse) and small-sample (misses a rare tail), which is *why* the delay keeps margin and
the fail-safe backstops (the pre-merge earliest-live-claim recheck + the per-stage `⛙ merged`
marker — N3) carry the tail — read consistency is mostly an **efficiency** assumption here; see
N3 for the narrow residual.

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

**First: in worker mode the *legacy global* Step 0.6 sweep is DISABLED** (see CR-5). That sweep
assumes a single driver and resets *any* In-Progress ticket that looks orphaned — which in worker
mode is another worker's live work. Recovery in worker mode is only these two, both scoped: a
relaunching worker **self-recovers** just what its own tracking issue owns (its `Current ticket`,
if not `✓ completed`); and this reaper reclaims *another* worker's ticket **only on death** (stale
liveness), never because a ticket merely looks In-Progress. Nothing strands: selection runs off the
pool math (`ready = pool − done − held − blocked`, blockers ⊆ `done`). The board is trusted
**only for Waiting/Blocked** (`blocked`); ownership and completion never come from its In
Progress/Done columns.

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
- **Write mechanism:** the ping is an **in-place edit of a single `❤ wK alive` comment on the
  worker's own tracking issue** (S3) (created once at loop startup, re-stamped each TTL/4). Not a fresh comment each time (thread
  spam), and **not** a body edit (that would collide with the session's stage/operator-slot writes
  to the body and risk clobbering them). The reaper reads that one comment's `updatedAt`.
- Because the ping is stage-independent, the TTL no longer has to clear a 40-min stage — it only
  covers transient API blips, so **TTL drops to ~10–20 min** (from the 90m session timeout).

`wK` is **dead** when its liveness comment's `updatedAt` is older than the TTL — **but the reaper is
throttle-aware: if its own `gh` calls are being rate-limited it does NOT reap** (a stale ping is
ambiguous under throttle — starved vs. dead). This breaks the rate-limit feedback loop (throttle →
missed pings → false reaps → reclaim storm → more writes); under pressure the system stops reaping
and self-heals when throttle clears. See CR-4.

**Incumbent-wins-if-alive — so a false death can't double-run *and* can't livelock (the load-bearing
part).** The naive rule "the taker-over wins" (highest token) has two failures: it discards the
incumbent's progress (it was further along), and — worse — if takeovers are triggered by *slowness*,
the taker-over is also slow, gets taken over, and the ticket churns between workers forever, never
finishing. So the rule is **the earliest live claim wins — the incumbent keeps `#5` as long as it's
alive; the challenger yields.** Every acquisition (first-time or reclaim) carries a **monotonic
token = the claim's comment ID**, recorded as `Current ticket: #5 @token <id>`:

- **Ownership = the *earliest* live claim (lowest token).** A slow-but-alive incumbent keeps its
  lower token → **keeps the ticket** → no churn, no lost progress. A reclaim only wins because the
  incumbent is **dead** (dropped from the live set, so the reclaimer becomes the earliest *live*
  claim) — real-death recovery still works, no wedge.
- **Before resuming and before any mutating action** (push, open PR, `✓ completed`), a worker
  **refreshes its own liveness ping, then re-reads**: "am I the earliest live claim?" If an earlier
  live claim exists, the incumbent is back → the challenger **yields** (abandons `#5`, returns to
  the pool). An unreadable answer (failed/throttled read) is never treated as "clear" — pause and
  retry until definite (S1). A resurrected incumbent, being the earliest live claim, reclaims its own work; the
  challenger stands down. (Ping-first so a live worker always counts itself live.)
- **Why "alive" is trustworthy:** the liveness ping is the **loop's**, not the work session's — so a
  worker stuck in a long or wedged stage still counts alive (the loop keeps pinging and will
  relaunch a hung session via its own timeout). Only a dead *loop* goes stale. So "still alive" ≈
  "will make progress" — exactly the thing that makes the incumbent worth keeping.

**Partial-work handling — hands off the other worker's branch.** Since a resurrected incumbent can
win back `#5`, the challenger must **never destroy the incumbent's work** — no adopt, no teardown of
someone else's branch/PR. Each worker works its **own** branch — and this is literal because branch
names are **worker-scoped** (`story/{STORY_ID}-{worker}-…`, B1), so two workers on one ticket never
collide on a ref. The **yielder cleans up its own** on standing down; a genuinely-dead worker's
orphan branch/PR is left untouched (resurrection-safe) and swept at **CLEANUP** (its distinct name
means it never blocks the reclaimer). **Guarding each merge (N3):** before merging any stage's PR,
the worker's recheck asks both "am I the earliest live claim?" *and* "has any worker already posted
`⛙ merged #5 · <stage>`?" — if the stage is already merged, it stands down and tears down its own
branch. Right after its own merge it posts `⛙ merged #5 · <stage> · w2`. `✓ completed #5`
(Stage 8) only stops a *finished* ticket from being worked again; it fires too late to guard
individual merges. (Depends on liveness being trustworthy and on GitHub read-consistency — CR-4,
CR-6; residual in N3.)

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
2. Computes `done` (has `✓ completed`), `held` (some **live** worker owns it — the earliest live
   claim; read from tracking issues; a **dead** holder, liveness past TTL, does not count), `blocked`
   (board Status = Waiting/Blocked — the one board signal trusted; CR-8), and
   `ready = pool − done − held − blocked`, keeping only tickets whose blockers ⊆ `done`. (Ownership
   from tracking issues and completion from `✓ completed` — not the board's In-Progress/Done; only
   Waiting/Blocked is read from the board.)
3. **If `ready` is non-empty:** pick one **at random** (not the topmost — see claim handshake layer
   1), run the claim handshake. On win, take it through the pipeline, post `✓ completed`, then
   **exit for relaunch** (fresh context per ticket, exactly as today). On loss, drop it from the
   candidate set and try the next.
4. **If `ready` is empty but `pool − done` is not:** everything left is blocked or claimed → write
   `Run state: WAITING` to the worker's tracking issue and exit; the loop backs off (~5 min,
   stretching toward ~15 min while nothing changes, jittered — S6) and relaunches to re-scan.
5. **If `pool − done` is empty AND `held` is empty (quiescence):** try to claim the **cleanup role**
   (`🧹 cleanup-claim` comment on the plan ticket, earliest wins — B2). The winner runs the single
   heavyweight **CLEANUP** pass (C1–C5); if it injects work, the suite isn't green, or the Deploy
   Pipeline isn't green (DS-112 bar) it re-enters the pool (workers resume WORKING) and does *not*
   close; only an inject-nothing + tests-green + deploy-green pass closes the
   **plan ticket** (`RUN_COMPLETE`). Losers exit/relaunch. **The loop stops only when the plan ticket
   is closed** (S4) — an idle worker WAITS, it never self-stops on being idle.

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
  '.[0]'` (loop `orchestrate-loop.sh:157/194/218/237`, status `orchestrate-status.sh:19`,
  `monitor-v5/SKILL.md:30`, find-or-create `orchestrate-v5/SKILL.md:178`). In worker mode each
  worker gets its **own** tracking issue, identified per **S3**: shared label
  `orchestration-worker`, worker id in the title (`Worker w2 — plan #40`), found by listing the
  label and matching the title. Worker issues **never** carry `orchestration-run`, so legacy
  queries never see them. Threading worker mode through those query sites + the loop + status is
  the bulk of the mechanical work. (Net: **one shared plan ticket + N per-worker run-state
  issues.**)
- **Log / status filenames** (`orchestrate-loop.sh:139`) — key on `project + worker`.

### 2. The pool, the claim handshake, and the reaper

New logic in `orchestrate-v5` mode selection: the worker's loop above (scan → claim → work →
complete), the claim resolution (**earliest live claim wins** — for both acquisition and ongoing
ownership; token = claim comment ID recorded in the tracking issue), the reaper (orphan-recovery
keyed on tracking-issue liveness; **incumbent-wins-if-alive**, challenger yields, hands off the
other's branch), and the end-of-run cleanup pass (delete untaken claims at the fixpoint). Plus, in
`orchestrate-loop.sh`, the
**TTL/4 liveness ping** — an in-place edit of the worker's single `❤ alive` comment (process-level,
throttle-conscious). This is the genuinely new coordination code.

### 3. The dependency gate + `WAITING` backoff

Reuse the existing `AWAITING_HUMAN` pattern (`orchestrate-v5/SKILL.md:341`): a tracking-issue body
flag that changes how the loop relaunches. A worker with no ready ticket writes `Run state:
WAITING`; the loop, on seeing it, **sleeps a backoff then relaunches** — versus `AWAITING_HUMAN`,
where it stops entirely (`orchestrate-loop.sh:237`). The **deadlock trip** (decision #5): when
*every live worker is dependency-WAITING and no worker holds a ticket* (`held` empty — S2),
sustained 2–3 cycles, set `Run state: STUCK` and stop relaunching rather than spin to `--max-iter`.
A lone waiter is normal and never trips it. A worker wedged on a poison ticket can't hold the run
hostage: the **no-progress bound** (S2) parks that ticket after 3 relaunches on the same stage,
which empties `held` and lets the trip fire.
The "thrash" is fine — it's the same fresh-relaunch the loop already does; the backoff just paces it.

### 4. Aggregate status

Teach `orchestrate-status.sh` (or a sibling) to read the plan ticket + all worker tracking issues
and print one view: `w1: #4 @ stage 4 · w2: WAITING · pool 6/9 done`.

### 5. Usage-limit wait (`LIMIT_WAIT`) — U1

**The gap (grounded, exists today even single-driver):** the loop has no pause between
relaunches. When a session hits the Claude usage limit, `claude -p` exits fast with an error; the
loop classifies that as a crash and relaunches **immediately** (`orchestrate-loop.sh:251-258`).
Every relaunch fails the same way, so the loop burns all `MAX_ITER` (50) iterations in minutes and
exits on the circuit breaker (`:261-264`) — an overnight run dies instead of waiting out the
limit. Parallel makes it worse: N workers on one Claude account drain the allowance ~N× faster and
hit the wall together.

**Fix — lives in the loop, not the skill** (the session is already dead; only the bash loop can
react):
- **Detect:** after each session exits, match the captured session output (`$logfile`) for the
  usage-limit message. **ED-3 — the exact text `claude -p` emits is not yet known; capture a real
  one before writing the pattern** (don't guess a regex). Detection keys on that output, not on
  `rc` alone (a limit exit and a crash may share an exit code).
- **Wait:** if the message carries a reset time, sleep until it (+ small jitter so N workers
  don't stampede the reset). If not, probe **hourly** with a minimal `claude -p` call and resume
  on the first success. Limit-wait iterations **do not count toward `MAX_ITER`** — they are not
  failures.
- **Surface:** write `Run state: LIMIT_WAIT (retry ~HH:MM)` to the tracking issue (worker mode:
  the worker's own run-state issue) so `orchestrate-status.sh` / `monitor-v5` show *why* the run
  is quiet; clear it on resume. Local heartbeat keeps logging the wait.
- **Resume:** the session died mid-stage, so the next relaunch recovers through the existing path
  — legacy Step 0.6, or worker-mode self-recovery of its own `Current ticket` (CR-5). Nothing new.

**Interactions with the coordination machinery:**
- **Reaper:** a worker in `LIMIT_WAIT` keeps its **loop** liveness ping, so it stays *alive* and
  keeps its ticket. Correct by design — every worker on the account is blocked anyway, so reaping
  would move work to another equally-blocked worker and gain nothing.
- **S2's per-worker no-forward-progress bound** must **exempt `LIMIT_WAIT`** (and not count wait
  time toward the bound), or a limit wait would trip STUCK.
- **Deadlock trip (decision #5):** "every live worker WAITING" must mean dependency-`WAITING`
  only; workers in `LIMIT_WAIT` are **not** evidence of a graph deadlock and never trip STUCK.
- **Legacy mode:** gets the same fix — this is one of the few changes that alters the no-flag path,
  deliberately (it fixes a real bug there). Behavior when *no* limit is hit is byte-for-byte
  unchanged, so CR-2's spirit holds.

---

## The planner skill (`orchestrate-plan-v5`)

A new authoring skill in the v5 family. It does **not** spawn workers and does **not** need to know
how many you'll run — it produces the plan; you decide worker count at launch.

**Input:** a ticket list — e.g. *"plan tickets #1–#15."*

**What it does:**
0. **Precondition — every pool ticket must be refined** (CR-7). Runs `refine-story-v5`'s own
   Already-Refined check (`skills/refine-story-v5/SKILL.md:55` — body has all spec sections); if any
   ticket isn't refined, **halt and name it** — do not build the graph from content Stage 1 will
   rewrite. (Matches practice: refine first, then orchestrate.)
1. Reads each refined ticket — the explicit **`## Dependency on {issue#}`** section
   (`refine-story-v5:323`) for *declared* edges, and the body/AC to **infer** edges only where a
   ticket is silent — building the dependency graph.
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
- **Merge serialization between workers.** Because each worker is in its **own clone** (see
  Deployment topology), two workers touching the same files is exactly two human developers on
  separate checkouts — resolved the same way (rebase / re-run CI). No merge queue or lock. *But*
  the skill today halts on a merge conflict, so worker mode must actually do the rebase-and-retry
  (**M1**), and post-merge CI breakage is shared fate that needs one repair owner and a merge hold
  (**S5**) — those are built; a general merge serializer is not. (This holds *only* because of the separate-clone
  topology — under a shared working tree it would instead be repo corruption, which is why the
  topology is stated as a foundational requirement, not an assumption.)

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
   is dependency-`WAITING` and no worker holds a ticket** (`held` empty — S2; not the board's In
   Progress column, per CR-5) (nobody can make progress → nothing will complete →
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

## Cold-read findings (2026-08-08) — work through one at a time

A fresh adversarial reviewer read this plan against the repo (all file:line citations verified
accurate). Findings below, most severe first. **Status: all worked through and RESOLVED
(2026-08-08)** — CR-11 (scope) decided **model A, the full shared pool**; CR-1/CR-2 (blockers) and
CR-3–CR-10 addressed; resolutions folded into the body above. Each entry keeps its resolution for
the record.

- **CR-1 — RESOLVED-BY-DESIGN — separate clone per worker.** The concern (concurrent git ops on one
  working tree → corruption) only arises if workers share a directory, which the plan's launch
  example implies (`--project-dir "$(pwd)"`). **Intended model: each orchestrator instance runs in
  its own separate clone (or git worktree), all pushing to one shared remote** — i.e. genuinely "N
  developers on N checkouts," which git handles. No shared tree, no corruption. *Fix = make the
  separate-clone model explicit in the plan (one line); not a redesign.* Residual (lock keying) folds
  into CR-2. *Status: RESOLVED — separate-clone requirement now written into §Deployment topology,
  the Worker concept, and the §What-we-do-NOT-build merge bullet.*
  **Topology (for the remaining findings):** local working trees = separate; the **remote repo,
  board, issues, and `gh` token = shared** — so CR-3/4/5/6/8/9/10 live on that shared GitHub surface,
  not the tree, and remain.
- **CR-2 — RESOLVED — worker mode is opt-in via `--worker`.** No `--worker` → **legacy
  single-driver path, byte-for-byte today's behavior** (basename lock, bare `orchestration-run`
  label, no auto-id). `--worker w2` → worker mode with that id; `--worker` with no value (or the
  planner's launch commands) → worker mode, **auto-generated id**. In worker mode the lock/log/
  tracking-issue key on the **worker id**, not the directory basename (also fixes CR-1's leftover:
  two same-named clones colliding on one lockfile). **Self-gates per invocation** — no migration, no
  per-project "converted" state. The whole backward-compat obligation collapses to: *don't touch the
  no-flag path.* Worker-mode's pool is the explicit plan-ticket set (no blank "grab all Up Next"
  sweep). Operational rule: don't run legacy + worker-mode against the same board at once (shared
  queue) — low risk in practice since runs are always scoped. *Status: RESOLVED.*
- **CR-3 — RESOLVED — flipped to incumbent-wins-if-alive; damage bounded to wasted compute.** The
  original "highest token / taker-over wins" rule had a **livelock**: if slowness triggers takeover,
  the taker-over is also slow → taken over → the ticket churns forever, discarding progress each
  time. Fix: **earliest live claim wins** — the incumbent keeps the ticket as long as it's alive
  (liveness = the *loop's* ping, so a slow/wedged stage still counts alive); a challenger yields.
  Real death still recovers (a dead incumbent drops from the live set → challenger becomes earliest
  live). Consequence: **hands off the other worker's branch** (no adopt/teardown of someone else's
  work, since a resurrected incumbent can win back), each works its own, yielder cleans up its own,
  and each merge is guarded by the recheck + per-stage `⛙ merged` marker (N3; `✓ completed` only
  guards a finished ticket). The TOCTOU window can't be closed atomically on GitHub; the worst case
  is **usually wasted compute, and rarely a duplicate merge of one stage** that CI/review must
  catch (N3 — corrected from the original "never a corrupted `main`"). Depends on CR-4 (liveness trustworthy) + CR-6 (read
  consistency). *Status: RESOLVED.*
- **CR-4 — RESOLVED (fail-safe; not urgent until it bites) — backoff + throttle-aware reaper.** Real
  risk is bursts + a feedback loop, not sustained volume (primary limit ~5k/hr is generous; the
  *secondary* limit on bursty content-creation is what bites, and its thresholds are undocumented —
  ED-3). Mitigations: **(1)** every `gh` call honors `Retry-After` / backs off — a rate-limit
  response is never a stage failure (kills retry pile-on). **(2)** the **reaper is throttle-aware:
  if its own gh calls are being rate-limited it does NOT reap** — a stale ping is ambiguous under
  throttle (starved vs. dead), so the reaper's own API health is the discriminator; this breaks the
  feedback loop (under pressure the system stops reaping, self-heals when throttle clears). **(3)**
  jitter non-urgent writes; keep the liveness ping tiny/prioritized. **(4)** one identity has a
  ceiling → guide **small N (~3–5) on one account**; the scaling lever is **distinct GitHub
  *accounts* per worker** (separate bot/service accounts, or a GitHub App with per-worker
  installation tokens). NB: the limit is per *account*, not per token — logging in each worker as
  the *same* user (even separate tokens/sessions) shares one budget; only distinct accounts multiply
  it. Net: mis-estimating the limit degrades to *slower*, never a reap storm. Confirm safe N
  with an empirical spike (cf. CR-6) when it matters. *Status: RESOLVED.*
- **CR-5 — RESOLVED — worker-mode recovery is scoped; the global In-Progress sweep is OFF.** Legacy
  Step 0.6 (`SKILL.md:229`) assumes a single driver (every In-Progress ticket is *its* crashed work),
  so its global "sweep all In-Progress, resume-or-reset" is wrong in worker mode. Fix: under a plan
  ticket, split it and **disable the global sweep** — (1) **self-recovery:** a relaunching worker
  recovers **only** what its own tracking issue shows it owns (its `Current ticket`, if not yet
  `✓ completed`), never the global set; (2) **reaper:** another worker's ticket is recovered only
  when that worker is *dead* (stale liveness), never because it merely looks In-Progress. Being
  In-Progress is not grounds to reset a ticket; only owner-death is. Nothing strands because
  selection runs off the **pool math** (`ready = pool − done − held − blocked`, blockers ⊆ `done`;
  `held` from live tracking issues). The board is trusted **only for Waiting/Blocked**; ownership
  and completion never come from it — a ticket sitting In Progress with no live owner is simply
  `ready` again. Tidiness:
  record ownership in the tracking issue *before* the board move. Legacy mode (no plan ticket) keeps
  0.6 byte-for-byte (CR-2 rule). *Status: RESOLVED.*
- **CR-6 — RESOLVED (down-graded to build-informing; baseline measured 2026-08-08).** Re-framed:
  read-consistency governs **efficiency** (how often two workers waste effort both grabbing a
  ticket), **not correctness** — correctness is backstopped by earliest-live-claim ownership (CR-3)
  + the per-stage `⛙ merged` marker checked before each merge (N3). So a false assumption degrades
  to *wasted compute* (same bounded residual as CR-3, incl. N3's rare duplicate merge), not a broken
  run → **not a hard build gate.** Quick empirical baseline (10-sample lag probe on a throwaway
  issue, single-client read-your-own-writes): **10/10 comments visible on the first read, ~0.8–0.9s
  round-trip dominated by `gh` call overhead → propagation effectively immediate, zero stale reads.**
  Caveats: single-client (cross-worker could be marginally worse), small sample (misses the tail).
  **Decision: settle delay ~5s (≈5× the baseline); fallbacks = longer delay / read-until-stable if
  the tail ever bites; adjust empirically later.** *Status: RESOLVED.*
- **CR-7 — RESOLVED — planner requires refined tickets; then the graph is built from final content
  + declared edges.** The problem was the graph inferred from *pre-refinement* prose that Stage 1
  (`refine-story-v5`) then rewrites mid-run. Fix (matches practice: refine before orchestrating):
  the **planner validates every pool ticket is already refined** — reusing `refine-story-v5`'s own
  **Already-Refined Detection** (`skills/refine-story-v5/SKILL.md:55` — body contains all required
  spec sections) — and **halts naming any that aren't**. Two payoffs: (a) refined bodies carry an
  explicit **`## Dependency on {issue#}`** section (`refine-story-v5:323`), so the planner reads
  *declared* edges and only *infers* where silent (propose-and-confirm covers the remainder);
  (b) since pool tickets are already refined, the pipeline's Stage 1 self-detects `AlreadyRefined`
  and **skips**, so nothing rewrites a ticket after the graph is frozen. **Injected-ticket residual:**
  a mid-run injected fix must be refined *before* entering the pool (so its `## Dependency on` is
  visible); since injected fixes almost always depend only on already-done work, they enter as
  immediately-ready with no blocking edge. Graph never built from un-refined content. *Status:
  RESOLVED.*
- **CR-8 — RESOLVED — `ready` subtracts board-Waiting/Blocked (the one board signal we trust).**
  Fix (a): **`ready = pool − done − held − blocked`**, `blocked` = tickets at board Status
  **Waiting/Blocked**. Catches both a human park *and* the pipeline's own move-to-Waiting/Blocked on
  a Blocked stage (`SKILL.md:550`); the ticket drops out of `ready`, no re-claim. Reversible: move it
  back to Up Next → it re-enters `ready`. **Consistency with CR-5:** the board is authoritative
  **only for "blocked"** — In-Progress/Done columns stay untrusted (ownership = tracking issues via
  `held`, completion = `✓ completed` markers). Fix (b): a blocked ticket's dependents **wait, not
  fail** (the block may lift — resolve → complete → dependents unblock; failing would throw away
  recoverable work). Surface the impact: the STUCK-trip report (decision #5) **names the blocked
  blocker** (`#3 unready: blocker #8 in Waiting/Blocked`); optionally surface eagerly when a ticket
  enters Waiting/Blocked. Adds a board-status read to the scan (consistent with CR-10). *Status:
  RESOLVED.*
- **CR-9 — RESOLVED — plan ticket gets the same dedupe rule.** The planner applies
  `orchestration-run`'s COUNT≥2 "keep the newest open, close the stale older one(s)" rule
  (`SKILL.md:185`) to the `orchestration-plan` label, so there is never more than one live
  coordination surface. *Status: RESOLVED.*
- **CR-10 — RESOLVED (wording) — "one fetch" corrected.** The doc no longer claims a worker decides
  from "one fetch of the plan ticket." Reality: a scan reads the plan ticket (pool/graph/claims/
  completions) **plus** enumerates worker tracking issues (ownership/liveness) **plus** a
  board-status read (Waiting/Blocked, CR-8). Stale auto-id worker issues (loop restarts) are ignored
  by the liveness filter and swept by dedupe/cleanup so they don't pollute the enumeration or the
  deadlock-trip count. *Status: RESOLVED.*
- **CR-11 — RESOLVED — decided: model A, the full shared pool.** The alternative (build-order step 1:
  hand-launched workers with disjoint `--tickets` scopes, no pool/claim/fence/reaper) is simpler but
  buys no auto-load-balancing or dependency-gating. Decision: **build the full shared pool** — the
  premises that made the "over-engineered?" question sharp have since softened (CR-1 shared-tree is a
  non-issue under separate clones; CR-6 read-consistency measured effectively immediate and is only
  an efficiency assumption). Step 1 remains a valid *incremental* first milestone (see build order),
  but the target is A. *Status: RESOLVED.*
- **CR-12 — nit — DONE.** Header "last updated" was stale (said 08-05 while decisions were resolved
  08-08). Fixed in this edit.

---

## Second cold-read findings (2026-08-08, round 2) — work one at a time

A second fresh reviewer read the *revised* plan against the repo (citations verified; two minor
drifts noted in N4). It confirmed the core ownership model holds (CR-1/2, CR-3 livelock kill, CR-9)
but found the **recovery / injection / close-out machinery** under-specified — the paths a real
multi-hour, 15-ticket run *will* exercise. Most severe first. Status: B1–B3, S1–S6, N1–N3 RESOLVED; N4–N5 OPEN.

- **B1 — RESOLVED — worker-scoped branch names.** Branch names are per-**ticket** today:
  `story/{STORY_ID}-…` (`SKILL.md:433`), `-integration-tests` (`:615`), `-ui-tests` (`:737`), so two
  workers on one ticket (reclaim or resurrection window) push the *same* ref → non-ff reject or
  destructive force-push. Fix: **in worker mode, branch names get a worker segment** —
  `story/{STORY_ID}-{worker}-{slug}` (and `-{worker}-integration-tests` / `-{worker}-ui-tests`).
  No two workers ever push the same ref. **This is what makes "swept at CLEANUP" fine** (the
  reviewer's "too late" objection): under the shared name the reclaimer was *blocked* by the orphan;
  with its own name it isn't, so a dead worker's orphan `story/HC-5-w1-…` harmlessly waits for
  CLEANUP. Keeps hands-off + resurrection-safe: **never delete another worker's branch on reclaim**
  (a resurrected incumbent wins under CR-3 and needs it); a **yielder** closes its *own* PR+branch;
  the merge gate merges the *owner's* branch (earliest-live-claim); a genuinely-dead worker's orphan
  branch/PR is swept at **CLEANUP** (extend the `^(story|fix|task|ci-fix)/` sweep, `SKILL.md:903`, to
  orphaned worker branches + stale worker PRs). Design choice: a dead worker's partial ticket is
  **redone from scratch** on a fresh branch, not *adopted* — consistent with hands-off; adopting a
  maybe-not-dead worker's branch reopens the shared-branch race. **Legacy mode (no `--worker`) keeps
  `story/{STORY_ID}-…` byte-for-byte (CR-2).** *Status: RESOLVED.*
- **B2 — RESOLVED — CLEANUP is a single *elected* runner; the plan ticket is the fixpoint.** The
  heavyweight CLEANUP mode (`SKILL.md:931-1006`: C1 full UI regression dispatch, C2/C3 audits that
  **inject tickets**, C4 fix injection, C5 close + `RUN_COMPLETE` — C5 now also carries DS-112's
  authoritative `deploy.yml` hard bar) must not run N-way. Fix: when a
  worker observes **quiescence** (`pool − done` empty **and** `held` empty), it **claims the cleanup
  role** via an append-only `🧹 cleanup-claim` comment on the plan ticket (earliest-comment-ID wins,
  same handshake as tickets); **only the winner runs CLEANUP, losers exit/relaunch.** One UI
  dispatch, one audit pass. **The fixpoint closes the PLAN ticket** (+ `RUN_COMPLETE`) — that is the
  run authority; per-worker tracking issues are run-state only and never gate completion. The
  **WORKING↔CLEANUP oscillation is preserved**: injections (C2/C3/C4) use B3's append-safe channel;
  if the owner injected anything or the suite isn't green it **does not close** — injected work
  re-enters the pool, workers resume WORKING, a later quiescence re-elects a fresh cleanup owner;
  only an inject-nothing + tests-green + deploy-green pass reaches C5 close. (Because the elected
  owner runs C5, the DS-112 deploy bar — poll-to-terminal, re-run-once to classify flaky, route a
  real red to `ci-fix-v5` — runs exactly once, not N-way. Interaction with S5's CI-repair owner is
  S5's to settle.) (Quiescence's `held`-empty test is shared with the
  S2 deadlock detector.) *Status: RESOLVED.*
- **B3 — RESOLVED (2026-09-24) — append-only `➕ pool` comments are the one injection channel.**
  Problem: pool + graph live in the plan-ticket **body** ("written once"), and concurrent body edits
  are forbidden (last-write-wins). But work gets added mid-run, and a body-edit injection would
  silently drop tickets under a race (the II-210/II-226 deferred-work bug). There are **three**
  injectors, not two — the round-2 reviewer missed the third:
  1. **Stage 2d UI-deferral follow-ups** (`SKILL.md:458-478`) — a worker mid-ticket.
  2. **CLEANUP C4 fix/re-tier tickets** (`SKILL.md:978-980`) — the elected cleanup owner.
  3. **The operator slot** — "add #12,#13 to the run" (`SKILL.md:220`). All three today append to
     the tracking issue's `Scope:` field (C4 says so explicitly at `:980`); in worker mode that field
     is per-worker run-state, **not** the pool, so writing there would inject into nothing.

  **Fix — one append-safe channel for all three:**
  - **Format:** a comment on the plan ticket, `➕ pool #N` or `➕ pool #N → #A, #B` (same edge syntax
    as the body's `## Dependencies`). One comment per injected ticket. Never edited, never deleted
    (end-of-run cleanup sweeps only untaken `🔒 claim` comments).
  - **Scan:** `pool = body pool ∪ all ➕ pool #N`; `graph = body edges ∪ ➕ edges`. Union is
    idempotent, so a double-injection (two workers, or a retry) is harmless. The body stays frozen
    as the planner wrote it — it remains the confirmed plan, the comments are the delta.
  - **Operator slot in worker mode:** whichever worker's session reads a mid-run "add #X" converts
    it to `➕ pool #X` comments on the plan ticket (never `Scope:`). The operator can also just post
    the `➕ pool` comment on the plan ticket directly — that's the preferred path.
  - **Refined-first (CR-7 carried over):** a ticket must be refined **before** its `➕` is posted, so
    its `## Dependency on` is readable and Stage 1 won't rewrite it after it's in the graph. 2d
    follow-ups and C4 fixes are created by the orchestrator, which refines them (or runs
    `add-story-v5` non-interactive + `refine-story-v5`) before posting. An operator-added ticket that
    isn't refined: the converting worker refines it first, then posts.
  - **Edges on injection:** 2d follow-ups depend on their parent (`➕ pool #F → #P`), which is
    already `✓ completed` or about to be — so they're effectively immediately ready. C4 fixes are
    injected at quiescence, when everything is done — no edges. An edge to a ticket **outside the
    pool** is legal only if that ticket is already closed; otherwise the injected ticket can never
    become ready → it shows up in the STUCK report (`#F unready: blocker #Z not in pool`), never a
    silent wedge.
  - **Close-time race (the one real window):** C5 closes the plan ticket; a `➕` could land between
    the owner's quiescence read and the close. A 2d injection can't — quiescence means `held` is
    empty, so no worker is mid-ticket. C4 injections come from the owner itself. The operator can
    post at any time, though. So **C5 re-reads the plan ticket's `➕ pool` comments immediately
    before closing**, and if any `➕` ticket is not `✓ completed`, it does **not** close — the new
    work re-enters the pool and quiescence is re-evaluated later. Residual: an operator `➕` posted
    in the few seconds between that re-read and the close is lost — accepted; the operator sees the
    plan ticket closed and re-plans.
  - **Legacy mode (no `--worker`):** unchanged — injectors keep appending to `Scope:` (CR-2).
  *Status: RESOLVED.*
- **S1 — RESOLVED (2026-09-24) — the recheck pauses and retries; it never acts on an unreadable
  answer.** CR-4 made the *reaper* fail-safe under throttle, but double-run safety actually rests on
  the pre-dispatch/pre-mutation "am I the earliest live claim?" recheck, which reads peer liveness
  and was not throttle-aware — a failed read could be mistaken for "no earlier live claim" and let a
  challenger push/merge. Decision: **fail-closed by waiting, not by yielding.** If the recheck's
  reads fail or are rate-limited, the worker **does not proceed and does not give up the ticket** —
  it backs off (honoring `Retry-After`) and retries until it gets a *definite* answer, then acts on
  that answer (proceed if earliest live, yield if an earlier live claim exists). Rejected: yield on
  unreadable liveness — equally safe, but a transient rate-limit blip would discard a ticket's work.
  No retry cap: throttle is self-clearing, and peers under the same throttle don't reap (CR-4), so
  the worker's claim is not lost while it waits. **Constraint on S2:** time spent paused on an
  unreadable recheck is not "no forward progress" (same exemption as `LIMIT_WAIT`). *Status:
  RESOLVED.*
- **S2 — RESOLVED (2026-09-24) — trip on `held` empty + a per-ticket no-progress bound (3
  relaunches on the same stage → park).** Two problems. **(a) Wording:** the trip said "none In
  Progress" — a board column, which CR-5/CR-8 say not to trust for ownership. Now: **no worker holds
  a ticket (`held` empty).** **(b) Poison ticket:** a ticket whose sessions keep crashing or timing
  out *without* cleanly reporting Blocked (a clean Blocked already parks it — `SKILL.md:550`) keeps
  its worker alive and holding forever, so the trip never fires. Worse, it **cascades**: the
  worker's own loop eventually hits `MAX_ITER` and exits → its ping goes stale → the reaper hands the
  ticket to the next worker → which wedges the same way → one bad ticket consumes every worker in
  turn, hours each, before a human hears about it.
  **Fix — the no-progress bound:**
  - The worker's tracking issue records an attempt count beside ownership:
    `Current ticket: #7 @ stage n @token <id> · attempts k`. It's in the issue, so it survives
    relaunch.
  - On self-recovery (CR-5), a session resuming the **same ticket at the same stage** increments
    `k`; **advancing a stage resets `k` to 0.**
  - At **`k = 3`** (≈4.5h of 90-min timeouts with zero stage progress): **park** the ticket —
    move it to board **Waiting/Blocked**, comment the reason on the work ticket (`parked: no
    stage-n progress after 3 attempts by <worker>`), clear `Current ticket`, and return to the
    pool. Waiting/Blocked drops it out of `ready` (CR-8), so **no other worker picks it up** — the
    cascade is cut at the first worker.
  - The parked ticket and its dependents then appear in the STUCK report (`#7 parked: no progress
    at stage n`), so once everything else is done the run trips and names the culprit instead of
    burning workers. A human unparks by moving it back to Up Next.
  - **Exemptions (U1, S1):** a session that ended in `LIMIT_WAIT` or while paused on an unreadable
    ownership recheck does **not** increment `k` — the loop/session records that end-reason in the
    tracking issue and the resuming session skips the increment. Blocked-by-environment is not
    wedged.
  - **Scope:** worker mode only. Legacy single-driver keeps today's behavior (`MAX_ITER` stops the
    loop), per CR-2.
  *Status: RESOLVED.*
- **S3 — RESOLVED (2026-09-24) — one issue per worker: shared `orchestration-worker` label, worker
  id in the title, dedupe scoped to its own name.** Problem: if worker issues kept the bare
  `orchestration-run` label, Step 0.5's COUNT≥2 dedupe (`SKILL.md:171-194` — "newest wins, close
  the rest") would have **every worker closing every other worker's live tracking issue** on each
  launch; and every other `orchestration-run` reader (`orchestrate-loop.sh:157/194/218/237`,
  `orchestrate-status.sh:19`, `monitor-v5/SKILL.md:30`) would see a mix. **Fix:**
  - **One issue per worker**, labelled **`orchestration-worker`** (shared by all workers), titled
    with the worker id and plan ticket: `Worker w2 — plan #40`. **Never** labelled
    `orchestration-run`.
  - **Body = the worker's scratch pad:** `Current ticket: #5 @ stage n @token <id> · attempts k`,
    `Run state:` (WORKING / WAITING / `LIMIT_WAIT` / …), last end-reason (for S2's exemptions), and
    a running **Tickets worked** list — the per-worker history.
  - **Find-or-create:** list open `orchestration-worker` issues (live REST list via label filter,
    `--limit 100`) and match the title on the worker id client-side (jq). Deliberately **not**
    `gh search` / title search — the search index lags, so a just-created issue could be missed and
    duplicated.
  - **Dedupe scoped to self:** Step 0.5's newest-wins rule applies only among open issues whose
    title carries **this** worker's id. A worker never closes another worker's issue.
  - **Liveness:** the loop's `❤ wK alive` comment lives on the worker's **own** issue, edited in
    place every TTL/4 — a comment, not the body, so the loop's pings never clobber the session's
    body writes.
  - **Enumeration:** reaper, deadlock trip, and aggregate status list `orchestration-worker` to see
    all workers, then filter to this plan's (title `plan #N`) — stale issues from another plan are
    ignored.
  - **Close-out:** when the plan ticket closes (C5), the cleanup owner closes all of that plan's
    worker issues; they stay as the run's history. Stale auto-id issues from loop restarts (CR-10)
    are closed then too.
  - **Rejected:** per-worker labels (`orchestration-run-<worker>`) — one new repo label per auto-id
    worker per run, which piles up; and a free-form "worker field" — no live filter for it.
  - **Legacy mode:** keeps `orchestration-run` and Step 0.5 byte-for-byte (CR-2).
  *Status: RESOLVED.*
- **S4 — RESOLVED (with B2) — worker-loop stops on the plan ticket closing.** In worker mode the
  loop's stop condition becomes **"the plan ticket is closed" (`RUN_COMPLETE`)**, not the
  `--label orchestration-run --state open` query (`:194/:218/:237`) — which is per-worker and would
  stop each worker when merely idle. A worker with no ready ticket **WAITS** (backoff-relaunch),
  because cleanup may inject work; it stops only when the plan ticket closes (done) or the STUCK trip
  fires. All workers stop together at close. (Legacy mode keeps the bare-label stop, CR-2.)
  *Status: RESOLVED.*
- **S5 — RESOLVED (2026-09-24) — one elected CI-repair owner; everyone else holds merges until
  `main` is green.** Today each merge spawns a background `ci-fix-v5` WATCH on *its own* merge SHA
  (`SKILL.md:1067-1090`); red → a background FIX agent (`:1092-1106`); FIX `Blocked` → orchestrator
  halt (`:1121-1127`, breaker list `:1135-1142`). Single-driver, the breaker is the fixer. In worker
  mode, A's merge breaks `main`; B and C then merge on top of red, their watchers see red too, and
  **three FIX agents race on the same breakage** with competing fixes, any of which can trip a halt
  on a worker that didn't cause it — and every merge onto red muddies attribution. The "two devs
  merging, git handles it" bullet covered merge-tree conflicts, not this post-merge shared fate.
  **Fix:**
  - **Elect one repair owner.** The first worker to observe red `main` appends `🔧 ci-repair <sha>`
    to the plan ticket; earliest comment ID wins (same handshake as tickets and `🧹 cleanup-claim`).
    Only the owner spawns `ci-fix-v5` FIX. A non-owner whose watcher reports red on a SHA covered by
    an open repair claim **does not spawn a FIX and does not halt** — it logs and defers.
  - **Merge hold.** While a `🔧 ci-repair` claim is open with no matching `✓ main green`, **no worker
    merges** a PR. Workers keep implementing, testing and opening PRs; they wait (backoff re-check)
    at the merge step only. The hold is part of the pre-mutation recheck (same read as S1 —
    unreadable → pause, never merge blind).
  - **Release.** When the owner's fix merges and CI on the new HEAD is green, the owner appends
    `✓ main green <sha>`; merges resume. Waiting workers rebase onto the new `main` before merging
    (M1).
  - **Owner death.** A repair claim is ownership like any other: a dead owner (stale liveness) drops
    out and the next worker to observe red becomes the earliest *live* claimant and takes it over.
  - **Repair fails** (FIX `Blocked`): the owner posts `⚠ halted — main red, needs human` to the plan
    ticket, and **all** workers stop relaunching (same park mechanism as STUCK) — a red `main` blocks
    everyone, so halting one worker would be meaningless. Plan ticket stays open.
  - **Waiting time is exempt** from the S2 no-progress bound (held at merge ≠ wedged).
  - **C5 interaction:** the elected cleanup owner's DS-112 deploy bar still queries `deploy.yml`
    authoritatively; an open `🔧 ci-repair` claim means not-at-fixpoint.
  - **Legacy mode:** unchanged (CR-2).
  *Status: RESOLVED.*
- **S6 — RESOLVED (2026-09-24) — batched scan reads (~3 calls/scan, flat in N), stretching idle
  backoff, and measured budget.** Problem: CR-4 budgeted writes only. A naive scan reads the plan
  ticket (paginated, growing all run) + each worker's issue *and* liveness comment (~N+1 calls) +
  the whole board (`gh project item-list --limit 1000`, `SKILL.md:293` — ~10 pages to learn the
  status of a handful of pool tickets). N workers each reading N workers' state → **~N²**, and idle
  WAITING workers pay it every backoff cycle for nothing. **Fix:**
  1. **Board read scoped to the pool.** One GraphQL query for the project Status of just the pool
     tickets (by issue number), not a full `item-list`. ~1 call instead of ~10. Worker mode only —
     legacy Mode Selection keeps its `item-list` (CR-2).
  2. **All workers in one read.** One GraphQL query returns every open `orchestration-worker` issue
     for this plan (S3) with its body and its `❤ alive` comment's `updatedAt`. 1 call instead of
     N+1 — this is what removes the N² term.
  3. **Stretching, jittered idle backoff.** A WAITING worker's backoff starts at ~5 min and grows
     toward ~15 min while nothing changes, with random jitter so idle workers don't re-scan in
     lockstep; it **resets to the short interval when a new `✓ completed` or `➕ pool` appears**
     (the only events that can make a ticket ready). Trade: an idle worker may notice new work a
     few minutes later, for far fewer idle reads.
  4. **Measure.** The loop's 45s heartbeat logs remaining REST + GraphQL budget from
     `gh api rate_limit` (that call doesn't count against the limit) to the run log. The first test
     run replaces the estimates below with real numbers.
  **Resulting estimate (ED-3 — unmeasured until #4 runs):** a scan is ~3 calls regardless of N
  (plan ticket + workers + pool status), so coordination cost is linear — workers × scans. Five
  workers all idle at a 5-min backoff ≈ 5 × 3 × 12 ≈ **~180 calls/hr** of a 5,000/hr budget, and
  less as backoff stretches. The dominant consumer remains the pipeline's own traffic (PRs,
  reviews, CI polling), which scales with N regardless of where coordination lives.
  *Status: RESOLVED.*
- **N1 — RESOLVED (2026-09-24) — one `ready` formula.** Every statement now reads `ready = pool −
  done − held − blocked`, blockers ⊆ `done` (Concepts, reaper, CR-5). Matters beyond tidiness: the
  `− blocked` term is what keeps parked tickets (human park, Blocked stage, S2, M1) out of
  circulation. *Status: RESOLVED.*
- **N2 — RESOLVED (2026-09-24) — board-trust wording.** "Not the board column" (reaper, CR-5) read
  as contradicting CR-8's Waiting/Blocked read. Reworded both to "the board is trusted **only for
  Waiting/Blocked**; ownership and completion never come from it." *Status: RESOLVED.*
- **N3 — RESOLVED (2026-09-24; upgraded from nit — it hid a real gap) — per-stage merge marker;
  honest residual.** `✓ completed` is posted at checkpoint (Stage 8), *after* all three of a
  ticket's PRs merge, yet the plan called it the "`✓ completed`-at-merge backstop" and relied on it
  to settle a takeover race ("first to post wins, other tears down"). Too late: in a takeover
  window both workers could already have merged their Stage-2 implementation PRs, putting two
  implementations of `#5` on `main`. The actual per-merge guard is the pre-mutation
  earliest-live-claim recheck (S1). Its gap: the incumbent is alive but its pings failed to land
  for > TTL, while the challenger's reads are healthy → each thinks it's the earliest live claim →
  both merge. **Fix:**
  1. **Wording:** the recheck is the per-merge guard; `✓ completed` only stops a finished ticket
     being re-worked. Corrected in the reaper, CR-3, CR-6 and the read-consistency caveat.
  2. **Per-stage marker:** immediately after merging a stage's PR, the worker appends
     `⛙ merged #5 · <impl|integration|ui> · w2` to the plan ticket. The pre-merge recheck also reads
     these; if the stage is already merged by anyone, the worker stands down and tears down its own
     branch/PR. Narrows the window to seconds (between another worker's merge and its marker);
     cannot close it — GitHub has no atomic check-and-merge.
  3. **Honest residual:** worst case is **rarely a duplicate merge of one stage**, which CI/review
     must catch — not "never a corrupted `main`" (CR-3's original claim, now corrected).
  *Status: RESOLVED.*
- **N4 — nit — refine citation drift + overstated payoff.** `## Dependency on` is at
  `refine-story-v5:321` (not :323) and the header is `## Dependency on {PREFIX}-{issue#}`. More
  substantively: that section is **optional** and **single-blocker-shaped**, so it can't express the
  many-to-many gate `#4 → #1,#2,#3` — CR-7's "declared edges" payoff (a) is **oversold**; the
  planner leans on *inference* (ED-1 risk) more than CR-7 implies. Confirm gate still covers it.
  *Status: OPEN.*
- **N5 — nit — re-planning closes the live plan ticket.** CR-9's newest-wins dedupe on
  `orchestration-plan` would close the *active* plan ticket if the planner is re-run mid-flight.
  Guard: never dedupe-close a plan ticket that has live claims. *Status: OPEN.*

### Added findings (post-round-2)

- **M1 — RESOLVED (2026-09-24) — in worker mode a merge conflict means rebase-and-retry, not halt.**
  Found while grounding S5: the circuit-breaker list (`SKILL.md:1138`) halts the orchestrator
  entirely on **"A PR merge conflict occurs."** Single-driver, conflicts are rare. With N workers
  merging into the same codebase they become routine, so each would halt a worker — contradicting
  §What-we-do-NOT-build's "git resolves it the same way (rebase / re-run CI)," which the skill does
  not actually do. **Fix (worker mode):**
  - PR not mergeable because `main` moved → **rebase the worker's branch onto `main`**, push
    (it's the worker's own worker-scoped branch — B1 — so force-push is safe), **re-run CI**, retry
    the merge (behind the S1/S5 recheck).
  - Rebase has **textual conflicts** → do **not** halt the worker: **park the ticket** (Waiting/
    Blocked + comment naming the conflicting files and the `main` commits involved), release it,
    and move on — same park path as S2. A human (or a later refined fix ticket) resolves it.
  - **Cap:** 3 rebase-and-retry cycles per merge (main keeps moving under a busy run) → then park.
  - Rebase/CI wait time is exempt from the S2 no-progress bound.
  - **Legacy mode:** keeps the halt (CR-2).
  *Status: RESOLVED.*

- **U1 — RESOLVED-IN-DESIGN (2026-09-24) — usage-limit wait.** Raised by the operator: a Claude
  usage-limit hit makes the loop relaunch instantly into the same failure until `MAX_ITER` trips
  (`orchestrate-loop.sh:251-264`) — a real bug today, amplified by N workers on one account. Fix:
  loop-level detection → `LIMIT_WAIT` → sleep to reset / hourly probe → resume via existing
  recovery; waits don't count toward `MAX_ITER`. Full spec in **Runtime piece #5**. Open item
  inside it: capture the real limit message before writing the detection pattern (ED-3).
  Constrains S2 and the deadlock trip (both must exempt `LIMIT_WAIT`). Built as part of this plan
  (build-order step 1), not as a separate change. *Status: RESOLVED-IN-DESIGN.*

---

## Suggested build order

Each step is independently useful.

1. **Worker-aware plumbing** (lock + tracking-issue identity + log/status keys) **+ usage-limit
   wait (U1)** — both are loop-level changes to `orchestrate-loop.sh`, so they land together. After
   this, N hand-launched workers with **manually disjoint `--tickets` scopes** coexist — parallelism
   with no coordination yet (the "just tell one to run `#1,#3` and another `#2`" case) — and none
   of them dies on a usage limit.
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
- `orchestrate-loop.sh` / `orchestrate-status.sh` — patched (incl. U1 `LIMIT_WAIT`).
- `orchestrate-plan-v5` — one new skill, joins the v5 family.

Cutting a v6 would force re-versioning and re-syncing all thirteen skills for zero contract change —
pure churn — and would spoil the clean "v5 is the only synced generation" state. Reserve v6 for the
next time the **testing model or core pipeline contract** actually changes (the same trigger that
justified v5). This is an in-place v5 upgrade.
