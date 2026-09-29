---
name: plan-batches-v6
description: "Split a ticket list into batches for parallel orchestrator runs (one per clone/machine). Read-only: reads every ticket, honors declared ## Dependencies and infers more, keeps dependency chains / milestones / shared-file hot spots in one batch, skips tickets already in an open run, balances by rough size, and — when one round would be lopsided — plans in rounds (clear the hub blockers first, then split the rest evenly). Prints one ./scripts/orchestrate-v6.sh --tickets line per batch. Never writes to GitHub."
argument-hint: "#7,#8,#9,... [orchestrators, default 2]"
---

# Plan Batches

You are splitting a list of tickets into **independent batches**, one per orchestrator run. Each batch is launched on its own clone with `./scripts/orchestrate-v6.sh --tickets "..."`. **Nothing coordinates the runs**: no dependency may cross batches that run at the same time, and the order inside a batch is the processing order.

A dependency only constrains the split **while its blocker is open**. Once a blocker is closed, it stops tying tickets together. So when a few "hub" tickets drag most of the list into one batch, the fix is **rounds**: clear the hubs first, then split what's left evenly (Phase 3b).

You are **read-only**. You never create run issues, launch anything, comment, edit, or move board items. The operator reviewing your output *is* the confirm step; the loop creates a run when a batch is launched.

**Work under engineering discipline** (`standards/engineering-discipline.md`). Every dependency or hot-spot claim is grounded in what a ticket says or what the code shows (ED-1); an inferred one is labeled as inferred (ED-3); the split is cross-examined before printing (ED-2, Phase 4). Cite the ED rules by ID; do not restate them.

This skill carries the batching rules itself. Do **not** read `orchestrate-v6/SKILL.md` to work out how the orchestrator behaves.

## Phase 0: Inputs

Parse `$ARGUMENTS`:
- **Tickets (required):** issue numbers (`#7` or `7`), comma- or space-separated. `--tickets` takes issue numbers only, so convert any Story ID (`SF-7`) to its issue number (`gh issue list --search "SF-7 in:title"`). No tickets → ask for them and stop.
- **Orchestrators N (optional):** an integer ≥ 2 (`3`, `--n 3`, "3 machines"). **Default 2.** N = 1 → say a single run needs no split and print one line.

Resolve the repo: `gh repo view --json nameWithOwner -q .nameWithOwner`.

## Phase 1: Read Every Ticket in Full

For each ticket: `gh issue view {N} --json number,title,state,labels,body,comments`. Read the whole body, not just the title. Record:

- **State.** Closed → drop it with a warning (nothing to do).
- **Milestone marker?** Label `milestone`. Its stories = its sub-issues plus the `## Stories in This Milestone` list in its body.
- **Declared dependencies.** The `## Dependencies` section (one `- #N — reason` line per blocker, or `None`). **Binding** — you may add dependencies, never drop a declared one. A blocker that is closed is already satisfied; a blocker that is open but **not in the list** → warning (the batch will run before its blocker lands unless the operator adds it or waits).
- **Inferred dependencies.** No section (pre-v6 tickets) or anything the section missed: read for "depends on", "after #N", "requires", "builds on", references to entities/tables/endpoints/screens another listed ticket introduces. Mark each as *inferred* with its evidence.
- **Refined?** Use `refine-story-v6`'s Already-Refined test: the body has **all** of `## Summary`, `## Technical Approach`, `## Acceptance Criteria`, `## Files Expected to Change`, `## Branch`, each substantive (not placeholder). Otherwise it is **unrefined → warning, not a halt**; batch it anyway.
- **Files touched.** From `## Files Expected to Change` / `## Files to Change`; for unrefined tickets, a best guess from the summary (labeled as a guess).
- **Rough size.** S / M / L from the number of acceptance criteria, files expected to change, and the tiers in the Test Coverage table (Integration and UI rows cost the most wall-clock: they queue on the shared self-hosted runner). Unrefined → estimate, flagged.

## Phase 2: Exclude Tickets Already in a Running Run

```bash
gh issue list --label orchestration-run --state open --limit 100 --json number,title,body
```

Parse each run's `**Scope:**` value (issue numbers; convert any Story IDs). A listed ticket that is in an open run's `Scope:` is **refused**: leave it out of every batch and name the run (`#12 is already in run #140`). If a ticket you keep depends on a refused one, warn: that batch needs run #140 to finish that ticket first.

## Phase 3: Build the Batches

Build a dependency graph over the remaining tickets (declared + inferred edges), then apply these rules:

