# Brief: Human vs. Agent Time Tracking

I want to build a tool that tracks human time and agent time per client, so we can bill our retainer clients accurately. Please read this whole brief, investigate the repo, and come back with a plan before writing any code.

## Background

We're Theoretically Impossible Solutions. Our first retainer client is Hey Capto. They pay a monthly fee for a capped number of hours: Full is 175 hrs/month for $15,000, Half is 88 hrs/month for $9,000, and hours over the cap are $200/hr, billed after the month ends. Hourly-only is $250/hr. Hours are human time + agent time combined. Clients get a monthly statement showing hours used against the cap, split into human and agent time. Caps reset on the 1st of each month, unused hours don't roll over, and plan changes take effect on the 1st.

Our orchestration today is our own script that calls Claude Code in headless mode.

## Definitions (these are decided)

- **Agent time** is an autonomous run that we launch and that then works without us: an orchestration run, a headless agent, a batch of tickets handed off. It's counted per agent from launch until the run finishes, minus idle stretches. If two agents run in parallel for an hour, that's 2 hours.
- **Subagents** that an agent spawns inside its own run are not billed separately. Only the top-level agents we launch count.
- **Idle time:** for every run, store both elapsed time (launch to finish) and active time (elapsed minus any gap with no model or tool activity longer than a configurable threshold, default 5 minutes). We bill active time.
- **Human time** is everything else: triage, writing and refining tickets, reviews, releases, client conversations, and interactive back-and-forth Claude sessions. It's logged by person, client and category. Most of it will be entered by hand (a quick timer or log entry). Interactive Claude sessions can suggest entries, but a person confirms them.
- **Unit of reporting:** repos roll up to a client. One client can have several repos, and some human time isn't tied to any repo.

## Step 1: Investigate first

- **Look for an existing monitoring agent.** My partner, Kevin Phifer, built an agent at some point that monitored runs or activity. Search this repo and any related ones for it. If it exists, tell me what it does and whether we can extend it rather than build something new.
- **Read the orchestration script.** Find where it launches headless Claude Code runs and where it detects that they've finished. Tell me how parallel runs are started, if they are.
- **Check what Claude Code already records.** Look at the local session transcripts (`~/.claude/projects/`) and confirm which fields we can rely on: timestamps, session ID, working directory, git branch, and whether headless runs can be told apart from interactive ones.

## Step 2: Proposed design (confirm or push back)

- **Tagging:** when the orchestrator launches a run, it passes environment variables, for example `TI_CLIENT`, `TI_REPO`, `TI_TICKET`, `TI_RUN_ID` and `TI_MODE=autonomous`.
- **Hooks:** a hook script (SessionStart, Stop, SessionEnd) reads those tags and writes run start and end events, including the transcript path so the run can be rebuilt later. Sessions without tags don't count as agent time.
- **Active-time calculation:** computed from transcript timestamps after the run ends, using the idle threshold.
- **Data model:** keep it small.
  - `runs`: id, client, repo, ticket, agent/run id, person who launched it, started_at, ended_at, elapsed_seconds, active_seconds, transcript_path
  - `human_entries`: person, client, category, started_at, ended_at, source (manual or suggested), note
  - `client_plans`: client, tier, monthly cap, overage rate, effective_from
  - `repo_clients`: repo (git remote URL, normalized), client
- **Repo identity:** use the normalized git remote URL, not the local path, so different clones and worktrees map to the same repo.
- **Storage:** start simple. I'm open to SQLite or a small Postgres/Supabase database. Two people on different machines need to report into one place, so recommend what fits.

## Step 3: Phase 0, before building the real thing

Write a one-off script that backfills from existing session transcripts and produces a per-repo, per-month report of headless (agent) runs with elapsed and active time, and interactive sessions shown separately. I want to see whether the numbers look believable before we build further.

## Later phases (don't build yet, just keep in mind)

- Live collection through orchestrator tags and hooks, plus a simple way to log human time.
- A monthly statement per client: hours against the cap, human and agent split, and per-run line items for any overage.
- An internal dashboard: burn rate, projected month-end hours, and an alert when more than one agent runs on a client at the same time (the proposal says we'll ask the client before running agents in parallel).
- A read-only client view, switched on per client. It stays off until we've checked our numbers for at least a month.

## Principles

- Keep it simple. The goal is our time versus Claude's time, shown in a form that's easy to read.
- Every billed hour must trace back to a specific run or entry.
- The only thing that should touch the orchestration pipeline is tagging plus hooks. Don't restructure it.

Start with Step 1 and report back.
