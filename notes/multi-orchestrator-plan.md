# Multi-Orchestrator Plan

> **Purpose:** let **several orchestrators run at the same time against one repo, each in its own
> clone** (normally one clone per computer), each driving its own independent run. No shared pool, no claims, no coordination
> between runs. The operator decides up front which tickets go to which machine.
> **Created:** 2026-09-26. **Last updated:** 2026-09-27.
> **Status:** BUILDING (2026-09-27). All decisions D1–D8 resolved. Cold read round 1 (2026-09-26): F1–F4 resolved, F5 skipped, F6 accepted, F7 resolved, F8 accepted, F9–F10 resolved, F11 accepted, F12 fixed. Round 2 (2026-09-27): G1–G9 recorded with fixes. Round 3 (2026-09-27): H1–H9 resolved (fixes folded
> in).
> Ships as a **v6 skill generation** (decided 2026-09-26 — see Versioning).
> **Supersedes:** [parallel-orchestration-plan.md](parallel-orchestration-plan.md) (suspended
> 2026-09-26). That plan's shared-pool design kept producing new blockers from its own mechanisms
> (three cold-read rounds). This plan drops the coordination layer entirely.
> **Principle:** a run is identified by **its tracking issue number, given explicitly**. The
> orchestrator never discovers a run, and never looks at the board for work.

---

## The idea in one paragraph

Today there is at most one active run per repo: the orchestrator finds "the" open
`orchestration-run` issue and uses it. This plan makes the run **explicit**. You either give the
orchestrator a ticket list (it starts a **new** run for exactly those tickets) or a run number (it
**continues** that run). The run number is held in an env var for the life of the loop, so every
relaunch works the same run. Two machines given two different ticket lists run two independent runs
side by side. Nothing coordinates them; the operator keeps them from overlapping by how they split
the tickets.

---

## Deployment topology

**One orchestrator per clone.** The unit is a checked-out copy of a repo, not a computer. Running
several orchestrators on one computer or in one container is normal and stays supported: today the
operator runs orchestrators for **different repos** side by side in the same container. Nothing in
this plan may assume there is a single place per machine to run orchestration or its tooling.

For **one repo**, parallel runs each use their own clone. The expected setup is one clone per
computer, but two clones of the same repo on one computer are not a problem in principle: separate
folders and separate processes, sharing only what separate machines would share anyway.

What parallel runs of the same repo share: the **remote repo, the GitHub Project board, the issues,
the self-hosted CI runner(s), and `main`**.

**One current snag, to fix in the v6 loop:** the loop's lock file and log file are named after the
project **folder name** only (`orchestrate-loop.sh:108,139`, both
`${TMPDIR:-/tmp}/orchestrate-loop-$(basename "$PROJECT_DIR")`). Two clones of the same repo with the
same folder name on one machine (e.g. `/a/heycapto` and `/b/heycapto`) share one lock, so the second
refuses to start (exit 4). Nothing is damaged, but it blocks. Different folder names already work.
Fix: key the lock and log on the full project path (or a hash of it) instead of the folder name.
This is also safe for different-repo runs in one container, which have distinct paths.

---

## Launch modes (the whole contract)

| Launch | Behavior |
|---|---|
| `--tickets "#7,#8,#9"` | **Start a new run.** Create a new `orchestration-run` issue with `Scope: #7,#8,#9` (order preserved, as today), export its number, run it. |
| `--run 123` | **Continue run #123.** Check that #123 exists, is **open**, and is labeled `orchestration-run`. If so, export it and run it. If not, refuse and say why (not found / closed = already complete / not a run issue). |
| neither | **Refuse:** "No run and no tickets given. Pass `--tickets` to start a run or `--run` to continue one." Exit without launching a session. |
| both | **Refuse:** "Pass `--tickets` or `--run`, not both." Exit without launching a session. |

Rules:
- **No discovery.** The orchestrator never searches for an open run and never reads the board to
  find work. The only sources of scope are `--tickets` (new run) or the run issue's `Scope:` field
  (existing run).
- **`--run` is also how you resume** after anything that stops the loop: Ctrl-C, a crash, the
  `MAX_ITER` circuit breaker, a milestone `AWAITING_HUMAN` pause. The loop prints the run number at
  startup and on exit so it's easy to copy.
- **Refusals happen in the loop, before any `claude -p` session**, with a non-zero exit code.
- **Full-board mode is removed.** Today a launch with no ticket list means "all Up Next"
  (`SKILL.md:70`, `:76`, `:298`, `:313`). That path goes away. This is a deliberate behavior change.

---

## Changes to build

### 1. Loop: flags, run creation, run binding (`developer-tools/orchestrate-loop.sh`)

- Add `--run N`. Enforce the four-way rule above after argument parsing (`:82-94`).
- Key the lock file and run log on the full project path, not its folder name (`:108`, `:139`;
  see Deployment topology).
- **`--tickets`:** the loop creates the run issue itself, before the first session, so the number is
  known from the start (see D1 for the body). Then `export ORCHESTRATE_RUN=<number>`, same mechanism
  as `ORCHESTRATE_N` (`:135`).
- **`--run`:** validate, then `export ORCHESTRATE_RUN`.
- **Scope-overlap guard (new-run only):** before creating, read the `Scope:` of every other open
  `orchestration-run` issue. If any ticket in `--tickets` is already in another open run's scope,
  refuse and name the ticket and run. This is the one check that stops two machines working the
  same ticket.
- Replace every "the open run" query with the bound issue:
  - heartbeat `:157` → read `#$ORCHESTRATE_RUN`
  - pre-session open check `:194` and post-session stop check `:218` → "is `#$ORCHESTRATE_RUN`
    closed?" (closed = fixpoint = stop). The `saw_issue` bookkeeping (`:178`, `:189-196`) goes away:
    the issue always exists before the first session.
  - `AWAITING_HUMAN` check `:237` → read `#$ORCHESTRATE_RUN`
- Prompt (`:129-131`): pass the run number, drop the "find-or-create" wording.
- Header/usage text (`:2-56`) rewritten to match, including the stop condition and the
  "loop holds no run state" claim (it now holds the run number, by design).

### 2. Skill: run binding (`skills/orchestrate-v5/SKILL.md`)

- **Parse Arguments (`:65-76`):** grammar changes to match the launch modes, for both loop and
  interactive launches (see D2 for how an interactive session names an existing run).
