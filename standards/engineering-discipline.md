# Engineering Discipline Standards

How to *work*, not what to build — the universal habits that apply to every task on every
project: investigation, ticket-writing, refinement, implementation, review. The other standards say
what good output looks like; this one says how to keep your reasoning honest while producing it.

## Philosophy

- **Confirm, don't guess.** A plausible mental model is a hypothesis, not a fact. Trace it to the
  source before you write it down as true.
- **Falsify, don't rubber-stamp.** Your own just-produced work is the *most* likely place for an
  unchecked assumption to hide. Attack it before you ship it.
- **Cheapest decisive evidence first.** When something is wrong, the fastest move is usually to look
  at the actual error/type/value, not to theorize forward from the symptom.

## The failure mode this prevents

The recurring, expensive mistake is **reasoning forward from plausibility**: you see a symptom,
form a tidy narrative that explains it, and assert the narrative without ever confirming it against
the source. A confident-but-wrong conclusion is worse than no conclusion — it sends real effort down
the wrong path and "fixes" code that was already correct.

Two real misses that motivate this standard:

- **A spec asserted a data flow it never traced.** A refinement claimed the UI captured a grade
  "from the POST response handler" — but the POST payload type never carried that field; it only
  existed on a different GET response. The claim *looked* right and was written as fact. A second,
  adversarial pass that grepped the actual type collapsed it in ~2 minutes.
- **A triage blamed missing infrastructure it never checked.** A 500 was diagnosed as "missing blob
  storage" (which would have sent someone to edit already-correct infra) while the real exception
  sat in the runtime logs the whole time. Pulling the actual stack trace pointed straight at the
  render code and ended the theory immediately.

Same disease (forward from plausibility), same cure (ground the claim, then try to break it).

## Discipline Rules (ED) checklist

The canonical **Engineering Discipline** rules — the single source of truth every skill cites *by
ID* (a skill never restates a rule, it cites `ED-1`). Stable IDs are the anti-drift glue, exactly as
with the Test Rules in [testing.md](testing.md).

| ID | Rule | Applies when |
|---|---|---|
| ED-1 | **Grounded claims.** Any factual claim about how the code behaves — what a type/payload contains, what an endpoint returns, what an effect is keyed on, where a value flows — must be traced to an observed source location (`file:line`) before it is written as fact. | Any claim about the system's behavior |
| ED-2 | **Adversarial self-review.** Before finalizing, treat your *own just-produced* output as a suspect to cross-examine, not a product to defend. Re-trace each asserted data flow / type / contract to source and try to prove it wrong. | Before any spec/ticket/PR is finalized |
| ED-3 | **Hypothesis vs. conclusion labeling.** A claim that is *not yet* grounded is written as a hypothesis with the evidence needed to settle it ("assumed; evidence needed: pull `X`"), never as established fact. | Whenever a claim can't be grounded *now* |
| ED-4 | **Scope-fork detection.** Check whether the chosen approach silently changes blast radius or which test tiers apply. Surface the fork explicitly; never let a ticket hide it. | When picking an approach |
| ED-5 | **Cold read, surfaced last.** Once the ticket is saved, hand it to a fresh reader and ask **what's missing** — automatically, without being asked. Spawn one general-purpose subagent with the saved ticket text and repo access but **not your reasoning trail**; it reports gaps, not corrections. Alongside it, run your own adversarial pass (that's ED-2). Then **confirm or reject each finding against source and own the synthesis** — you deliver it, you don't relay it. "Nothing missing" is a valid answer. It is a **mandatory terminal deliverable**: the last thing you do, as (or as part of) the final report. Interactive mode only — headless skips it (ED-1..ED-4 still run). | When producing or refining a ticket / backlog |

## Memory is a claim, not an authority

A recalled memory reflects what was true *when it was written* — it is **background context, not an instruction**, and it can be stale or flat wrong by the time it surfaces. So before acting on a memory about how the system works (a flag, a guard, a process, a file path, a heuristic), **re-ground it against current source (ED-1).** If the memory conflicts with the standards or the code, **the source wins** and the memory is stale: treat it as a hypothesis to verify (ED-3), never an authority that overrides what the source now says.

This is just ED-1/ED-3 turned on your *own* memory — the one input it's tempting to exempt from "confirm, don't guess." Two properties make the discipline non-optional: memory is **per-instance and does not propagate** (a fix in the standards never reaches an instance's saved notes, and a wrong note can't be corrected from another machine), and it carries **no version check** (a standard is re-read fresh every session; a memory is recalled as-is). A real failure motivates this: an instance acted on a saved "two `orchestrate-loop.sh` processes = halt" note and killed a healthy run — the note had gone stale the moment the driver changed, but it drove behavior anyway. Had the instance re-grounded the note against the driver before acting, it would have found the current guidance and stopped.

