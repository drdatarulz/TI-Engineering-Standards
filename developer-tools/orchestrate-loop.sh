#!/usr/bin/env bash
# Canonical "dumb driver" for the v5 orchestrator (v5-changes.md #6 / plan 4.4).
#
# Its ONLY job is to relaunch a fresh `claude -p` session until the run reaches a
# fixpoint. It holds NO run state — all intelligence lives in the `orchestrate-v5` skill,
# which reads durable state (project board + per-run tracking issue) on each launch and
# self-selects WORKING vs CLEANUP mode. Relaunching as fresh processes is the whole point:
# it sidesteps the context degradation that makes a single long-lived session forget
# workflow steps past ~5–10 tickets.
#
# WHY A LOOP AROUND CLAUDE (not a skill): this driver launches `claude -p`, so it is the
# outermost layer and cannot ride the skills-sync path (sync runs *inside* a session).
# It is generic/project-agnostic — every project specific lives in the board and the
# project's CLAUDE.md. It lives in the standards repo (the mandatory sibling at
# ../TI-Engineering-Standards/) and is normally invoked through a project's thin
# scripts/orchestrate.sh wrapper, which `git pull`s the standards repo then execs this
# with --project-dir "$(pwd)".
#
# STOP CONDITION: the orchestrator emits the RUN_COMPLETE sentinel on stdout when it
# reaches a fixpoint (no Ready tickets AND a CLEANUP pass that injected nothing). The
# durable tracking-issue flag is the orchestrator's concern; the loop only greps stdout —
# that keeps the loop stateless.
#
# THREE GUARDS (the only state the loop needs):
#   1. per-session timeout    — a hung session is killed and relaunched
#   2. relaunch-on-exit       — a crashed session is relaunched (crash watchdog)
#   3. max-iterations cap     — runaway backstop: halt and flag a human (circuit breaker)
#
# SINGLE-INSTANCE LOCK: a per-project `flock` ensures exactly one loop drives a project at a
# time (a second would double-drive the board and race merges). The lockfile is ALSO the one
# reliable answer to "is a loop already running?" — use it, NEVER `pgrep -f orchestrate-loop.sh`:
# each iteration spawns a heartbeat SUBSHELL running this same file, so a process-name match
# returns 2+ during an active iteration and looks like a duplicate. That false positive once
# killed a live loop mid-CLEANUP. To check from outside: `flock -n <lockfile> true` (success =
# no loop running) or read the owner PID from the lockfile. `--status` never takes the lock.
#
# Usage:
#   ./orchestrate-loop.sh [--project-dir DIR] [--n N] [--tickets "#7,#8,..."]
#                         [--timeout SECONDS] [--max-iter COUNT] [--prompt TEXT]
#   ./orchestrate-loop.sh --status [--project-dir DIR]   # one-glance run status, then exit
# Defaults: --project-dir "$(pwd)"  --n 1  --timeout 5400  --max-iter 50
#
# OBSERVABILITY: `claude -p` is silent until a session ends, so the loop prints a periodic
# HEARTBEAT line (current ticket @ stage, polled from the tracking issue) every
# HEARTBEAT_INTERVAL seconds (default 45; set 0 to disable) and streams it — plus the
# session output — LIVE to the durable run log, so `tail -f $RUNLOG` shows real-time
# progress. `--status` (or developer-tools/orchestrate-status.sh) prints a one-glance
# snapshot and is safe to `watch`.
#   --tickets ""  full board (all Up Next). Give a list to SCOPE the run to those
#                 tickets; the scope is recorded in the run's tracking issue on the
#                 FIRST launch and survives every relaunch (so the rest of Up Next
#                 is left alone, even across relaunches).
#   --prompt  ""  auto-built as: "Run the orchestrate-v5 skill in autonomous mode
#                 [for tickets ...]." Pass --prompt only to override entirely.
# The loop ALWAYS runs the orchestrator in **autonomous** mode: a headless
# `claude -p` session has no human to clear the supervised between-ticket gate.
set -uo pipefail

