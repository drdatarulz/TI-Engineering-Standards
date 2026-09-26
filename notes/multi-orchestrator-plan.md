# Multi-Orchestrator Plan

> **Purpose:** let **several orchestrators run at the same time against one repo, each on its own
> computer**, each driving its own independent run. No shared pool, no claims, no coordination
> between runs. The operator decides up front which tickets go to which machine.
> **Created:** 2026-09-26. **Last updated:** 2026-09-26.
> **Status:** DRAFT. Not yet cold-read. Open decisions D1–D5 below, D6–D7 under Versioning.
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

**One orchestrator per computer.** Each runs in its own clone, on its own machine. What they share
is the **remote repo, the GitHub Project board, the issues, the self-hosted CI runner(s), and
`main`**. Running two orchestrators in two folders on the **same** computer is out of scope (the
loop's lock and log file are keyed on the project folder name, `orchestrate-loop.sh:108,139`, so two
same-named clones on one machine would collide).

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
  (`SKILL.md:70`, `:302`, `:313`). That path goes away. This is a deliberate behavior change.

---

## Changes to build

### 1. Loop: flags, run creation, run binding (`developer-tools/orchestrate-loop.sh`)

- Add `--run N`. Enforce the four-way rule above after argument parsing (`:82-94`).
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
- **CLEANUP C1 dispatch (`:946-947`):** today it dispatches `ui-tests.yml` and then takes
  `gh run list --limit 1` as "my run". With two runs on the repo, that can pick up the **other
  run's dispatch**. Identify the run by matching the dispatch time (or a run-name input) instead.
- **C5 close (`:1005`):** reword "the next relaunch finds no open `orchestration-run` issue" to "the
  loop sees `#$ORCHESTRATE_RUN` closed".
- **Tracking-issue body schema (`:1033`):** `Scope:` loses the `full board` option.

### 3. Observability (`developer-tools/orchestrate-status.sh`, `skills/monitor-v5/SKILL.md`)

- `orchestrate-status.sh:19` and `monitor-v5/SKILL.md:30` pick `.[0]` of the open runs. With no
  argument they should **list all open runs** (number, scope, current ticket); with a run number,
  show that one.

### 4. Docs and templates

- `templates/scripts/orchestrate.sh:9-15` usage lines (no-arg "full board" example goes away).
- `standards/project-tracking.md:50-55` ("One active run = one open issue…", find-or-create by
  label) rewritten for many open runs, each bound by number.
- `workflow/agentic-development-workflow.md` / `workflow/README.md`: check for "one active run" and
  full-board wording. (Not yet checked — ED-3.)

### 5. Usage-limit wait (`LIMIT_WAIT`), carried over from the old plan's U1

A real bug today, independent of parallelism: when a session hits the Claude usage limit,
`claude -p` exits fast, the loop treats it as a crash and relaunches immediately
(`orchestrate-loop.sh:251-258`), and burns all `MAX_ITER` relaunches in minutes (`:261-264`). Two
machines on **one Claude account** hit the limit sooner and together. Fix, in the loop:
- **Detect** from the session output. **ED-3: capture a real usage-limit message before writing
  the pattern.** Don't key on exit code alone.
- **Wait** until the reset time if the message gives one (plus jitter), else probe hourly. Waits do
  not count toward `MAX_ITER`.
- **Surface** `Run state: LIMIT_WAIT (retry ~HH:MM)` in the run issue; clear it on resume.
- **Resume** through the normal Step 0.6 recovery.

Can ship separately and first; it doesn't depend on anything above.

---

## Planning the split (no skill)

Deciding which tickets go to which machine is a conversation, not a skill: *"I have tickets #1–#15
and three orchestrators. Split them."* The output is N `--tickets` lines you review before launching.

**The one hard rule: a dependency must never cross runs.** Nothing orders work between machines, so
if #8 needs #7, both go in the **same** list with #7 first. Dependencies come from declared
`## Dependency on {PREFIX}-{issue#}` sections (`refine-story-v5:321`) plus whatever reading the
tickets turns up. Two cases to watch:
- **Milestone tickets.** A milestone gate (`SKILL.md:329-346`) fires when its run reaches it. If the
  milestone's stories are spread across runs, it fires before the others finish. Put the milestone
  in a list after all its stories, or hold it back and run it on its own once the others are done.
- **Shared-file hot spots.** Tickets that will clearly touch the same files belong in one list, to
  avoid merge conflicts (see D4).

If the same prompt keeps coming up, promote it to a small skill later.

---

## Open decisions

- **D1 — Who writes the run issue body on creation?** The loop now creates the issue, but the body
  schema lives in the skill (`SKILL.md:1010-1051`). Options: (a) the loop writes a minimal body
  (`Scope:`, `Run state: WORKING`, empty operator slot) and the first session fills in the full
  schema; (b) move the schema to a template file both read. *Leaning (a).*