- **Step 0.5 (`:164-194`):** remove find-or-create and the COUNT ≥ 2 rule. As written today, the
  COUNT ≥ 2 rule ("close the stale older one(s)", `:185`) would **close the other machine's live
  run**. Replacement: load `#$ORCHESTRATE_RUN`. If unset (interactive direct run), follow the same
  four-way rule itself: tickets → create a new run; run number → load it; neither/both → refuse.
- **Step 0.6 crash recovery (`:229`)** is board-wide today ("Find tickets left at Status In
  Progress") and would reset the **other run's live ticket** to Up Next. Scope it to tickets in
  this run's `Scope:`. The rest of 0.6 (`:230-231`) already reasons per scoped ticket.
- **Mode Selection (`:280-307`) / WORKING (`:313`):** delete the `full board` branches.
- **Step 0.0 (`:80-86`):** still correct (the loop's own lock is its own run); reword the Step 0.5
  reference.
- **Stage 2d follow-up injection (`:470-476`):** append the follow-up to the `Scope:` field, as
  C4 does (`:980`), not just the session's in-memory ticket list (G5). Without full-board mode,
  an in-memory-only follow-up is lost when the session exits.
- **CLEANUP C1 dispatch (`:946-947`):** no change (F8). It takes the latest `ui-tests.yml` run on
  `main` as "my run", which may be the other run's near-simultaneous full-suite dispatch; that
  result is equally valid (same suite, same `main`, same moment).
- **C5 close (`:1005`):** reword "the next relaunch finds no open `orchestration-run` issue" to "the
  loop sees `#$ORCHESTRATE_RUN` closed".
- **Tracking-issue body schema (`:1033`):** `Scope:` loses the `full board` option.
- **Merge gate (`:47-61`):** before `gh pr merge`, bring the branch up to date and re-test if
  `main` moved (F1-A); check `main` first — red `main` → wait, then update-and-re-test (D3, G2);
  red `main` with no fixer → start ci-fix FIX (G1, H1); merge conflict while updating → D4 (H8).
- **Circuit breakers (`:1135-1144`):** "merge conflict" (`:1139`) halts only after D4's one
  automatic attempt fails; "build fails on main" (`:1140`) is no longer a halt on its own (D3). (H8)
- **Stage 2d existing follow-ups (`:464-466`):** overlap check before appending to `Scope:` (H3).
- **CLEANUP C4 (`:978-980`):** dedupe fix tickets by test name, wait only on another open run's
  ticket (D3, H2).
- **`ci-fix-v6/SKILL.md`** (H8): run-number input and `fix/ci-{run}-…` / `fix/ci-manual-…` branch
  names (G6, H6); open-fix-PR check at start and before push (D3, G6); pre-merge re-check (H5);
  WATCH follows the latest non-cancelled run on `main` (G3, H7); F7 waits for checks to finish, no
  10-min cap (D5); abandoned-fix rule (D3, F7).

### 3. Observability (`developer-tools/orchestrate-status.sh`, `skills/monitor-v5/SKILL.md`)

- `orchestrate-status.sh:19` and `monitor-v5/SKILL.md:30` pick `.[0]` of the open runs. With no
  argument they should **list all open runs** (number, scope, current ticket); with a run number,
  show that one.

### 4. Docs and templates

- `templates/scripts/orchestrate-v6.sh` (new, D7) usage lines: no no-arg "full board" example
  (the v5 wrapper's `:9-15` stays as is).
- **Deferred to v5 retirement (2026-09-27):** shared standards keep their v5 wording so v5
  sessions read exactly what they read today; the v6 rules live inside the v6 skills. At cutover:
  - `standards/project-tracking.md:50-55` ("One active run = one open issue…", find-or-create by
    label) rewritten for many open runs, each bound by number.
  - `standards/project-tracking.md:57` (queue = all of Up Next; crash recovery resets every In
    Progress) reworded for scoped runs (F10).
  - `standards/project-tracking.md:89-91` session-start protocol ("pick up In Progress items"):
    an In Progress ticket in an open run's scope belongs to that run — don't pick it up (F10).
- `orchestrate-v6/SKILL.md` copies of `:166` and `:171` ("the loop never touches it", "never a run
  ID the loop would have to hold") rewritten; both are false in v6 (F10).
- v6 loop's `--status` execs `orchestrate-status-v6.sh`, not the v5 script (`orchestrate-loop.sh:100`,
  F10).
- `templates/workflows/integration-tests.yml:4-6` header: drop the nonexistent
  `setup-branch-protection.sh` reference; describe F1-A instead.
  - `workflow/agentic-development-workflow.md` / `workflow/README.md`: "one active run" and
    full-board wording.
- **Shared workflow templates** (`templates/workflows/`) do change now (F1-B push trigger, header
  rewrite). Only projects created after this pick them up (sync is skip-if-exists); for a v5
  project that just means tests also run on `main` after a merge, which v5's CI watcher already
  expects (`ci-fix-v5/SKILL.md:63`).

### 5. Usage-limit wait (`LIMIT_WAIT`), carried over from the old plan's U1

A real bug today, independent of parallelism: when a session hits the Claude usage limit,
`claude -p` exits fast, the loop treats it as a crash and relaunches immediately
(`orchestrate-loop.sh:251-258`), and burns all `MAX_ITER` relaunches in minutes (`:261-264`). Two
machines on **one Claude account** hit the limit sooner and together. Fix, in the loop:
- **Detect** from the session output: a case-insensitive text match on `429`,
  `rate_limit_error`, or "usage limit" / "rate limit" (operator-supplied, 2026-09-27). The match
  lives in bash because the session is already dead when this happens, and asking Claude to
  classify the error would hit the same limit. Don't key on exit code alone. A message that
  doesn't match just falls through to today's crash-relaunch behavior; add new wording to the
  match when it's seen.
- **Wait** until the reset time if the message gives one (plus jitter), else probe hourly. Waits do
  not count toward `MAX_ITER`.
- **Surface** `Run state: LIMIT_WAIT (retry ~HH:MM)` in the run issue; clear it on resume.
- **Resume** through the normal Step 0.6 recovery.

**v6 loop only** (D6 reversed 2026-09-27); the v5 loop is not changed.

---

## Planning the split: `plan-batches-v6` skill (decided 2026-09-26)

A small, **read-only** v6 skill that is essentially a saved prompt: *"here are my tickets and how
many orchestrators I'll run — give me the batches."* It exists so the batching rules below are
applied the same way every time instead of being re-remembered in an ad hoc prompt. Name is a
working title.

**It carries the rules itself.** It does not read `orchestrate-v6/SKILL.md` to work out how the
orchestrator behaves (1,200+ lines, almost all pipeline mechanics); the few rules that matter for
batching are written into the skill.

**Inputs:**
- A ticket list (required).
- Number of orchestrators — **defaults to 2**. Asking for batches implies more than one; override
  with any N ≥ 2.

**What it does:**
1. Reads every ticket in full. Dependencies come from what the tickets declare plus its own
   reading of them (see D8 for where declared dependencies actually live today). **Declared
   dependencies are always honored**; it may add ones it infers, never drop a declared one.
2. **Unrefined tickets → warning, not a halt.** Flag them in the output and batch them anyway (you
   may want a rough split before refining).
3. Builds batches under the rules below and balances them by **rough size, not ticket count**.
4. Checks open `orchestration-run` issues and refuses to put a ticket that's already in a running
   run's `Scope:` into a batch (names the run instead).
5. **Self-checks the split before printing (ED-2):** no dependency crosses batches, every ticket
   appears exactly once, each milestone comes after its stories.

**The batching rules:**
- **A dependency must never cross batches.** Nothing orders work between machines, so if #8 needs
  #7, both go in the **same** batch with #7 first. Order within a batch is the processing order
  (the orchestrator works `Scope:` left to right, `SKILL.md:313`).
- **Milestone tickets.** A milestone gate (`SKILL.md:329-346`) fires when its run reaches it. If the
  milestone's stories are spread across batches, it fires before the others finish. Put it last in
  a batch that contains all its stories, or hold it out as its own follow-up run and say so.
- **Shared-file hot spots.** Tickets that will clearly touch the same files go in one batch, to
  avoid merge conflicts (see D4).
- **If the tickets can't be parallelized** (one long chain), say so plainly: the honest answer may
  be fewer batches than asked for.

**Output:** one paste-ready `./scripts/orchestrate-v6.sh --tickets "..."` line per batch (v6
wrapper, D7 — H4), each with a
one-line reason for its grouping and order, then any warnings (unrefined tickets, hot spots,
lopsided split, milestone held out).

**Does not:** create run issues, launch anything, or write to GitHub. The loop creates a run when
you launch a batch. You reviewing the batches is the confirm step.

---

## Open decisions

- **D1 — Who creates the run issue, and who writes its body? RESOLVED (2026-09-26).**
  - **Looped runs: the loop creates the issue** before the first session. Why: the loop has to
    know the exact number to relaunch into the same run. If a session created it and passed the
    number back, a first session that crashed after creating the issue but before handing the
    number over would leave the loop relaunching with `--tickets` again → a second, duplicate run.
  - **The loop writes a minimal body:** `Scope:`, `Run state: WORKING`, the operator slot set
    to `none`, and the `**Mode (last session):** —` line right after the slot (it ends the slot for
    Step 0.55's parser, `SKILL.md:216` — G4). The first session fills in the full schema (`SKILL.md:1010-1051`). That keeps the
    schema in one place (the skill) and is barely a change: the skill already rewrites the body
    every session as read-modify-write (Step 0.55).
  - **Interactive runs** (skill launched directly, no loop) create the issue themselves, full
    body, exactly as today.
- **D2 — How does an interactive session name an existing run? RESOLVED (2026-09-26): same words
  as the loop.** Only affects interactive runs; looped runs get the number from `ORCHESTRATE_RUN`
  (D1). Today a bare number is always a ticket (`SKILL.md:71`), and that stays true.
  - `orchestrate-v6 supervised --run 123` → continue run #123.
  - `orchestrate-v6 supervised #7,#8,#9` → new run, as today; `--tickets "#7,#8,#9"` also accepted.
  - Neither / both → the same refusals as the loop.
  - `ORCHESTRATE_RUN` set (the loop is driving) → arguments are not used to pick the run.
  - **Operator rule: one driver per run.** Nothing stops two drivers working the same run (a loop
    on one machine plus an interactive `--run` on another, or `--run 123` launched twice); both
    would work the same tickets. A guard would need a "who's driving" liveness signal, which is
    the machinery this plan dropped, so this is a documented rule, not a check.
- **D3 — Red `main` is shared. RESOLVED (2026-09-26): one fixer at a time; everyone else waits.**
  The problem: when run A breaks `main`, run B works on top of it and (1) B's watcher also sees red
  and starts a second ci-fix FIX for the same breakage (`SKILL.md:1097-1111`; FIX branches
  `fix/ci-{description}`, opens and merges its own PR, `ci-fix-v5/SKILL.md:161-168`, `:237`);
  (2) B's own PR inherits the red and the merge gate sends it to FIX (`SKILL.md:58`), so B may
  patch A's bug inside B's ticket; (3) both runs' CLEANUP inject a fix ticket for the same red UI
  test (C1/C4, `:951`, `:978-980`).
  - **Who's fixing = an open `fix/ci-*` PR.** No registry, no claims: the open PR on GitHub *is*
    the signal, visible to every orchestrator. ci-fix FIX checks for one at start and again right
    before pushing its branch (G6). If one exists, it waits for that PR to merge or close, then
    re-checks `main`: green → done; still red → it takes its turn.
  - **Fix branch names carry the run number** (`fix/ci-{run}-{description}`), so two fixers never
    push the same ref (G6). The orchestrator passes its run number when it starts a fix (watcher
    spawn `SKILL.md:1099-1105` and the merge-gate spawn); standalone ci-fix, which has no run, uses
    `fix/ci-manual-{description}` (H6).
  - **Before merging its own PR, ci-fix re-checks (H5).** ci-fix merges directly
    (`ci-fix-v5/SKILL.md:237`), outside the orchestrator's merge gate. So before merging: if any
    other `fix/ci-*` PR was opened **or merged** since this fix started, close this PR and re-check
    `main` instead (covers "the lower one already merged"); otherwise apply F1-A's
    bring-up-to-date-then-re-test step, then merge.
  - **Abandoned fix.** Normally the fixer finishes: the orchestrator drains its FIX agents before
    closing a ticket (`SKILL.md:1129-1131`). But a crashed or timed-out session can leave a fix PR
    open with nobody behind it. Rule: a fix PR with **no activity for ~30 min** (no new commits,
    comments or check runs, and no checks queued or running — F7) counts as abandoned; the waiter comments on it, closes it, and takes
    its turn. Closing an automated fix PR is reversible. *The 30-min figure is a starting guess.*
  - **Merge gate checks `main` first.** A PR that's red while `main` is also red isn't at fault: wait
    for `main` to go green, then bring the PR branch up to date with `main` and wait for its checks
    again (F1-A's step — a plain re-run would re-test the old red merge commit, G2). Only a PR that's
    red on a green `main` goes to FIX.
  - **The merge gate starts the fix if nobody has (G1).** If it sees red `main` and no open
    `fix/ci-*` PR, it starts ci-fix FIX itself rather than just waiting. The watcher can miss a red
    `main` (15-min timeout, `ci-fix-v5/SKILL.md:76`; no watcher after a ci-fix merge,
    `SKILL.md:1071`), and without this every run would wait forever. The open-PR check keeps it to
    one fixer. **It also checks this session's own pending fixes** (`session_metrics.ci_fixes[]`)
    and waits on one if it exists: a background fix spends a while diagnosing and testing before it
    opens a PR (`ci-fix-v5/SKILL.md:130-197`), and in that window there's no PR to see (H1).
  - **"Is `main` red?" means the latest non-cancelled run on `main` (G3).** The workflows cancel an
    in-progress run when a newer push arrives (`fast-tests.yml:18-20`, `integration-tests.yml:15-17`),
    so a merge's run can end `cancelled`. Treat `cancelled` as superseded and follow the **latest
    non-cancelled run of that workflow on `main`** (not a run on the same commit — the newer run is
    on a newer commit, often the other run's merge). If that run is still queued or running: wait.
    ci-fix WATCH does the same; today it looks runs up by merge commit and handles only
    success/failure (`ci-fix-v5/SKILL.md:50`, `:71`, `:82-105`) (G3, H7).
  - **One halt condition.** "Build fails on main" (`:1140`) stops being a halt on its own; red
    `main` routes to the single fixer. The halt stays on "CI fix reports Blocked" (`:1142`).
  - **CLEANUP dedupes by test name.** Injected fix tickets name the failing test in the title.
    Before injecting, CLEANUP looks for an open ticket for that test. If one exists **and is in
    another open run's `Scope:`**, it doesn't create another, stays open (not at fixpoint), and
    re-checks next CLEANUP pass. If one exists but **no open run owns it** (e.g. left over from a
    finished run — the pilot's #389, `SKILL.md:935`), it appends that ticket to this run's `Scope:`
    and works it (H2). "If you
    see it, you own it" still holds: owning means not closing until it's green.
  - **Accepted cost:** a run waiting on another run's fix keeps relaunching CLEANUP, re-running the
    full UI suite each pass. If that bites, add a WAITING-style backoff.
- **D4 — Merge conflicts. RESOLVED (2026-09-26): one automatic attempt, then halt.** Today any
  merge conflict halts the whole run (`SKILL.md:1139`); nothing in the skills rebases or resolves
  (grounded: no other conflict/rebase handling in orchestrate, implement, integration-test or
  ui-test). Two runs merging to `main` makes conflicts more likely.
  - **On a conflict:** the agent merges the latest `main` into its branch (no rebase, no
    force-push — same as F1-A, G7), resolves the conflicts, re-runs build and tests, pushes, and sends the PR back through the normal merge gate (checks
    must pass again). One attempt per merge.
  - **If it can't resolve cleanly, or tests fail after resolving:** halt the run as today. You
    resolve, then resume with `--run`.
  - **Halt the run, don't skip the ticket.** A batch is an ordered chain; later tickets may depend
    on the stuck one, so skipping ahead is unsafe.
  - A good batch split (shared-file hot spots in one batch) still keeps conflicts rare.
- **D5 — Self-hosted runner contention. RESOLVED (2026-09-26): waiting in line is not "runner
  down".** The standard setup is one self-hosted runner per repo
  (`developer-tools/self-hosted-runner-setup.md:7`, `:132-133`); a runner does one job at a time, so
  two runs' jobs take turns. Safe, just slower. The problem is waits that give up too early while
  queued behind the other run:
  - **C1 runner-down halt** (`SKILL.md:941`): a UI run still queued after ~15 min is treated as
    "runner down" → halt. Change: halt only if queued ~15 min **and no other job is running on the
    self-hosted runner** (checked via the repo's in-progress runs). Busy → keep waiting.
  - **ci-fix F7** (`ci-fix-v5/SKILL.md:226-233`): polls the fix PR's checks for at most 10 min, and
    a still-pending result is not handled. Change: wait until the checks are terminal, the same way
    the merge gate does (`gh pr checks --watch`, `SKILL.md:52`).
  - **ci-fix WATCH timeout** (`ci-fix-v5/SKILL.md:76`, 15 min → `STATUS: Timeout`): unchanged; it's
    informational only (`SKILL.md:1113-1115`).
  - **Warning (document in the runner setup guide):** don't add a second runner **on the same
    machine**. The UI tier starts the app on fixed ports (`templates/workflows/README.md:31`, 5001 /
    5002), so two UI jobs at once on one host would collide. A second runner on a **different**
    machine is fine and is an optional speed-up for parallel runs.

- **D8 — Dependencies aren't recorded consistently.** Grounded 2026-09-26:
  - `prd-to-backlog-v5` records **no** dependencies; it only orders stories within a milestone
    (`prd-to-backlog-v5/SKILL.md:120`, `standards/story-writing-standards.md:121`). Milestone
    membership is recorded as sub-issue links (`standards/project-tracking.md:59-78`).
  - `add-story-v5` asks for dependencies and shows them in its preview (`**Dependencies:**`,
    `add-story-v5/SKILL.md:116`), but the issue body it creates has **no dependencies section**
    (`:156-200`), so what the human confirmed is dropped when the ticket is saved.
  - `refine-story-v5` asks about cross-story dependencies (question K, `:176`) and writes an
    optional `## Dependency on {PREFIX}-{issue#}` section (`:321-323`), free-text and shaped for a
    single blocker.

  So today the batching skill mostly **infers** dependencies.

  **RESOLVED (2026-09-26): one `## Dependencies` section, same format everywhere, in v6.**
  - **Format** (in the issue body):
    ```markdown
    ## Dependencies
    - #7 — needs the Orders table and repository from #7
    - #9 — reuses the checkout screen #9 adds
    ```
    or `None` when there are none. One line per blocker: issue number, then a short reason. The
    section is always present, so "no dependencies" is stated rather than implied by absence.
  - **Writers:**
    - `prd-to-backlog-v6` writes it for every story it creates, from the same analysis it uses to
      order stories within a milestone.
    - `add-story-v6` writes the dependencies it already asks for and shows in its preview (the fix
      for today's drop). `reconcile-backlog-v6` creates stories through add-story, so it inherits
      this.
    - `refine-story-v6` replaces the free-text `## Dependency on {PREFIX}-{issue#}` section with
      this one, keeps it up to date from question K, and adds anything it finds.
    - `triage-v6` writes it too. It creates its bug tickets directly with `gh issue create`
      (`triage-v5/SKILL.md:178-239`), not through add-story, so it doesn't inherit the fix.
    - Tickets created mid-pipeline also get it, usually listing their parent:
      `implement-ticket-v6` scope-deferral follow-ups (`implement-ticket-v5/SKILL.md:71-76`),
      `orchestrate-v6` Stage 2d UI follow-ups (`orchestrate-v5/SKILL.md:463-478`) and CLEANUP C4
      fix tickets (`:978-980`, often `None`).
  - **Reader:** `plan-batches-v6` treats listed dependencies as binding and still infers extra
    ones. Tickets without the section (anything created before v6) fall back to inference.
  - **Not doing now:** GitHub's native "blocked by" issue relationships. Could be added later as a
    second, UI-visible copy. *Hypothesis (ED-3): the feature exists and is reachable via the API;
    not verified.*

---

## Cold-read findings (round 1, 2026-09-26) — work one at a time

A fresh subagent read the plan against the repo (ED-5). ~55 citations checked; one drifted (F12).
Each finding below was re-checked against source before recording. Status: all worked through
(2026-09-27) — see each item.

- **F1 — BLOCKER — no "`main` is red" signal; PRs merge on stale green.** The test workflows run
  only on `pull_request` (`templates/workflows/fast-tests.yml:15-17`, `integration-tests.yml:11-13`);
  nothing runs tests on a push to `main`. `integration-tests.yml:4-6` assumes strict branch
  protection (PR must be up to date with `main`) via `developer-tools/setup-branch-protection.sh`,
  which doesn't exist; `CLAUDE.md` step 6 says no branch protection is needed. So run A's PR goes
  green against an older `main`, run B merges, A merges, and the combination breaks with no test
  catching it. D3's "is `main` red?" has nothing to read: ci-fix WATCH looks for runs on the merge
  SHA (`ci-fix-v5/SKILL.md:48-63`) and finds none (only `deploy.yml`, if a project has one).
  Pre-existing in v5; two runs make it much more likely.
  **RESOLVED (2026-09-27): both parts.**
  - **A — re-test before merging if `main` moved.** In the merge gate (`SKILL.md:47-61`), right
    before `gh pr merge`: if `main` has moved since the PR's checks ran, bring the PR branch up to
    date with `main`, push, and wait for `fast-tests` / `integration-tests` to pass again, then merge.
    A conflict while updating → D4 path (one automatic resolve attempt, then halt). Done by the
    orchestrator, not GitHub branch protection, so `CLAUDE.md` step 6's "no branch protection
    needed" stays true. *To verify at build time (ED-3): `gh pr update-branch` exists and does a
    merge-from-`main` without force-push.*
  - **B — run the tests on `main` after every merge.** Add `push: branches: [main]` to
    `templates/workflows/fast-tests.yml` and `integration-tests.yml`. This is D3's "`main` is red"
    signal and gives ci-fix WATCH runs to watch. It catches the leftover race (two merges seconds
    apart) that A can't close.
  - **Costs:** more runner time (a run per merge plus occasional pre-merge re-tests), so more
    queueing on a one-runner repo. Existing projects don't get B automatically (workflows are
    skip-if-exists), so it goes on the **v6 migration checklist** (see Versioning).
  - The stale `setup-branch-protection.sh` reference in `integration-tests.yml:4-6` gets rewritten
    to describe A.
- **F2 — BLOCKER — v5 and v6 on one repo wreck each other.** Both use the `orchestration-run`
  label. A v5 session closes older open run issues (`orchestrate-v5/SKILL.md:185`) and resets every
  In Progress ticket on the board (`:229`). The v5 lock is keyed on folder name
  (`orchestrate-loop.sh:108`) and v6 on full path, so both can run together. D7's "switching back is
  equally easy" invites mixing.
  **RESOLVED (2026-09-27): not a real scenario — operating rule, no mechanism.** The operator
  doesn't mix generations: moving a repo from v5 to v6 is a one-way cutover between runs, and v5 is
  then left alone (archived). Rule, stated in the v6 docs and the migration checklist: **a repo runs
  v5 or v6, never both; finish (or close) any open v5 run before the first v6 launch.** v6 keeps the
  shared `orchestration-run` label. D7's "switching back" wording is replaced with "one-way
  cutover".
- **F3 — SHOULD-FIX — build order stale.** Step 5 says "D3 / D5 guards, once decided" (both now
  resolved); D4 is in no step; the order doesn't say when running two at once becomes safe (needs
  run binding, 0.6 scoping, overlap guard, D3, D4, D5).
  **RESOLVED (2026-09-27):** build order rewritten as a table grouped by what each step makes safe;
  everything needed for two-at-once is in step 3, with an explicit "don't run two before step 3".
- **F4 — SHOULD-FIX — scope can grow without the overlap guard.** The guard runs only in the loop
  at creation. Bypasses: operator slot "add #12,#13" appends to `Scope:` (`SKILL.md:220`);
  interactive runs create their own issue (D1); Stage 2d follow-ups (`:470-476`); two launches
  racing (check-then-create).
  **RESOLVED (2026-09-27):**
  - **The skill runs the same overlap check** whenever it creates a run (interactive) or adds
    tickets to one (operator slot). On an add, overlapping tickets are not added; the
    `✉ operator message handled` comment says which and which run owns them.
  - **Re-check right after creating a run** (loop and skill). If another open run now overlaps, the
    newer run (higher issue number) closes itself with a `⚠ closed — scope overlap with #N` comment
    and refuses to start. Closes the same-moment race. `--run` on such an issue says "closed over a
    scope overlap with #N", not "already complete" (G9).
  - **Follow-up / fix tickets the run creates itself** (Stage 2d auto-create, implement deferrals,
    C4): no check. Rejected as a risk: they're brand-new, so no other run can own them; duplicate
    cleanup fixes are covered by D3's dedupe by test name.
  - **Exception — an existing follow-up Stage 2d picks up** ("If a follow-up ticket exists",
    `SKILL.md:464`, `:466`) wasn't created by this run and could be in another run's scope. It gets
    the overlap check before being appended to `Scope:` (H3).
- **F5 — SKIPPED (2026-09-27, operator: overcomplicating it).** D5 stays as decided.
  Original finding: **D5's "runner busy?" check is blind to shared runners.** "The repo's
  in-progress runs" can't see an org-level runner or one busy with another repo's job
  (`SKILL.md:941`; `self-hosted-runner-setup.md:132-133`).
- **F6 — ACCEPTED, no change (2026-09-27).** Each waiting pass re-runs the full UI suite, so 50
  passes take many hours; the other run's fix lands long before. Running out only happens if the
  owning run is stuck or halted, and then stopping is right (a human is needed; resume with `--run`).
  Original finding: **a run waiting on another run's fix burns `MAX_ITER`.** D3's CLEANUP dedupe
  re-checks each pass, and each pass is a relaunch counted toward `MAX_ITER=50`
  (`orchestrate-loop.sh:73`, `:261-264`) → circuit breaker. If the owning run is parked or halted,
  the waiter can never finish. Needs a waiting state that doesn't count (like `LIMIT_WAIT`) and a
  clear halt when the owner isn't progressing.
- **F7 — SHOULD-FIX — the 30-min abandoned-fix rule can close a live fix.** A fix PR whose checks
  are queued behind the other run's UI suite shows no commits/new check runs for 30+ min (D3 + D5).
  Count queued / in-progress checks as activity.
  **RESOLVED (2026-09-27):** a fix PR with checks queued or running counts as active; it's abandoned
  only after ~30 min with no new commits **and** no checks queued or running. D3 updated.
- **F8 — SHOULD-FIX — C1 run-id fix needs a template change.** A run-name input means editing
  `templates/workflows/ui-tests.yml` (no `run-name` today, `:14-33`); existing projects keep their
  local copies (sync is skip-if-exists, `CLAUDE.md` step 6). Matching on dispatch time is weak when
  both runs dispatch unfiltered on `main`. Add to §4 plus migration notes.
  **ACCEPTED, no change (2026-09-27).** Only C1 can mix up: per-ticket UI dispatches run on the
  ticket's own branch (`ui-test-v5/SKILL.md:250-255`). If A picks up B's run, it's a full-suite
  run on `main` from the same moment, so its result is just as valid for A (red → A still owns it
  until green). Rare and harmless; not worth a template change and migration step.
- **F9 — SHOULD-FIX — loop-created issue details.** The label may not exist yet (skill creates it
  today, `SKILL.md:175`); the minimal body must use the exact operator-slot markers Step 0.55
  parses (`:216`); `Scope:` may hold Story IDs (`SF-7`, `:70`), so normalize to issue numbers for
  the overlap check; a `gh` error on "is #N closed?" must not read as closed (today's `*)` case,
  `orchestrate-loop.sh:247-248`).
  **RESOLVED (2026-09-27), all four as build details:**
  1. The loop creates the `orchestration-run` label first (ignore "already exists"), as the skill
     does today (`SKILL.md:175`).
  2. The minimal body copies the operator-slot heading word for word (`### 📨 Operator message …`)
     so Step 0.55 finds it (`SKILL.md:216`).
  3. **`--tickets` takes issue numbers only** (`#7` or `7`); `Scope:` always stores issue numbers.
     Interactive runs may still take Story IDs; the skill converts them first (Step 0d).
  4. A `gh` error on "is the run closed?" is never read as closed: keep today's
     couldn't-read → relaunch behavior (`orchestrate-loop.sh:247-248`).
- **F10 — SHOULD-FIX — more docs to update.** `standards/project-tracking.md:57` (queue = Up Next;
  crash recovery resets In Progress) and `:89-91` (session start picks up any In Progress item —
  the other machine's ticket); `SKILL.md:166,171` ("loop never touches it", "never a run ID the loop
  would have to hold"); the v6 loop's `--status` must exec the v6 status script
  (`orchestrate-loop.sh:100`).
  **RESOLVED (2026-09-27):** all four added to §4.
- **F11 — NIT — C5 deploy check with two runs.** `gh run list --workflow deploy.yml -L1` against a
  `main` the other run keeps moving (`SKILL.md:990-993`) is a moving target, and both runs may
  "re-run once" the same red deploy (`:997`). Extend D3's single-fixer rule to the deploy re-run.
  **ACCEPTED, no change (2026-09-27).** A's check is valid for the `main` it saw; B's own C5 covers
  B's merges. A double re-run of one deploy just wastes a run. A real red routes to ci-fix FIX,
  already covered by D3's one-fixer rule.
- **F12 — NIT — citation drift.** Plan cites `SKILL.md:302` for full-board wording; it's at `:298`
  and `:76`.
  **FIXED (2026-09-27):** citation corrected in "Launch modes".

---

## Cold-read findings (round 2, 2026-09-27)

A second fresh subagent read the plan after round 1, focused on interactions between the new rules.
75 citations checked, none drifted. Each finding was re-checked against source. All nine were
recorded with their minimal fix in one pass (operator decision); the fixes are folded into the
sections named.

- **G1 — BLOCKER — red `main` with no fixer → every run waits forever.** Only the watcher starts a
  fix (`SKILL.md:1097-1111`); it can time out (`ci-fix-v5/SKILL.md:76`) and isn't spawned after a
  ci-fix merge (`SKILL.md:1071`). **Fix (D3):** merge gate starts ci-fix FIX itself when it sees red
  `main` and no open `fix/ci-*` PR.
- **G2 — SHOULD-FIX — "re-run the PR's checks" re-tests the old red merge commit.** *Hypothesis
  (ED-3), from GitHub's documented re-run behavior (a re-run reuses the original event's SHA).*
  **Fix (D3):** use F1-A's bring-up-to-date-then-re-test step.
- **G3 — SHOULD-FIX — push-to-`main` runs cancel each other.** `cancel-in-progress: true` per ref
  (`fast-tests.yml:18-20`, `integration-tests.yml:15-17`); WATCH handles only success/failure
  (`ci-fix-v5/SKILL.md:82-105`). **Fix (D3):** `cancelled` = superseded; read the newer run.
- **G4 — SHOULD-FIX — D1's minimal body lacks the `**Mode` line** that ends the operator slot
  (`SKILL.md:216`), so Scope/Run state would read as an operator message. **Fix (D1):** loop writes
  the `**Mode (last session):** —` line after the slot.
- **G5 — SHOULD-FIX — Stage 2d follow-ups are lost without full-board mode.** They're appended only
  to the in-memory ticket list (`SKILL.md:475`); C4 appends to `Scope:` (`:980`). **Fix (§2):** 2d
  appends to `Scope:` too.
- **G6 — SHOULD-FIX — two fixers push the same branch before D3's check.** Branch
  `fix/ci-{SHORT_DESCRIPTION}` (`ci-fix-v5/SKILL.md:165`) is pushed at `:197`, before the
  pre-`gh pr create` check. **Fix (D3):** check before pushing; branch name carries the run number.
- **G7 — NIT — D4 said rebase (needs force-push); F1-A merges `main` in.** **Fix (D4):** merge
  `main` in.
- **G8 — NIT — build-order slips:** F11 listed in step 3 though accepted with no change; the
  `integration-tests.yml` header rewrite (describes F1-A) was in step 2. **Fix:** table updated.
- **G9 — NIT — a run self-closed over an overlap looks "already complete" to `--run`.** **Fix
  (F4):** `⚠ closed — scope overlap with #N` comment; `--run` reports it.

---

## Cold-read findings (round 3, 2026-09-27)

A third fresh subagent read the plan after round 2. ~85 citations checked; one had drifted
(`project-tracking.md:88-90` → `:89-91`, now fixed). I re-checked each finding below against the
source; all hold. Operator accepted every suggested fix (2026-09-27); they're folded into D3, F4,
§2 and "Planning the split". H9 was pure bookkeeping.

**Summary:** no blockers this round. Five should-fixes, three small nits. Most are edge cases in the
round-2 CI-fix rules (G1, G5, G6).

- **H1 — RESOLVED (2026-09-27, suggested fix folded in) — the merge gate can start a second fixer inside the same run.**
  *In plain terms:* the CI watcher starts a fix in the background, and that fix spends a while
  diagnosing and testing before it opens a PR. During that time the merge gate sees "red `main`, no
  fix PR" (G1) and starts a second fix. Both push branches with the same run number, the second push
  can be rejected, and that likely ends as Blocked → run halts.
  *Evidence:* background FIX spawn `orchestrate-v5/SKILL.md:1099-1106`; FIX diagnoses/tests before
  pushing `ci-fix-v5/SKILL.md:130-197`; Blocked halts `SKILL.md:1127`.
  *Suggested fix:* before starting a fix, the merge gate also checks whether this session already
  has a fix running (`session_metrics.ci_fixes[]`); if so, it waits on that one.

- **H2 — RESOLVED (2026-09-27, suggested fix folded in) — CLEANUP can wait forever on a fix ticket nobody is working.**
  *In plain terms:* D3 says "if an open fix ticket for this test already exists, don't make
  another, wait for it." But that ticket might not be in any open run — e.g. left over from a
  finished run. Then nobody ever works it and this run never finishes.
  *Evidence:* the pilot did exactly this — ticket #389 filed and left open (`SKILL.md:935`).
  *Suggested fix:* only wait if the existing ticket is in another **open run's** `Scope:`;
  otherwise add it to this run's `Scope:` and work it.

- **H3 — RESOLVED (2026-09-27, suggested fix folded in) — a Stage 2d follow-up might already belong to the other run.**
  *In plain terms:* F4 skipped the overlap check for follow-ups because "they're brand new." But
  2d also picks up follow-ups that already existed, which could be in another run's scope. G5 now
  adds those to `Scope:` without a check.
  *Evidence:* "check whether a follow-up ticket was created" / "If a follow-up ticket exists"
  (`SKILL.md:464`, `:466`); only `:465` auto-creates.
  *Suggested fix:* run the overlap check when 2d adds a ticket it didn't create itself.

- **H4 — RESOLVED (2026-09-27, suggested fix folded in) — `plan-batches-v6` prints v5 launch commands.**
  *In plain terms:* the batching skill's output lines say `./scripts/orchestrate.sh`, which is the
  **v5** wrapper (D7). Pasting two of those starts two v5 runs, which close each other's run
  issue — the exact F2 hazard, caused by our own tool.
  *Evidence:* plan "Planning the split" output line; `templates/scripts/orchestrate.sh:27`;
  v5 closes older runs `SKILL.md:185`.
  *Suggested fix:* output `./scripts/orchestrate-v6.sh --tickets "..."`. (One-word change; left
  open only because I said I wouldn't decide anything while you were away.)

- **H5 — RESOLVED (2026-09-27, suggested fix folded in) — a CI fix merges itself without F1's re-test, and can merge a duplicate.**
  *In plain terms:* ci-fix merges its own PR directly, so F1's "bring up to date and re-test before
  merging" (which lives in the orchestrator's merge gate) doesn't apply to it. And D3's "lower PR
  number wins" doesn't cover the case where the lower one **already merged**: the higher one then
  sees no open rival and merges a second fix.
  *Evidence:* ci-fix merges directly `ci-fix-v5/SKILL.md:237`.
  *Suggested fix:* before merging, ci-fix closes its PR if another `fix/ci-*` PR was opened or
  merged since it started; otherwise it applies the same up-to-date-then-re-test step.

- **H6 — RESOLVED (2026-09-27, suggested fix folded in) — no run number for ci-fix standalone mode.** G6 puts the run number in fix branch
  names, but standalone ci-fix has no run, and FIX mode isn't given one today
  (`ci-fix-v5/SKILL.md:124-128`, `:269-293`). *Suggested fix:* pass the run number in when the
  orchestrator starts a fix; standalone uses `fix/ci-manual-{description}`.

- **H7 — RESOLVED (2026-09-27, suggested fix folded in) — G3's "read the newer run" doesn't fit how the watcher looks up runs.** The watcher
  looks up runs by the merge commit (`ci-fix-v5/SKILL.md:50`, `:71`); after a cancel, the newer run
  is on a different commit (often the other run's merge). Also unstated: what if the latest
  non-cancelled run is still running? *Suggested fix:* follow the latest non-cancelled run of that
  workflow on `main`; still running = wait.

- **H8 — RESOLVED (2026-09-27, suggested fix folded in) — §2's change list is incomplete.** Merge-gate edits (F1-A, main-first, G1), the
  circuit-breaker edits (`SKILL.md:1139` for D4, `:1140` for D3) and the ci-fix edits (G3, G6, D5,
  F7) appear only in the D/F/G items. Someone building from §2 would miss them. *Suggested fix:*
  add one bullet per item to §2.

- **H9 — NIT — stale bookkeeping. FIXED (2026-09-27).** Header "Last updated" date, round-1
  "Status: all OPEN" line, and the `project-tracking.md` citation corrected.


---

## Build order

**Built in one pass (operator decision, 2026-09-27)**, then used; adjust from real use rather than
more paper review. The earlier staged order existed only so a half-built v6 couldn't run two
orchestrators at once; building everything before first use removes that risk. Checklist:

- 15 v6 skills: the 14 v5 skills copied to `-v6` with skill cross-references renamed, plus
  `plan-batches-v6`.
- v6 loop, status script and wrapper (D7), incl. `LIMIT_WAIT` (§5), run binding, issue creation
  (D1, F9, G4), overlap guard (F4, G9), lock/log by full path.
- `orchestrate-v6`: §2 changes, D2–D4, D8, F1-A, G1–G5, H1–H3, H8.
- `ci-fix-v6`: D3, D5, F7, G3, G6, H5–H7. `monitor-v6`: §3.
- D8 `## Dependencies` in prd-to-backlog, add-story, refine-story, triage, implement-ticket.
- Workflow templates: F1-B push trigger + `integration-tests.yml` header.

Existing projects also need the **v6 migration checklist** (see Versioning) before their first v6
run.

---

## Versioning: a v6 generation (decided 2026-09-26)

**Decision (operator):** this ships as a **full v6 generation**, not an in-place v5 upgrade. This
reverses the old plan's "upgrade v5, don't cut a v6" recommendation. The goal is separation: v5
keeps running unchanged on existing projects while v6 is built and proven.

**What "full generation" means:**
- **All 14 v5 skills get a `-v6` copy** (`skills/*-v5/` → `skills/*-v6/`), including the ones this
  plan doesn't otherwise change. Inside the copies, every cross-reference to a `-v5` skill is
  renamed to `-v6`, so a v6 run never calls into v5. v6 also adds one new skill,
  `plan-batches-v6`, for 15 in all.
- **The plan's changes land only in v6.** The file:line references in "Changes to build" point at
  the v5 source they're copied from; apply them to the v6 copies. v5 is not changed.
- **The loop and scripts must be versioned too, not just the skills.** The project wrapper
  self-updates from the standards repo and execs the shared loop
  (`templates/scripts/orchestrate.sh:25-27`), and the loop's prompt hard-codes
  `.claude/skills/orchestrate-v5/SKILL.md` (`orchestrate-loop.sh:129`). Editing the loop in place
  would change every v5 project on its next run. So v6 gets its own loop, status script and wrapper
  template (`orchestrate-loop-v6.sh` etc., D7); the v5 loop stays as is. A project moves to
  v6 by switching its wrapper.
- **Retiring v5** follows the v4 → v5 pattern: once v6 is proven on a pilot, move the v5 skills to
  `skills/archive/` and update `CLAUDE.md`, the standards, and the workflow docs to point at v6.

**v6 migration checklist (per existing project).** Sync never overwrites a project's existing
files (`CLAUDE.md` steps 5–7), so moving a project from v5 to v6 needs these by hand:
- Re-copy or patch `.github/workflows/fast-tests.yml` and `integration-tests.yml` to add the
  push-to-`main` trigger (F1-B).
- Finish or close any open v5 run first; from then on launch only with
  `./scripts/orchestrate-v6.sh` (D7, F2). Never run v5 and v6 on the same repo.

**Costs we're accepting:**
- While both generations are live, the sync protocol (`CLAUDE.md` step 5) copies **both** sets into
  every project, since it syncs everything outside `archive/`. The names don't collide, so this is
  clutter, not breakage.
- A fix to a skill that's identical in v5 and v6 has to land in both until v5 is archived.
- Standards, workflow docs and `CLAUDE.md` refer to v5 skills by name (~113 lines outside
  `skills/`). These are left alone until v5 retires, then updated in one pass.

**Open:**
- **D6 — Does `LIMIT_WAIT` (§5) also go into v5? REVERSED (2026-09-27): no — v6 only.** Operator:
  the usage limit has never been a problem across long v5 use, so v5 stays completely untouched.
  (Originally resolved yes on 2026-09-26.) Detection is a plain text match on the operator-supplied
  error shape (`429 - rate_limit_error`, §5); revisit once a real limit hit is seen.
- **D7 — v6 script naming and location. RESOLVED (2026-09-26): `-v6` suffix, same as the skills.**
  - `developer-tools/orchestrate-loop-v6.sh`, `developer-tools/orchestrate-status-v6.sh`.
  - `templates/scripts/orchestrate-v6.sh`, vendored into projects as `scripts/orchestrate-v6.sh` by
    the existing sync step (`CLAUDE.md` step 7, skip-if-exists).
  - The v5 files stay where they are, untouched (D6 reversed). Existing projects'
    `scripts/orchestrate.sh` keeps running v5.
  - A project moves to v6 by running `./scripts/orchestrate-v6.sh`; no file edits. The move is a
    **one-way cutover** between runs (F2): once a repo is on v6 it stays there. At v5 retirement the
    v5 scripts move to an archive folder.
  - Rejected: a `developer-tools/v6/` folder (inconsistent with how skills are versioned).
  - Side effect (accepted, same as skills): both wrappers sync into every project while both
    generations are live.
