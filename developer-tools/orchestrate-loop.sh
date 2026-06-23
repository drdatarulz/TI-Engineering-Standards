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
# Usage:
#   ./orchestrate-loop.sh [--project-dir DIR] [--n N] [--tickets "#7,#8,..."]
#                         [--timeout SECONDS] [--max-iter COUNT] [--prompt TEXT]
#   ./orchestrate-loop.sh --status [--project-dir DIR]   # one-glance run status, then exit
# Defaults: --project-dir "$(pwd)"  --n 3  --timeout 3600  --max-iter 50
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
N=3                 # tickets per WORKING chunk (measured reliability threshold ~3)
TIMEOUT=3600        # per-session timeout, seconds (60m — a big story's implement stage
                    # can run ~30m; 60m leaves headroom before a hung-session kill)
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

# Build the launch prompt unless overridden. ALWAYS autonomous (headless has no human
# to approve the supervised gate). The orchestrator only reads a ticket scope from args
# on the FIRST launch (it records it in the tracking issue); passing it every relaunch is
# harmless — find-or-create reads scope back from the issue thereafter.
if [[ -z "$PROMPT" ]]; then
  PROMPT="Run the orchestrate-v5 skill in autonomous mode"
  [[ -n "$TICKETS" ]] && PROMPT="$PROMPT for tickets $TICKETS"
  PROMPT="$PROMPT."
fi

# The orchestrator reads N from the environment (config; default ~3).
export ORCHESTRATE_N="$N"

# Durable trail for headless post-mortem (terminal scrollback is lost when unattended;
# the GitHub tracking issue remains the real observability).
RUNLOG="${TMPDIR:-/tmp}/orchestrate-loop-$(basename "$PROJECT_DIR").log"
: > "$RUNLOG"

# Heartbeat: `claude -p` emits nothing until a session ends, so without this the terminal
# and log look frozen for the whole iteration. Poll the open tracking issue every
# HEARTBEAT_INTERVAL seconds and print the current ticket+stage to stdout AND the run log.
# Restarted per iteration so it carries the live $iter; killed on EXIT and after each session.
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
  ) 2>/dev/null | tee -a "$RUNLOG" &
  HB_PID=$!
}
stop_heartbeat() { [[ -n "$HB_PID" ]] && kill "$HB_PID" 2>/dev/null; HB_PID=""; }
trap 'stop_heartbeat' EXIT

echo "orchestrate-loop: project=$PROJECT_DIR N=$N timeout=${TIMEOUT}s max-iter=$MAX_ITER"
echo "orchestrate-loop: scope=${TICKETS:-full board} | log=$RUNLOG | heartbeat=${HEARTBEAT_INTERVAL}s"
echo "orchestrate-loop: prompt=\"$PROMPT\""
echo "orchestrate-loop: live progress -> tail -f $RUNLOG   |   snapshot -> $SCRIPT_DIR/orchestrate-status.sh $PROJECT_DIR"

iter=0
while (( iter < MAX_ITER )); do
  iter=$(( iter + 1 ))
  echo "──── orchestrate-loop: iteration ${iter}/${MAX_ITER} ────"

  logfile="$(mktemp)"

  # Guard 1: timeout kills a hung session (exit 124). Stream output LIVE to the operator and
  # the durable run log (tee -a), and capture it to $logfile so we can grep for the sentinel.
  # The heartbeat runs concurrently so the terminal/log keep moving while claude is silent.
  echo "── iteration ${iter} · $(date -u '+%H:%M:%SZ') ──" | tee -a "$RUNLOG"
  start_heartbeat "$iter"
  timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions 2>&1 | tee -a "$RUNLOG" "$logfile"
  rc=${PIPESTATUS[0]}
  stop_heartbeat

  if grep -q "$SENTINEL" "$logfile"; then
    echo "──── orchestrate-loop: $SENTINEL detected — run reached fixpoint. Stopping. ────"
    rm -f "$logfile"
    exit 0
  fi
  rm -f "$logfile"

  # Guards 2: relaunch on any exit (clean, crash, or timeout) until the sentinel appears.
  if (( rc == 124 )); then
    echo "orchestrate-loop: session TIMED OUT after ${TIMEOUT}s — relaunching (hang guard)."
  elif (( rc != 0 )); then
    echo "orchestrate-loop: session exited rc=${rc} — relaunching (crash guard)."
  else
    echo "orchestrate-loop: session exited cleanly without $SENTINEL — work remains, relaunching."
  fi
done

# Guard 3: circuit breaker tripped.
echo "orchestrate-loop: hit MAX_ITER=${MAX_ITER} without ${SENTINEL}." >&2
echo "orchestrate-loop: CIRCUIT BREAKER — halting and flagging a human. Investigate before re-running." >&2
exit 3