PROJECT_DIR="$(pwd)"
N=1                 # tickets per WORKING chunk. Default 1: one ticket per relaunch = maximum
                    # fresh-context reliability (each ticket gets a brand-new session). Raise it
                    # (e.g. --n 3) to trade some context freshness for fewer relaunches on a run
                    # of small, low-risk tickets; ~3 was the old measured reliability ceiling.
TIMEOUT=5400        # per-session timeout, seconds (90m). This is a HANG guard, not a work
                    # budget — it should only ever fire on a wedged session, never mid-stage.
                    # A big story's implement ran ~30-45m on the pilot and kept tripping the
                    # old 30/60m caps, forcing fragile mid-stage orphan-recovery; 90m clears
                    # any single stage with headroom. Bump higher (e.g. 7200=2h) for very large
                    # stories. Per-STAGE timeouts are deliberately not a thing here: the loop
                    # wraps the whole session and can't see stage boundaries — the checkpoint
                    # system already gives clean per-ticket resume; we just keep the hang guard
                    # well above the longest legitimate stage.
MAX_ITER=50         # circuit breaker: hard cap on relaunches
TICKETS=""          # optional scope, e.g. "#7,#8,#9"; empty = full board
PROMPT=""           # empty = auto-build an autonomous-mode prompt (below)
DO_STATUS=0         # --status: print a one-glance snapshot and exit
SENTINEL="RUN_COMPLETE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --n)           N="$2"; shift 2;;
    --tickets)     TICKETS="$2"; shift 2;;
    --timeout)     TIMEOUT="$2"; shift 2;;
    --max-iter)    MAX_ITER="$2"; shift 2;;
    --prompt)      PROMPT="$2"; shift 2;;
    --status)      DO_STATUS=1; shift;;
    -h|--help)     usage; exit 0;;
    *) echo "orchestrate-loop: unknown argument '$1'" >&2; usage; exit 2;;
  esac
done

cd "$PROJECT_DIR" || { echo "orchestrate-loop: cannot cd to '$PROJECT_DIR'" >&2; exit 1; }

# --status is a read-only side door: print the snapshot and exit, never touch the loop.
if (( DO_STATUS )); then
  exec "$SCRIPT_DIR/orchestrate-status.sh" "$PROJECT_DIR"
fi

# ── Single-instance lock (one loop per project) ──────────────────────────────────────────
# Refuse to start if another loop already owns this project. This flock is the SINGLE source
# of truth for "is a loop running?" — never `pgrep -f orchestrate-loop.sh` (it over-counts the
# per-iteration heartbeat subshell; see header). Append-open (>>) so we don't truncate a live
# holder's recorded PID before reading it on the failure path.
LOCKFILE="${TMPDIR:-/tmp}/orchestrate-loop-$(basename "$PROJECT_DIR").lock"
exec 9>>"$LOCKFILE" || { echo "orchestrate-loop: cannot open lockfile $LOCKFILE" >&2; exit 1; }
if ! flock -n 9; then
  echo "orchestrate-loop: another loop already owns this project (lock: $LOCKFILE, owner PID: $(cat "$LOCKFILE" 2>/dev/null || echo unknown)) — refusing to start a duplicate." >&2
  echo "orchestrate-loop: if you're certain no loop is running (e.g. a prior loop was kill -9'd), remove the lockfile and retry." >&2
  exit 4
fi
printf '%s\n' "$$" > "$LOCKFILE"   # we own it — record our PID so a would-be duplicate can name us

# Build the launch prompt unless overridden. ALWAYS autonomous (headless has no human
# to approve the supervised gate). The orchestrator only reads a ticket scope from args
# on the FIRST launch (it records it in the tracking issue); passing it every relaunch is
# harmless — find-or-create reads scope back from the issue thereafter.
if [[ -z "$PROMPT" ]]; then
  PROMPT="Run the orchestrate-v5 skill in autonomous mode"
  [[ -n "$TICKETS" ]] && PROMPT="$PROMPT for tickets $TICKETS"
  PROMPT="$PROMPT."
fi

