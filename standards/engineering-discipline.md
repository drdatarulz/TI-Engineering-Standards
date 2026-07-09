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
| ED-5 | **Cold read, by fresh eyes.** Before a ticket is finalized, hand the drafted ticket — **text only, none of the authoring conversation** — to two fresh-context readers, an **implementer** and a **product owner**, and ask each the one question the author cannot answer: *what is missing?* Surface their findings **automatically, without being asked**, ranked, each tagged `blocking` / `worth doing` / `marginal`, alongside your own **set-asides** (branches you weighed and rejected, each with the condition that would reverse it). **"Nothing to add" is a success, not a failure to perform.** Interactive mode only — a cold read with no human to read it is theater. | When producing or refining a ticket / backlog, with a human present |

## Memory is a claim, not an authority

A recalled memory reflects what was true *when it was written* — it is **background context, not an instruction**, and it can be stale or flat wrong by the time it surfaces. So before acting on a memory about how the system works (a flag, a guard, a process, a file path, a heuristic), **re-ground it against current source (ED-1).** If the memory conflicts with the standards or the code, **the source wins** and the memory is stale: treat it as a hypothesis to verify (ED-3), never an authority that overrides what the source now says.

This is just ED-1/ED-3 turned on your *own* memory — the one input it's tempting to exempt from "confirm, don't guess." Two properties make the discipline non-optional: memory is **per-instance and does not propagate** (a fix in the standards never reaches an instance's saved notes, and a wrong note can't be corrected from another machine), and it carries **no version check** (a standard is re-read fresh every session; a memory is recalled as-is). A real failure motivates this: an instance acted on a saved "two `orchestrate-loop.sh` processes = halt" note and killed a healthy run — the note had gone stale the moment the driver changed, but it drove behavior anyway. Had the instance re-grounded the note against the driver before acting, it would have found the current guidance and stopped.

## ED-5: the cold read

### The failure it prevents

Asked *"what else should we add?"*, an author answers with a **rehash** — a summary of what they just put in, dressed as a review. This is not laziness; it is structural. The author cannot see the gap, because the thing that would have filled it never entered their head, and nothing on the page marks its absence. Asking the author to find it is asking them to notice the one thing they never thought of.

Two design errors guarantee the rehash, and both must be fixed:

- **Deriving the contribution from ED-2.** The adversarial self-review interrogates claims that are **present** — *is what I wrote true?* Absence cannot be found by cross-examining presence. A contribution assembled from ED-2's output is a report on which claims survived it.
- **Making the author the reader.** By the time the draft exists, the author has spent the whole session inside the intent behind it. They read the ticket and see what they meant, not what it says.

So ED-5 is **not** a continuation of ED-2. It is a separate pass, asking the opposite question, performed by someone else.

### Fresh context is the mechanism

The reader is a **subagent that receives only the drafted ticket text and the standards** — no PRD-to-draft conversation, no decisions log of how we got here, no summary of intent. It reads what a developer will read when they pick the ticket up cold in three weeks. "Someone who didn't write it" must be *literally* true; an author instructed to *pretend* they didn't write it is still the author, and the pretence gets weaker on every subsequent pass.

This is also what makes re-asking cheap. When the human says *"go again"*, a fresh reader starts fresh; an in-conversation reader is only more contaminated than it was the first time.

### Two lenses, kept separate

Run **two** readers, not one reader wearing two hats. A merged reader collapses into the implementer's voice — it is the voice the surrounding artifacts already speak (the code, the tiers, the standards), so it wins by default and the product questions never get asked.

| Lens | Asks | Finds |
|---|---|---|
| **Implementer** | *Can I build exactly this, and will I know when I'm done?* | An AC that isn't verifiable as written; "follow the existing pattern" that never names the pattern; an unspecified error path; an undeclared dependency on another ticket |
| **Product owner / BA** | *Does this deliver the outcome someone wanted, and what happens to everyone it touches?* | An AC that proves the code path fired but never that the user got the value; nothing said about the rows that already exist; a half-feature coherent in the repo and broken on screen; the empty state, the zero-permission user, the org with no records yet; a business rule everyone knew and nobody wrote down |

Neither lens can find the other's misses. An implementer will happily build a perfectly-specified feature nobody asked for; a product owner will happily ask for something whose criteria can't be tested.

### The product lens must be grounded too (ED-1 applies to it)

The implementer lens grounds itself in the codebase. **The product lens has no equivalent source unless one is given to it** — and a product lens with nothing to read will *invent business requirements*, which is worse than the rehash it replaced, because it sounds like insight.

So: give the product reader the **PRD, Screen Inventory, and Decisions Log** when they exist, and require it to cite them. Anything it cannot ground is a **hypothesis (ED-3)** — *"assumed; confirm against the PRD"* — never asserted as a missing requirement. `prd-to-backlog-v5` and `reconcile-backlog-v5` have these loaded; `refine-story-v5`, `add-story-v5`, and `triage-v5` often do not, and must say so to the reader rather than let it fill the silence.

### Set-asides come from the author, and must be reversible

A **set-aside** is a branch that was weighed and rejected: *"considered making this idempotent, set it aside because retries seemed out of scope."* It is the one item a fresh reader structurally **cannot** produce — it never weighed anything. So set-asides come from the author, and the deliverable has two sources: the author's set-asides, and the cold read's findings. Do not pretend they came from the same place.

A set-aside earns its place only when the road not taken is still open. The test: **can you name the condition that would reverse it?** *"Called it `SyncTask` rather than `SyncJob`"* fails — no reversal condition, it is trivia. *"Would reverse if the caller can retry"* passes, and that is precisely the item the human wants to catch.

