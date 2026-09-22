# Human vs. Agent Time Tracking — Step 1 Findings

> **Responds to:** [time-tracking-brief.md](time-tracking-brief.md) (Step 1: investigate first)
> **Date:** 2026-09-22
> **Scope:** read-only investigation of this repo, the sibling `heycapto` repo, local Claude Code transcripts (`~/.claude/projects/`) on one machine, and the heycapto `orchestration-run` issues on GitHub. No code was written.

## Summary

- **An existing time tracker exists: AgentZula.** It is probably the right place for storage, human-time entry and statements. Its heartbeat hook is too coarse to bill agent time. Its source isn't in this repo, so a final call needs a look at it.
- **The orchestrator launches one `claude -p` session per loop pass.** A billable "run" is one invocation of the loop, which spans many sessions. Runs in the same repo can't overlap today.
- **Transcripts can tell headless runs from interactive ones** (`entrypoint: "sdk-cli"` vs `"cli"`). They don't record the git remote.
- **Two things need to change in the proposed design.** A plain idle-gap rule would undercount time spent in long tool calls. Transcripts are deleted after about 30 days by default.
- **Phase 0 has to run on the machine(s) where orchestration actually runs.** GitHub shows 98 heycapto runs, but the machine investigated holds transcripts for only one of them.

---

## 1. Existing monitoring agent

Two candidates exist. One is a time tracker; the other isn't.

### AgentZula (Kevin Phifer, March 2026)

AgentZula is a time-tracking system with a REST API and an MCP server. Its MCP tools include `LogActivity`, `GetActivitySummary` (time by project/client over a date range), `GetClientsAndProjects` and `GenerateInvoiceData`. This repo holds only the client side:

| File | What it is |
|---|---|
| `developer-tools/hooks/agentzula-heartbeat.sh` | PostToolUse hook: finds the project from a `.agentzula-project` marker file and posts at most one "Claude Code session activity" ping every 5 minutes to `POST /api/activity` |
| `developer-tools/agentzula-project-setup.md` | Setup guide (hook, marker file, MCP connection, tool list) |
| `developer-tools/claude-code-hooks.md` | Hook configuration reference, including the heartbeat |

heycapto's `.gitignore` lists `.agentzula-project`, so the marker was set up there at some point. The hook isn't installed on the machine investigated. AgentZula's own source code isn't on that machine.

**Can we extend it?** Probably, **as the storage and reporting layer**. It already has clients, projects, manual activity logging and invoice generation. That covers human time, statements and the "two people, one place" requirement.

**Its heartbeat can't bill agent time accurately:**
- It uses one debounce file for all sessions on a machine (`/tmp/agentzula-last-heartbeat`). Parallel agents would collapse into a single ping.
- It records no session ID, no run start or end, and no difference between headless and interactive sessions.

A final recommendation needs a look at AgentZula's repo and data model.

### `skills/monitor-v5`

`skills/monitor-v5` is a read-only, LLM-driven commentator on a live orchestration run. It reads the GitHub tracking issue, pull requests and CI, and describes progress. It doesn't measure or store time, so it isn't useful for billing.

---

## 2. The orchestration script

| What | Where |
|---|---|
| Entry point | `scripts/orchestrate.sh` pulls the standards repo, then runs `developer-tools/orchestrate-loop.sh` (`templates/scripts/orchestrate.sh:27`) |
| Headless launch | `developer-tools/orchestrate-loop.sh:205`: `timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions`, inside a relaunch loop |
| Run finish | `orchestrate-loop.sh:219–264`, decided by the loop, not the session |

### One run = many sessions

Each loop pass is a fresh `claude -p` process, usually one ticket per session (`N=1`, the default). A **billable run is one invocation of the loop**, not one Claude session. That's why `TI_RUN_ID` is needed: it groups the sessions of one run.

### Finish detection

A single session ending just triggers a relaunch. The run ends when:
- the GitHub `orchestration-run` tracking issue is closed (the run reached its end state) → `exit 0`
- the tracking-issue body says `Run state: AWAITING_HUMAN` → `exit 0` (the run is paused, not finished; a later loop resumes it)
- the max-iterations limit trips → `exit 3`