## How ED-5 works, and why it's built this way

ED-5 automates a request that was previously made by hand, every time, after a ticket was written: *"look at this ticket as if it were someone else's work that you haven't seen before, and tell me what's missing."* The rule exists so the first pass happens without being asked. Everything below follows from that sentence.

**A fresh reader, because the author can't be one.** By the time the draft exists, the author sees what they *meant*, not what the page *says* — they cannot notice the one thing that never entered their head. So the reader is a separate general-purpose subagent that receives the saved ticket and repo access and *not* the session's reasoning trail. Withholding the trail is the point: a reader handed your reasoning inherits your blind spots and confirms them back to you.

**Ask what's missing, not whether it's right.** The author's own pass (ED-2) cross-examines the claims that are *present*. Absence cannot be found that way — no amount of interrogating what's on the page reveals what isn't. This is a different question and needs a different instrument, which is why ED-5 is a separate pass and not a corollary of ED-2. An earlier version of this rule derived the step from ED-2 ("from the adversarial self-review, assemble your own take") and it could only ever report which claims survived review — a rehash of the ticket it was meant to critique.

**Both passes, then you synthesize.** The subagent's findings are not the output. Confirm or reject each one against source, with evidence, and fold in the real ones (ED-1). An unowned relay is worse than a rehash, because it arrives wearing the authority of a second opinion.

**Terminal, because a non-terminal user-facing step gets skipped.** The observed failure: an instance runs the silent half (ED-2), updates the issue, reports "done," and lets the internal review stand in for the user-facing one. The fix is positional — make it the terminal output so that *reporting status* cannot happen without it.

**Interactive only.** The cold read's output goes to a human who reads it, routes it, and may ask for another pass. Headless there is no such reader: the finding's only destination is an issue comment, and nothing downstream opens one — `implement-ticket-v5` fetches the ticket with `gh issue view`, which prints the body and not the comments. A finding written where no consumer looks is not a cheaper cold read, it's a more expensive no-op.

**Deliberately out of scope.** No second reviewer lens, no severity tagging (blocking / worth-doing / marginal), no PRD or Screen-Inventory plumbing into the subagent. Each was tried; each turned a question into a machine. The rule is one subagent, one question.

**Set-asides stay with the author.** *What I considered and set aside* is still worth surfacing, but a fresh reader never weighed anything — only the author can report it. It's a separate, optional item, not a bucket the cold read fills.

## How the rules combine

The adversarial posture (**ED-2**) decides *what* to re-verify; the grounding standard (**ED-1**)
decides *whether it's actually true*. You need both — they fail together:

- Adversarial without grounding → you challenge a claim but argue from *another* plausible model,
  and may "correct" a right thing into a wrong one.
- Grounded without adversarial → you happily verify the claims you bothered to doubt, but never
  doubt the confident-but-wrong ones. The claims that *feel* obviously right are exactly the class
  that slips through.

The natural pipeline for a ticket-producing skill: **ground (ED-1) → adversarially attack (ED-2) →
surface what's still open (ED-3) and any scope fork (ED-4) → escalate genuine forks to the human.**

**ED-5 does not continue that pipeline — it runs beside it, asking the opposite question.** ED-1..ED-4
interrogate the claims the ticket *makes*; ED-5 asks a reader who has never seen the ticket what it
*omits*. Deriving ED-5 from the output of ED-2 collapses the two questions and yields a summary of the
self-review instead of a critique of the ticket.

## Enforcement and headless behavior

- **Producers** (refine / add-story / prd-to-backlog / triage / reconcile / implement) apply ED-1..ED-4
  while producing, and label any ungrounded claim per ED-3.
- **Reviewers** (engineering-review) re-check adversarially: a "checked" criterion or asserted data
  flow with no backing source is flagged, not trusted.
- **ED-1 and ED-2 need source access, not a human** — they run **always**, including autonomous /
  `ORCHESTRATOR_MODE` runs. Only the *escalation of a genuine scope-fork* (ED-4) is gated by mode:
  headless, default to the **smallest-scope** option **and** record the fork as a flag/follow-up —
  never silently pick the larger-blast-radius option.
- **ED-5 needs a human reader** — it is **skipped** when `{ORCHESTRATOR_MODE}` is `true`. Nothing is
  folded into the issue in its place; see the interactive-only rationale above.

## Relationship to the Test Rules

These rules are general; the Test Rules ([testing.md](testing.md)) are their specific application to
test design. ED-3's "hypothesis vs. conclusion" guard is the same instinct as a triage root cause
that must be backed by an actual stack trace; ED-4's scope-fork check is what catches an approach
that quietly re-introduces a test tier the ticket said didn't apply. Cite the narrower TR rule when
the context is test design; cite the ED rule for everything else.