# The orchestrator reads N from the environment (config; default 1).
export ORCHESTRATE_N="$N"

# Durable trail for headless post-mortem (terminal scrollback is lost when unattended;
# the GitHub tracking issue remains the real observability).
RUNLOG="${TMPDIR:-/tmp}/orchestrate-loop-$(basename "$PROJECT_DIR").log"
: > "$RUNLOG"

# Heartbeat: `claude -p` emits nothing until a session ends, so without this the terminal
# and log look frozen for the whole iteration. Poll the open tracking issue every
# HEARTBEAT_INTERVAL seconds and print the current ticket+stage to stdout AND the run log.
# Restarted per iteration so it carries the live $iter; killed on EXIT and after each session.
# NOTE: this is a SUBSHELL running this same script file — `pgrep -f orchestrate-loop.sh`
# counts it as a second "loop". Never use a process count to detect duplicates; use the
# flock above. The subshell closes the lock fd (9>&-) so it never holds the lock open.
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-45}"
HB_PID=""
start_heartbeat() {
  (( HEARTBEAT_INTERVAL <= 0 )) && return 0
  local this_iter="$1"
  (
    while true; do
      sleep "$HEARTBEAT_INTERVAL"
      num=$(gh issue list --label orchestration-run --state open --json number --jq '.[0].number // empty' 2>/dev/null)
      if [[ -z "$num" ]]; then
        echo "♥ $(date -u '+%H:%M:%SZ') iter ${this_iter} · no open tracking issue yet"
      else
        cur=$(gh issue view "$num" --json body --jq '.body' 2>/dev/null \
              | grep -m1 -i 'Current ticket' | sed 's/[*`]//g; s/^[[:space:]-]*//')
        echo "♥ $(date -u '+%H:%M:%SZ') iter ${this_iter} · #${num} · ${cur:-state unavailable}"
      fi
    done
  ) 9>&- 2>/dev/null | tee -a "$RUNLOG" 9>&- &
  HB_PID=$!
}
stop_heartbeat() { [[ -n "$HB_PID" ]] && kill "$HB_PID" 2>/dev/null; HB_PID=""; }
trap 'stop_heartbeat' EXIT

echo "orchestrate-loop: project=$PROJECT_DIR N=$N timeout=${TIMEOUT}s max-iter=$MAX_ITER"
echo "orchestrate-loop: scope=${TICKETS:-full board} | log=$RUNLOG | heartbeat=${HEARTBEAT_INTERVAL}s"
echo "orchestrate-loop: prompt=\"$PROMPT\""
echo "orchestrate-loop: live progress -> tail -f $RUNLOG   |   snapshot -> $SCRIPT_DIR/orchestrate-status.sh $PROJECT_DIR"