- **D2 — How does an interactive session name an existing run?** Today a bare number in the
  arguments is always a ticket (`SKILL.md:71`), so `orchestrate-v5 supervised 123` can't mean
  "continue run #123". Needs a keyword, e.g. `orchestrate-v5 supervised run=#123`.
- **D3 — Red `main` is shared.** Both runs' background CI watchers see the same red `main`
  (`SKILL.md:1069-1111`), both start a ci-fix FIX agent, and both may trip "Build fails on main"
  (`:1140`). CLEANUP's "if you see it, you own it" hard bar (`:935`) and the C5 deploy bar
  (`:986-997`) make both runs' CLEANUP try to fix the same red test or deploy. Cheapest guard:
  before opening a fix, ci-fix FIX (and CLEANUP's own-it path) checks for an existing open ci-fix
  PR for that failure and waits on it instead of racing.
- **D4 — Merge conflicts.** The circuit breaker halts on any merge conflict (`SKILL.md:1139`). Two
  runs merging to `main` makes that more likely. *Leaning: keep the halt* (human resolves, then
  `--run` resumes) and rely on a good split; revisit if it happens often.
- **D5 — Self-hosted runner contention.** Two runs share the runner(s). C1 treats a dispatched UI run
  still `queued` after ~15 min as "runner down" and halts (`SKILL.md:941`). If one runner is busy
  with the other run's full UI suite, that timer could trip falsely. *Hypothesis (ED-3):* depends
  on how many runners exist and how long a full UI suite takes; check both before deciding.

---

## Suggested build order

0. **Create the v6 generation** (see Versioning): copy all 14 skills to `-v6` with cross-references
   renamed, plus the v6 loop, status script and wrapper. No behavior change yet; v6 at this point is
   a working clone of v5.
1. **`LIMIT_WAIT`** (§5) — independent, fixes a live bug, unblocked once a real limit message is
   captured. (Whether it's also backported to v5 is D6.)
2. **Run binding** (§1 loop + §2 skill Step 0.5 / Parse Arguments / full-board removal) plus the
   **Step 0.6 scoping** and **C1 dispatch-id** fixes. These land together: binding alone is not safe
   to run two-up while 0.6 still sweeps the whole board.
3. **Scope-overlap guard** (§1).
4. **Observability** (§3) and **docs** (§4).
5. **D3 / D5 guards**, once decided.

Single-machine use after step 2 is the same as today except that the operator must pass `--tickets`
or `--run`.

---

## Versioning: a v6 generation (decided 2026-09-26)

**Decision (operator):** this ships as a **full v6 generation**, not an in-place v5 upgrade. This
reverses the old plan's "upgrade v5, don't cut a v6" recommendation. The goal is separation: v5
keeps running unchanged on existing projects while v6 is built and proven.

**What "full generation" means:**
- **All 14 v5 skills get a `-v6` copy** (`skills/*-v5/` → `skills/*-v6/`), including the ones this
  plan doesn't otherwise change. Inside the copies, every cross-reference to a `-v5` skill is
  renamed to `-v6`, so a v6 run never calls into v5.
- **The plan's changes land only in v6.** The file:line references in "Changes to build" point at
  the v5 source they're copied from; apply them to the v6 copies. v5 is frozen apart from bug fixes.
- **The loop and scripts must be versioned too, not just the skills.** The project wrapper
  self-updates from the standards repo and execs the shared loop
  (`templates/scripts/orchestrate.sh:25-27`), and the loop's prompt hard-codes
  `.claude/skills/orchestrate-v5/SKILL.md` (`orchestrate-loop.sh:129`). Editing the loop in place
  would change every v5 project on its next run. So v6 gets its own loop, status script and wrapper
  template (naming TBD, e.g. `orchestrate-loop-v6.sh`); the v5 loop stays as is. A project moves to
  v6 by switching its wrapper.
- **Retiring v5** follows the v4 → v5 pattern: once v6 is proven on a pilot, move the v5 skills to
  `skills/archive/` and update `CLAUDE.md`, the standards, and the workflow docs to point at v6.

**Costs we're accepting:**
- While both generations are live, the sync protocol (`CLAUDE.md` step 5) copies **both** sets into
  every project, since it syncs everything outside `archive/`. The names don't collide, so this is
  clutter, not breakage.
- A fix to a skill that's identical in v5 and v6 has to land in both until v5 is archived.
- Standards, workflow docs and `CLAUDE.md` refer to v5 skills by name (~113 lines outside
  `skills/`). These are left alone until v5 retires, then updated in one pass.

**Open:**
- **D6 — Does `LIMIT_WAIT` (§5) also go into v5?** It fixes a live bug that v5 projects hit today.
  Under the v6-only rule it would only reach v6. A backport to the v5 loop is small, and it doesn't
  change behavior when no limit is hit.
- **D7 — v6 script naming and location** (suffixed files in `developer-tools/` vs a
  `developer-tools/v6/` folder), and whether the vendored wrapper becomes `scripts/orchestrate-v6.sh`
  or stays `scripts/orchestrate.sh` with v6 contents.
