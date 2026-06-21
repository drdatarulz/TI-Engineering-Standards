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
# Defaults: --project-dir "$(pwd)"  --n 3  --timeout 1800  --max-iter 50
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
TIMEOUT=1800        # per-session timeout, seconds
MAX_ITER=50         # circuit breaker: hard cap on relaunches
TICKETS=""          # optional scope, e.g. "#7,#8,#9"; empty = full board
PROMPT=""           # empty = auto-build an autonomous-mode prompt (below)
SENTINEL="RUN_COMPLETE"

usage() { sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --n)           N="$2"; shift 2;;
    --tickets)     TICKETS="$2"; shift 2;;
    --timeout)     TIMEOUT="$2"; shift 2;;
    --max-iter)    MAX_ITER="$2"; shift 2;;
    --prompt)      PROMPT="$2"; shift 2;;
    -h|--help)     usage; exit 0;;
    *) echo "orchestrate-loop: unknown argument '$1'" >&2; usage; exit 2;;
  esac
done

cd "$PROJECT_DIR" || { echo "orchestrate-loop: cannot cd to '$PROJECT_DIR'" >&2; exit 1; }

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

echo "orchestrate-loop: project=$PROJECT_DIR N=$N timeout=${TIMEOUT}s max-iter=$MAX_ITER"
echo "orchestrate-loop: scope=${TICKETS:-full board} | log=$RUNLOG"
echo "orchestrate-loop: prompt=\"$PROMPT\""

iter=0
while (( iter < MAX_ITER )); do
  iter=$(( iter + 1 ))
  echo "──── orchestrate-loop: iteration ${iter}/${MAX_ITER} ────"

  logfile="$(mktemp)"

  # Guard 1: timeout kills a hung session (exit 124). Stream output to the operator and
  # capture it so we can grep for the sentinel; append to the durable run log too.
  echo "── iteration ${iter} ──" >> "$RUNLOG"
  timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions 2>&1 | tee "$logfile"
  rc=${PIPESTATUS[0]}
  cat "$logfile" >> "$RUNLOG"

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