1. **A dependency never crosses batches in the same round.** Each connected group of **open** tickets (any chain or tree of dependencies) lands whole in one batch. Nothing orders work between machines running at the same time.
2. **Order within a batch = processing order.** The orchestrator works `Scope:` strictly left to right. Blockers come before their dependents (topological order); among independent tickets, keep the operator's original order.
3. **Milestones.** A milestone gate fires when its run reaches it and pauses that run for a human. Put the milestone **last in a batch that contains all of its listed stories**. If its stories must span batches (or some aren't in the list), **hold the milestone out** — no batch gets it — and say so: launch it as its own follow-up run once every batch finishes.
4. **Shared-file hot spots.** Tickets that will clearly touch the same files (the same endpoint file, `Program.cs`/DI registration, a shared page or component) go in one batch to avoid merge conflicts. "Clearly" means grounded in the tickets' file lists or the code, not a hunch; a weaker overlap is a warning, not a merge. **Database migrations are not a hot spot:** two batches each adding a migration is fine, and a duplicated migration number is not worth a warning — don't mention migration numbering at all.
5. **Balance by rough size, not ticket count.** Place the groups (largest first) into the currently lightest batch. Report the resulting S/M/L totals.
6. **Can't parallelize?** If the groups can't fill N batches (one long chain, everything touches one file), produce **fewer batches than asked** and say so plainly — never split a chain to hit N. Try rounds (Phase 3b) first; say "can't parallelize" only if rounds don't help either.
7. **Is it even?** If the heaviest batch is no more than ~1.5× the lightest (by the S/M/L sizes), this one-round split is the answer — go to Phase 4. Otherwise it's **lopsided**: go to Phase 3b.

## Phase 3b: Rounds (only when one round is lopsided)

Rounds add a sync point — every run in a round must finish before the next round starts — so use them only when they give a clearly more even split, and use the fewest that do: normally **2**, never more than **3**.

1. **Find the hubs.** A hub is an open ticket that blocks several others, pulling them into one group (in a typical case, one or two early tickets that the rest of a feature builds on). Rank open blockers by how many listed tickets depend on them, directly or through a chain.
2. **Round 1 clears the hubs.** Put the hubs (in dependency order) and their own blockers in Round 1. Then **fill every other machine** in Round 1 with work that doesn't depend on anything still open outside its own batch — independent tickets, or chain *starts* that later rounds need (a ticket with no open blockers that unblocks a later one is ideal). No machine should sit idle in Round 1.
3. **Later rounds split the rest.** Treat every Round 1 ticket as **closed** and re-apply Phase 3's rules to what's left. Each later round's tickets may depend on anything in an **earlier** round, and on earlier tickets in their own batch — never on another batch in the same round.
4. **Balance each round** across the N machines. Where it's a choice, give the heavier or deadline-critical chain to the machine that will be free first.
5. **Keep it only if it helps.** If the rounds plan isn't clearly more even than the one-round split, print the one-round split with the Lopsided warning instead.
6. **Milestones** go in the round after all of their stories, last in their batch (or held out, as in Phase 3).

## Phase 4: Self-Check (ED-2) — before printing

Try to break your own split:
- No dependency edge (declared or inferred) crosses batches **in the same round**; every cross-batch dependency points to an **earlier** round.
- Every non-refused, open ticket appears **exactly once** across all rounds; refused and closed tickets appear in none.
- Within each batch, every blocker precedes its dependents, and each milestone comes after all its stories.
- No batch contains an obvious hot-spot pair split from its partner.
- Every declared dependency is still present in the graph (none dropped).

Fix anything that fails and re-check. If a fix forces fewer batches, say so.

## Phase 5: Output

Print only this (no preamble):

````markdown
## Batches ({B} of {N} requested)

**Batch 1** — {size, e.g. 2L + 1M} — {one-line reason for the grouping and order}
```bash
./scripts/orchestrate-v6.sh --tickets "#7,#8,#11"
```

**Batch 2** — {size} — {reason}
```bash
./scripts/orchestrate-v6.sh --tickets "#9,#10"
```

**Held out:** {None | #20 (milestone) — launch after batches 1–2 finish: `./scripts/orchestrate-v6.sh --tickets "#20"`}

## Warnings
- {Refused: #12 is already in open run #140}
- {Unrefined: #10, #11 — sizes are estimates; refine before launch if you can}
- {Undeclared blocker: #8 needs #5 (open, not in the list)}
- {Inferred dependency: #11 → #7 (both add Orders endpoints) — kept in batch 1}
- {Hot spot: #9 and #13 both edit Program.cs — conflict risk}
- {Lopsided: batch 1 ≈ 3× batch 2 — the #7 chain can't be split, and rounds don't help}
- {Fewer batches than asked: everything chains through #7}
````

**When you planned in rounds**, print this instead of the Batches block (Warnings as above):

````markdown
## Plan: {R} rounds on {N} machines (one round would be lopsided: {e.g. 6L+1M+1S vs 1L+1M})

### Round 1 — start now
**Machine 1** — {size} — {reason, e.g. clears the hubs #56 → #9, plus #13 which #14 needs}
```bash
./scripts/orchestrate-v6.sh --tickets "#56,#9,#13"
```
**Machine 2** — {size} — {reason, e.g. independent of machine 1; #59 unblocks #60}
```bash
./scripts/orchestrate-v6.sh --tickets "#10,#11,#59"
```

### Round 2 — after every Round 1 run has finished
**Machine 1** — {size} — {reason} — `--tickets "#12,#14"`
**Machine 2** — {size} — {reason} — `--tickets "#60,#61"`

### Balance
| | Machine 1 | Machine 2 |
|---|---|---|
| Round 1 | 2L + 1S | 1L + 2M |
| Round 2 | 2L | 2L |

**Before Round 2:** wait until **every** Round 1 run has finished and its tickets are closed — not just the implementation PRs (each ticket also gets integration and UI test PRs). Pull `main` in each clone, then re-run `/plan-batches-v6 "#12,#14,#60,#61" {N}` to confirm the split against the live board and get the launch lines.
````

Only Round 1's lines are final. Later rounds are the plan; the re-run confirms them (it normally comes out as one even round, since their blockers are now closed).

Omit the Warnings section if there are none. Each run is one clone: run each line from a different checkout of the repo.

---
<!-- skill-version: 6.0 -->
<!-- last-updated: 2026-09-27 -->
<!-- pipeline: v6 -->