The loop can also be killed with Ctrl-C, which leaves no clean end marker.

### Parallel runs

- **Parallel runs aren't possible in one repo today.** A per-project `flock` (`orchestrate-loop.sh:110`) allows one loop per project.
- **Loops in different repos can run at the same time.**
- `notes/parallel-orchestration-plan.md` would allow several workers per repo, each in its own clone. It is a draft marked "not buildable until B1–B3 are resolved".
- **Inside a run, all parallel work is subagents.** Stage work runs through the Agent tool, and the ci-fix watchers run as background agents. Under the brief's rules none of these are billed separately.

---

## 3. What Claude Code records

These findings come from 12 top-level sessions and 107 subagent transcripts on one machine, Claude Code versions 2.1.233–2.1.272.

| Field | Reliable? | Notes |
|---|---|---|
| `timestamp` | Yes | On every message, tool call and tool result |
| `sessionId` | Yes | Also the transcript file name |
| `cwd` | Yes | Can change within a session (up to 4 values seen) |
| `gitBranch` | Yes | Changes within a session (one headless session touched 4 branches) |
| Git remote | **No** | Not recorded. It has to be looked up from `cwd` at backfill time, which only works if the directory still exists |
| Headless vs interactive | **Yes** | `claude -p` sessions have `entrypoint: "sdk-cli"` and `promptSource: "sdk"`. Interactive sessions have `"cli"` and `"typed"`. The orchestrator prompt text ("You ARE the v5 orchestrator…") is also recognisable |
| Subagents | Yes | Stored separately in `<session>/subagents/agent-*.jsonl`, with `isSidechain: true` and the parent's `sessionId`, so they're easy to exclude from the count |

---

## 4. Problems with the proposed design (Step 2)

1. **A plain "gap over 5 minutes = idle" rule would undercount.** In the one headless session examined (53 minutes), every gap over 5 minutes was a tool still running:
   - a `dotnet test` run lasting about 6 minutes
   - a `gh pr checks --watch` lasting about 6 minutes
   - about 7 minutes while a background CI-watcher agent was working

   The parent transcript also goes quiet while a subagent is working. **Active time should combine the parent's and subagents' timestamps and count an unfinished tool call as activity.**
2. **A timed-out session may never fire SessionEnd.** The loop's `timeout` wrapper kills a stuck session with SIGTERM. Storing `transcript_path` at SessionStart and rebuilding from the transcript is therefore **essential, not just a fallback**. The Stop hook fires at the end of every turn, so it doesn't signal the end of a run.
3. **Transcripts are deleted after about 30 days by default.** `cleanupPeriodDays` isn't set, and the oldest transcript on the machine is from 2026-08-17. **Raise the limit on every machine now**, before Phase 0 or live collection.
4. **Interactive sessions stay open for days.** One ran from 09-15 to 09-22. Elapsed time means nothing for them, so suggested human entries will have to be built from bursts of activity.
5. **The git remote has to come from outside the transcript.** For live collection, the SessionStart hook should record it (`git -C "$cwd" remote get-url origin`) rather than rely on `TI_REPO` alone.

---

## 5. A problem for Phase 0

**The machine investigated holds almost none of the agent history.**

- **GitHub:** 98 heycapto `orchestration-run` tracking issues, all opened by `drdatarulz`. By month: June 23, July 44, August 20, September 11.
- **The investigated machine:** transcripts for **one** run (ticket #1447 on 2026-08-26), made up of two sessions of 53 and 5 minutes.

The rest ran somewhere else. The backfill script has to run on the machine(s) where the loop actually runs, and even there only about the last 30 days will survive.

**Cross-check:** each tracking issue has created and closed timestamps. That gives an independent elapsed-time figure for all 98 runs to compare against the transcript numbers. The figure is rough: a run paused at a human gate stays open longer than it actually worked.

---

## 6. Open questions

1. **Where is the AgentZula repo, and is it deployed?** This decides between extending it and a new SQLite/Postgres database.
2. **Which machine(s) run the orchestration loop, and can the Phase 0 script be run there?**
3. **Does time spent waiting on CI or long test runs count as active agent time?** Under the brief's definition ("no model or tool activity") it does, since a running tool is tool activity.
