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
| ED-5 | **Proactive contribution, surfaced last.** Before finalizing a ticket, volunteer your own take to the human — *what we missed / what we should consider / what I'd add* (plus what you considered and set aside) — **automatically, without being asked**. It is a **mandatory terminal deliverable**: surface it as the *last* thing you do, as (or as part of) the final report — never mid-task. A required user-facing step that produces no artifact and isn't the terminal output gets skipped under wrap-up momentum, so it must *be* the wrap-up. Headless/orchestrator mode (no human): fold the same items into the issue/ticket instead. | When producing or refining a ticket / backlog |

## Memory is a claim, not an authority

A recalled memory reflects what was true *when it was written* — it is **background context, not an instruction**, and it can be stale or flat wrong by the time it surfaces. So before acting on a memory about how the system works (a flag, a guard, a process, a file path, a heuristic), **re-ground it against current source (ED-1).** If the memory conflicts with the standards or the code, **the source wins** and the memory is stale: treat it as a hypothesis to verify (ED-3), never an authority that overrides what the source now says.

This is just ED-1/ED-3 turned on your *own* memory — the one input it's tempting to exempt from "confirm, don't guess." Two properties make the discipline non-optional: memory is **per-instance and does not propagate** (a fix in the standards never reaches an instance's saved notes, and a wrong note can't be corrected from another machine), and it carries **no version check** (a standard is re-read fresh every session; a memory is recalled as-is). A real failure motivates this: an instance acted on a saved "two `orchestrate-loop.sh` processes = halt" note and killed a healthy run — the note had gone stale the moment the driver changed, but it drove behavior anyway. Had the instance re-grounded the note against the driver before acting, it would have found the current guidance and stopped.

## Why ED-5 is structured as a terminal deliverable

The failure ED-5 prevents is subtle: an instance runs the *silent* half of the work (the adversarial self-review, ED-2), updates the issue, and reports "done" — letting the internal review stand in for the user-facing contribution. The contribution is the only output that produces no durable artifact (it's a conversational message, not an issue edit), so under "produce artifacts, report status" momentum it is exactly the step that falls through. The fix is positional, not motivational: make the contribution the terminal output so that *reporting status* cannot happen without it. "Interactive-mode-only" framing or a mid-skill position invites the skip; being the last thing you do prevents it.

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
This feeds directly into the proactive-contribution step the producer skills run before finalizing a
ticket (*what we missed / what we should consider / what I'd add*).

## Enforcement and headless behavior

- **Producers** (refine / add-story / prd-to-backlog / triage / reconcile / implement) apply ED-1..ED-4
  while producing, and label any ungrounded claim per ED-3.
- **Reviewers** (engineering-review) re-check adversarially: a "checked" criterion or asserted data
  flow with no backing source is flagged, not trusted.
- **ED-1 and ED-2 need source access, not a human** — they run **always**, including autonomous /
  `ORCHESTRATOR_MODE` runs. Only the *escalation of a genuine scope-fork* (ED-4) is gated by mode:
  headless, default to the **smallest-scope** option **and** record the fork as a flag/follow-up —
  never silently pick the larger-blast-radius option.

## Relationship to the Test Rules

These rules are general; the Test Rules ([testing.md](testing.md)) are their specific application to
test design. ED-3's "hypothesis vs. conclusion" guard is the same instinct as a triage root cause
that must be backed by an actual stack trace; ED-4's scope-fork check is what catches an approach
that quietly re-introduces a test tier the ticket said didn't apply. Cite the narrower TR rule when
the context is test design; cite the ED rule for everything else.