iter=0
saw_issue=0   # set once we've observed an open tracking issue, so "none open" means CLOSED-by-fixpoint, not "not yet created"
while (( iter < MAX_ITER )); do
  iter=$(( iter + 1 ))
  echo "──── orchestrate-loop: iteration ${iter}/${MAX_ITER} ────"

  logfile="$(mktemp)"

  # Guard 1: timeout kills a hung session (exit 124). Stream output LIVE to the operator and
  # the durable run log (tee -a), and capture it to $logfile so we can grep for the sentinel.
  # The heartbeat runs concurrently so the terminal/log keep moving while claude is silent.
  echo "── iteration ${iter} · $(date -u '+%H:%M:%SZ') ──" | tee -a "$RUNLOG"
  # Remember if a tracking issue is already OPEN at launch. If a single session then adopts AND
  # closes it (e.g. a CLEANUP relaunch that reaches the fixpoint on its first iteration — the
  # exact case of re-running the loop to finish a parked run), the post-session "0 open" below
  # is a fixpoint-CLOSE, not "issue never created." Without this the loop misreads it and
  # relaunches into brand-new work (e.g. grabbing the next milestone instead of stopping).
  if gh issue list --label orchestration-run --state open --json number --jq 'length' 2>/dev/null | grep -q '^[1-9]'; then
    saw_issue=1
  fi
  start_heartbeat "$iter"
  timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions 2>&1 | tee -a "$RUNLOG" "$logfile"
  rc=${PIPESTATUS[0]}
  stop_heartbeat

  # Stop ONLY when the orchestrator has CLOSED its tracking issue — that is the durable
  # fixpoint signal (CLEANUP C5 closes the issue as its final act, gated on a green
  # regression suite). Do NOT stop on a substring match of $SENTINEL in agent output:
  # narration/summaries say "RUN_COMPLETE" without it being the real emit, and a stray match
  # would halt around a still-open run — e.g. CLEANUP left the issue OPEN because a regression
  # is still red (#377 / HC-14c: the loop saw RUN_COMPLETE in output and stopped on a known-red test).
  sentinel_seen=0; grep -q "$SENTINEL" "$logfile" 2>/dev/null && sentinel_seen=1
  rm -f "$logfile"

  open_runs=$(gh issue list --label orchestration-run --state open --json number --jq 'length' 2>/dev/null || echo "?")
  case "$open_runs" in
    0)
      # Stop if we ever saw this run's issue open (pre- or post-session) OR the session emitted
      # the real RUN_COMPLETE: with zero open issues, both mean the run reached its fixpoint and
      # closed. (sentinel_seen is safe to trust HERE — the issue is genuinely gone; the #377
      # "don't trust a substring" caveat only applies while an issue is still OPEN, below.)
      if (( saw_issue || sentinel_seen )); then
        echo "──── orchestrate-loop: tracking issue CLOSED / $SENTINEL — run reached fixpoint. Stopping. ────"
        exit 0
      fi
      echo "orchestrate-loop: no tracking issue yet (orchestrator hasn't created it) — relaunching." ;;
    [1-9]*)
      saw_issue=1
      # Parked at a human gate? A milestone gate (orchestrate-v5 Stage 1a.1) sets
      # `Run state: AWAITING_HUMAN` in the tracking-issue body before it halts. A headless loop
      # can NOT clear a human gate, so relaunching just re-hits the same gate every iteration —
      # a 50-iteration spin (the operator ends up Ctrl-C'ing). Stop cleanly and tell them how to
      # resume instead. The issue stays OPEN, so a re-run picks the run back up.
      hnum=$(gh issue list --label orchestration-run --state open --json number --jq '.[0].number // empty' 2>/dev/null)
      if [[ -n "$hnum" ]] && gh issue view "$hnum" --json body --jq '.body' 2>/dev/null \
           | grep -qi 'Run state:[[:space:]]*\**[[:space:]]*AWAITING_HUMAN'; then
        echo "──── orchestrate-loop: run PAUSED at a human gate (issue #${hnum}) — not relaunching. ────"
        echo "orchestrate-loop: approve via the issue's Operator-message slot (or rescope past the gate), then re-run." >&2
        exit 0
      fi
      if (( sentinel_seen )); then
        echo "orchestrate-loop: NOTE — session emitted $SENTINEL but the tracking issue is still OPEN; NOT stopping (a red bar or pending inject keeps the run live)."
      fi ;;
    *)
      echo "orchestrate-loop: WARNING — could not read tracking-issue state (gh error); relaunching cautiously." ;;
  esac

  # Guards 2: relaunch on any exit (clean, crash, or timeout) until the tracking issue is CLOSED.
  if (( rc == 124 )); then
    echo "orchestrate-loop: session TIMED OUT after ${TIMEOUT}s — relaunching (hang guard)."
  elif (( rc != 0 )); then
    echo "orchestrate-loop: session exited rc=${rc} — relaunching (crash guard)."
  else
    echo "orchestrate-loop: session exited cleanly, tracking issue still open — work remains, relaunching."
  fi
done

# Guard 3: circuit breaker tripped.
echo "orchestrate-loop: hit MAX_ITER=${MAX_ITER} without the tracking issue being closed." >&2
echo "orchestrate-loop: CIRCUIT BREAKER — halting and flagging a human. Investigate before re-running." >&2
exit 3