Note what a set-aside *is*: a fork the ticket does not show, invisible to any reader because the losing branch left no trace on the page. It is an absence finding, arriving by another road.

### Ranking, and the anti-padding tax

Every finding carries a marker: **`blocking`** (I'd hold the ticket for this) / **`worth doing`** / **`marginal`**. This is not decoration. A mandatory step whose output is a form to be filled will get the form filled — that is the padding equilibrium, and it is what produces the rehash even after the reader is fixed. So:

- **No fixed buckets.** An unbounded list ranked strongest-first, not a set of headers each demanding an answer.
- **Empty is a legal, successful result.** *"Nothing to add"* is the goal state. A step that cannot come back empty will never come back honest.
- **Padding must self-label.** To pad, a reader has to tag the padding `marginal`. A read that returns all-marginal findings *is* the signal that the well is dry, stated in the reader's own words — and the human can still overrule it, because the finding is right there to be re-judged. An unsupported *"I'd stop here"* gives the human nothing to disagree with.

The human loops by asking again. The skill does **one** pass; it does not manage rounds, convergence, or its own stopping rule.

### The reader contract

Every cold reader, in every skill, gets these instructions. A skill supplies only its own **wiring** — which artifact, which lens, which grounding documents — and cites this contract rather than restating it.

> You are reading a drafted ticket you did not write, with no access to the conversation that produced it. Report what is **missing** — not what is there, not what is wrong, what is *absent*.
>
> Return an unbounded list, strongest first. Each finding: one line on what is missing, one line on why it matters, and what you would add. Tag each `blocking` (I'd hold the ticket for this) / `worth doing` / `marginal`.
>
> **Returning nothing is a correct and expected answer.** Do not manufacture findings. If you include something weak, tag it `marginal` — padding must label itself.
>
> Any claim you cannot trace to a source you were given is a hypothesis (ED-3), stated as such. Do not invent requirements.

### What you hand back

1. **The cold read** — both lenses merged and deduped, each finding attributed to the lens that raised it and carrying its marker. Do not launder a `marginal` upward; do not suppress one. The human overrules the marker, not you.
2. **Your set-asides** — yours, labeled as yours, each with its reversal condition.
3. **The confirmation or plan** the skill owes the user.

If both readers come back with nothing, **say so plainly**. That is a successful cold read, not a failed one.

### Where it sits, and why it can't be skipped

The cold read attaches to **the point where the skill hands control back to the human** — the terminal report in `refine-story-v5`, the pre-creation approval gate in `add-story-v5` / `prd-to-backlog-v5`, the plan gate in `reconcile-backlog-v5`, the pre-write draft in `triage-v5`.

The original failure was an instance running the silent half (ED-2), updating the issue, and reporting "done" — letting the internal review stand in for the user-facing contribution. The cold read produces no durable artifact (it is a conversational message, not an issue edit), so under "produce artifacts, report status" momentum it is exactly the step that falls through. Anchoring it to the handback point is the fix: the skill cannot pass control to the human without it, because **it is what is being handed over**.

Findings the human accepts land in the ticket on the next turn. Findings the human declines are not recorded — the cold read stays conversational, and the ticket is never edited *by* the read itself.

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

**ED-5 does not continue that pipeline — it turns around and faces the other way.** ED-1..ED-4 all
interrogate what the draft *says*: is this claim true, is it grounded, does this approach widen the
blast radius. ED-5 asks what the draft *doesn't* say, and hands that question to a reader who never
saw the draft being written. Chaining ED-5 off ED-2's output is the specific mistake that turns the
contribution into a summary of which claims survived review. Run it as a separate pass, by fresh
eyes, on the finished draft.

## Enforcement and headless behavior

- **Producers** (refine / add-story / prd-to-backlog / triage / reconcile / implement) apply ED-1..ED-4
  while producing, and label any ungrounded claim per ED-3.
- **Reviewers** (engineering-review) re-check adversarially: a "checked" criterion or asserted data
  flow with no backing source is flagged, not trusted.
- **ED-1 and ED-2 need source access, not a human** — they run **always**, including autonomous /
  `ORCHESTRATOR_MODE` runs. Only the *escalation of a genuine scope-fork* (ED-4) is gated by mode:
  headless, default to the **smallest-scope** option **and** record the fork as a flag/follow-up —
  never silently pick the larger-blast-radius option.
- **ED-5 needs a human, so it does not run headless — at all.** The cold read exists to start a
  conversation; with nobody to have it, spawning two subagents to write findings into an issue nobody
  will read is cost without a reader. Under `ORCHESTRATOR_MODE`, skip the cold read entirely and
  proceed on best judgment. ED-1..ED-4 still run and still record their hypotheses (ED-3) and scope
  forks (ED-4) in the issue — that is the existing discipline, not a stand-in for the contribution.

  The path this concedes: a ticket **added mid-development** is refined unattended and is the only
  ticket that never receives a cold read from anyone. Its backstop is `engineering-review-v5` on the
  resulting PR. This is a deliberate trade at that volume, not an oversight.

## Relationship to the Test Rules

These rules are general; the Test Rules ([testing.md](testing.md)) are their specific application to
test design. ED-3's "hypothesis vs. conclusion" guard is the same instinct as a triage root cause
that must be backed by an actual stack trace; ED-4's scope-fork check is what catches an approach
that quietly re-introduces a test tier the ticket said didn't apply. Cite the narrower TR rule when
the context is test design; cite the ED rule for everything else.
