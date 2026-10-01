#!/usr/bin/env bash
# Canonical "dumb driver" for the v6 orchestrator (notes/multi-orchestrator-plan.md).
#
# Its job is to relaunch a fresh `claude -p` session until ONE run reaches a fixpoint. Unlike
# v5, a run is EXPLICIT: the loop is bound to one `orchestration-run` tracking issue by number
# and holds that number (exported as ORCHESTRATE_RUN) for every relaunch. That is what lets
# several orchestrators work the same repo at once, each in its own clone, each on its own run.
# All pipeline intelligence still lives in the `orchestrate-v6` skill.
#
# LAUNCH MODES (the whole contract — exactly one of --tickets / --run):
#   --tickets "#7,#8,#9"  START a new run for exactly these tickets (issue numbers only, order
#                         = processing order). The loop creates the run issue itself before the
#                         first session (minimal body; the first session fills in the rest), after
#                         checking no other open run already owns any of these tickets.
#   --run 123             CONTINUE run #123 (must be open and labeled orchestration-run). This is
#                         also how you resume after Ctrl-C, a crash, MAX_ITER, or AWAITING_HUMAN.
#   neither / both        refuse, exit 2, no session launched.
# There is no "full board" mode: the loop never looks at the board for work.
#
# STOP CONDITION: the bound run issue is CLOSED (CLEANUP C5 closes it at the fixpoint). A gh
# error reading it is never treated as closed — the loop relaunches cautiously.
#
# GUARDS:
#   1. per-session timeout    — a hung session is killed and relaunched
#   2. relaunch-on-exit       — a crashed session is relaunched (crash watchdog)
#   3. max-iterations cap     — runaway backstop: halt and flag a human (circuit breaker)
#   4. usage-limit wait       — a session that died on the Claude usage/rate limit is NOT a crash:
#                               the loop marks `Run state: LIMIT_WAIT`, sleeps until the reset time
#                               (if the message gives one) or LIMIT_WAIT_SECS, then relaunches.
#                               Limit waits don't count toward MAX_ITER.
#
# SESSION ENDINGS: right after each session exits, the loop records why it ended — one line in the
# run log and an event-log comment on the run issue (backgrounded, never waited on):
#   ⏱ session N timed out after Ts   ⏸ session N hit the usage limit
#   ✖ session N crashed (rc=R)       ■ session N ended cleanly
# The same ending (timed-out | limit-wait | crashed:R | clean; `none` before the first session of a
# launch) is exported to the NEXT session as ORCHESTRATE_PREVIOUS_SESSION_END and sent on that
# session's TimeIt pings as --previous-session-end. A session retried after a usage-limit wait keeps
# its number, and its line says so.
#
# SINGLE-INSTANCE LOCK: one loop per CLONE. The flock is keyed on the full project path (not the
# folder name), so two clones of one repo on one machine don't block each other. Never use
# `pgrep -f` to detect a running loop — the per-iteration heartbeat is a subshell of this file.
# One DRIVER per RUN is an operator rule (don't `--run 123` from two places at once).
#
# Usage:
#   ./orchestrate-loop-v6.sh (--tickets "#7,#8" | --run N) [--project-dir DIR] [--n N]
#                            [--timeout SECONDS] [--max-iter COUNT] [--prompt TEXT]
#   ./orchestrate-loop-v6.sh --status [RUN] [--project-dir DIR]   # snapshot, then exit
# Defaults: --project-dir "$(pwd)"  --n 1  --timeout 5400  --max-iter 50
# Env: HEARTBEAT_INTERVAL (45), LIMIT_WAIT_SECS (3600), LIMIT_MAX_WAITS (48), LIMIT_MAX_SLEEP (21600),
#      LIMIT_PATTERN / LIMIT_PATTERN_LOOSE (extended regexes matched against the last lines of
#      session output; the loose one only on a non-zero exit).
set -uo pipefail

PROJECT_DIR="$(pwd)"
N=1                 # tickets per WORKING chunk (one ticket per relaunch = freshest context)
TIMEOUT=5400        # per-session HANG guard (90m), not a work budget
MAX_ITER=50         # circuit breaker: cap on relaunches (limit waits excluded)
TICKETS=""
RUN=""
PROMPT=""
DO_STATUS=0
STATUS_RUN=""
LIMIT_WAIT_SECS="${LIMIT_WAIT_SECS:-3600}"
LIMIT_MAX_WAITS="${LIMIT_MAX_WAITS:-48}"
LIMIT_MAX_SLEEP="${LIMIT_MAX_SLEEP:-21600}"   # cap on one parsed-reset sleep (6h)
# Claude usage/rate-limit exit, matched case-insensitively against the TAIL of the session output
# only (the error is the last thing printed). LIMIT_PATTERN is specific enough to trust on any exit;
# LIMIT_PATTERN_LOOSE (a bare 429 or "rate limit", which a normal summary could mention — e.g. issue
# #429) only counts when the session exited non-zero. Extend when a new wording is seen.
LIMIT_PATTERN="${LIMIT_PATTERN:-rate_limit_error|usage limit|limit reached}"
LIMIT_PATTERN_LOOSE="${LIMIT_PATTERN_LOOSE:-\\b429\\b|rate limit}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="orchestration-run"

usage() { sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
need()  { [[ $# -ge 2 && -n "$2" ]] || { echo "orchestrate-loop-v6: $1 needs a value" >&2; exit 2; }; }
die()   { echo "orchestrate-loop-v6: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) need "$@"; PROJECT_DIR="$2"; shift 2;;
    --n)           need "$@"; N="$2"; shift 2;;
    --tickets)     need "$@"; TICKETS="$2"; shift 2;;
    --run)         need "$@"; RUN="$2"; shift 2;;
    --timeout)     need "$@"; TIMEOUT="$2"; shift 2;;
    --max-iter)    need "$@"; MAX_ITER="$2"; shift 2;;
    --prompt)      need "$@"; PROMPT="$2"; shift 2;;
    --status)      DO_STATUS=1; shift
                   if [[ $# -gt 0 && "$1" != --* ]]; then STATUS_RUN="$1"; shift; fi;;
    -h|--help)     usage; exit 0;;
    *) echo "orchestrate-loop-v6: unknown argument '$1'" >&2; usage; exit 2;;
  esac
done

cd "$PROJECT_DIR" || { echo "orchestrate-loop-v6: cannot cd to '$PROJECT_DIR'" >&2; exit 1; }
PROJECT_DIR="$(pwd -P)"

if (( DO_STATUS )); then
  exec "$SCRIPT_DIR/orchestrate-status-v6.sh" "$PROJECT_DIR" ${STATUS_RUN:+"$STATUS_RUN"}
fi

# ── Launch-mode rule: exactly one of --tickets / --run ───────────────────────────────────
if [[ -n "$TICKETS" && -n "$RUN" ]]; then
  die "pass --tickets or --run, not both."
fi
if [[ -z "$TICKETS" && -z "$RUN" ]]; then
  die "no run and no tickets given. Pass --tickets \"#7,#8\" to start a run or --run N to continue one."
fi

# --tickets → normalized "#7,#8" (issue numbers only; order preserved; duplicates dropped)
SCOPE=""
if [[ -n "$TICKETS" ]]; then
  seen=" "
  for t in $(tr ',' ' ' <<<"$TICKETS"); do
    t="${t#\#}"
    [[ "$t" =~ ^[0-9]+$ ]] || die "--tickets takes issue numbers only (e.g. \"#7,#8\"); got '$t'."
    [[ "$seen" == *" $t "* ]] && continue
    seen="$seen$t "
    SCOPE="${SCOPE:+$SCOPE,}#$t"
  done
  [[ -n "$SCOPE" ]] || die "--tickets is empty."
fi
if [[ -n "$RUN" ]]; then
  RUN="${RUN#\#}"
  [[ "$RUN" =~ ^[0-9]+$ ]] || die "--run takes an issue number; got '$RUN'."
fi

# ── Single-instance lock (one loop per clone), keyed on the full path ─────────────────────
KEY="$(basename "$PROJECT_DIR")-$(printf '%s' "$PROJECT_DIR" | sha1sum | cut -c1-8)"
LOCKFILE="${TMPDIR:-/tmp}/orchestrate-loop-v6-$KEY.lock"
exec 9>>"$LOCKFILE" || { echo "orchestrate-loop-v6: cannot open lockfile $LOCKFILE" >&2; exit 1; }
if ! flock -n 9; then
  echo "orchestrate-loop-v6: another loop already owns this clone (lock: $LOCKFILE, owner PID: $(cat "$LOCKFILE" 2>/dev/null || echo unknown)) — refusing to start a duplicate." >&2
  echo "orchestrate-loop-v6: if you're certain no loop is running (e.g. a prior loop was kill -9'd), remove the lockfile and retry." >&2
  exit 4
fi
printf '%s\n' "$$" > "$LOCKFILE"

# scope_numbers <body> → one bare issue number per line from the body's "Scope:" field
scope_numbers() {
  printf '%s\n' "$1" | grep -m1 -i 'Scope:' | sed 's/[*`]//g; s/.*Scope:[[:space:]]*//I' \
    | grep -oE '#?[0-9]+' | tr -d '#'
}
# overlap_with_open_runs <scope "#7,#8"> [exclude-run] → prints "ticket run" pairs that clash
overlap_with_open_runs() {
  local mine="$1" exclude="${2:-}" runs num body t
  runs=$(gh issue list --label "$LABEL" --state open --limit 100 --json number,body \
           --jq '.[] | @base64') || return 2
  for r in $runs; do
    num=$(base64 -d <<<"$r" | jq -r .number)
    [[ -n "$exclude" && "$num" == "$exclude" ]] && continue
    body=$(base64 -d <<<"$r" | jq -r .body)
    for t in $(scope_numbers "$body"); do
      [[ ",$mine," == *",#$t,"* ]] && echo "$t $num"
    done
  done
  return 0
}

# ── Bind the run ─────────────────────────────────────────────────────────────────────────
TIMEIT_RUN_URL=""   # the run issue's URL; TimeIt derives its run ID from it (TimeIt D-44)
if [[ -n "$SCOPE" ]]; then
  gh label create "$LABEL" --color FBCA04 --description "Active orchestration run" >/dev/null 2>&1 || true

  clash=$(overlap_with_open_runs "$SCOPE") || die "could not read open runs to check scope overlap (gh error) — not starting."
  if [[ -n "$clash" ]]; then
    while read -r t n; do echo "orchestrate-loop-v6: ticket #$t is already in open run #$n." >&2; done <<<"$clash"
    die "scope overlaps an open run — not starting. Pick other tickets, or continue that run with --run."
  fi

  BODY="## Orchestration Run

### 📨 Operator message (read FIRST each session, and re-read before every body write — Step 0.55)
none

**Mode (last session):** —
**Run state:** WORKING
**Chunk size N:** $N   **Scope:** $SCOPE
"
  url=$(gh issue create --title "Orchestration run — $(date -u +%Y-%m-%dT%H:%MZ)" \
          --label "$LABEL" --body "$BODY") || die "could not create the run issue (gh error)."
  RUN="${url##*/}"
  TIMEIT_RUN_URL="$url"
  [[ "$RUN" =~ ^[0-9]+$ ]] || die "could not read the new run issue number from '$url'."
  echo "orchestrate-loop-v6: created run #$RUN for $SCOPE"

  # Post-create re-check closes the same-moment race: the NEWER run (higher number) yields.
  clash=$(overlap_with_open_runs "$SCOPE" "$RUN") || clash=""
  older=""
  while read -r t n; do
    [[ -n "$n" && "$n" -lt "$RUN" ]] && older="$n"
  done <<<"$clash"
  if [[ -n "$older" ]]; then
    gh issue close "$RUN" --comment "⚠ closed — scope overlap with #$older (another run was created for the same tickets at the same moment)." >/dev/null 2>&1
    die "run #$RUN overlaps run #$older created at the same moment — closed #$RUN, not starting."
  fi
else
  info=$(gh issue view "$RUN" --json state,labels,comments,url 2>/dev/null) \
    || die "could not read issue #$RUN (not found, or gh error)."
  jq -e --arg l "$LABEL" '[.labels[].name] | index($l)' <<<"$info" >/dev/null \
    || die "issue #$RUN is not an $LABEL issue."
  if [[ "$(jq -r .state <<<"$info")" != "OPEN" ]]; then
    if jq -e '[.comments[].body | startswith("⚠ closed — scope overlap")] | any' <<<"$info" >/dev/null; then
      die "run #$RUN was closed over a scope overlap — see its last comment. Start a new run with --tickets."
    fi
    die "run #$RUN is closed (already complete). Start a new run with --tickets."
  fi
  TIMEIT_RUN_URL=$(jq -r '.url // empty' <<<"$info" 2>/dev/null) || TIMEIT_RUN_URL=""
fi

export ORCHESTRATE_RUN="$RUN"
export ORCHESTRATE_N="$N"
# Tells TimeIt's interactive-session hook that sessions launched here are the loop's, not a person's
# (TimeIt FR-3.3). Harmless when TimeIt isn't installed.
export TI_MODE=autonomous

if [[ -z "$PROMPT" ]]; then
  # Read the skill file directly — orchestrate-v6 is `disable-model-invocation: true`, so it
  # can't be loaded by name. Restate Step 0.0 inline so the session never mistakes this loop's
  # own lock for a competitor.
  PROMPT="You ARE the v6 orchestrator. Read .claude/skills/orchestrate-v6/SKILL.md in full and execute it directly in autonomous mode, bound to orchestration run #$RUN (ORCHESTRATE_RUN=$RUN is exported; load that tracking issue in Step 0.5 — do not search for or create another run). Do NOT invoke it as a named skill (model-invocation is disabled) — read the file and follow it. Per its Step 0.0: this relaunch loop IS your own run — a running parent orchestrate-loop-v6.sh process and its held lock are never a competitor. Do NOT check the lockfile, do NOT count loop processes, and NEVER refuse to start because something looks concurrent."
fi

RUNLOG="${TMPDIR:-/tmp}/orchestrate-loop-v6-$KEY.log"
: > "$RUNLOG"

# set_run_state <text> — replace the body's "Run state:" line (read-modify-write of the LIVE
# body). Only called between sessions, when no session is writing the body.
set_run_state() {
  local live
  live=$(gh issue view "$RUN" --json body --jq .body 2>/dev/null) || return 1
  live=$(printf '%s\n' "$live" | sed "s/^\*\*Run state:\*\*.*/**Run state:** $1/")
  gh issue edit "$RUN" --body "$live" >/dev/null 2>&1
}

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-45}"
HB_PID=""
start_heartbeat() {
  (( HEARTBEAT_INTERVAL <= 0 )) && return 0
  local this_iter="$1"
  (
    while true; do
      sleep "$HEARTBEAT_INTERVAL"
      cur=$(gh issue view "$RUN" --json body --jq '.body' 2>/dev/null \
            | grep -m1 -i 'Current ticket' | sed 's/[*`]//g; s/^[[:space:]-]*//')
      echo "♥ $(date -u '+%H:%M:%SZ') iter ${this_iter} · run #${RUN} · ${cur:-state unavailable}"
    done
  ) 9>&- 2>/dev/null | tee -a "$RUNLOG" 9>&- &
  HB_PID=$!
}
stop_heartbeat() { [[ -n "$HB_PID" ]] && kill "$HB_PID" 2>/dev/null; HB_PID=""; }
TIMEIT_PID=""; TIMEIT_DIR=""   # TimeIt agent-ping timer (below); set before the trap so on_exit can read them
on_exit() { local rc=$?; stop_heartbeat; stop_timeit_ping; (( rc != 0 )) && echo "orchestrate-loop-v6: run #$RUN stopped — resume with: --run $RUN" >&2; }
trap on_exit EXIT

# ── TimeIt agent pings (TimeIt FR-3, D-8, D-37, D-42, D-44) ──────────────────────────────
# Inert unless TimeIt's machine scripts are installed (timeit-agent-ping on the PATH or in
# ~/.local/bin). Its own timer, never the display heartbeat (which is off at HEARTBEAT_INTERVAL=0
# and between sessions). Silent, backgrounded, fd 9 closed on everything it starts, never waits
# on gh, and stops when this loop exits or dies. The timer is a subshell, so the loop hands it
# the run ID, state (working | waiting during a usage-limit wait), iteration, current ticket and
# scope through files in a private temp folder. No final ping: a run's end is its last ping.
TIMEIT_CMD="$(command -v timeit-agent-ping 2>/dev/null)"
[[ -z "$TIMEIT_CMD" && -n "${HOME:-}" && -x "${HOME:-}/.local/bin/timeit-agent-ping" ]] \
  && TIMEIT_CMD="${HOME:-}/.local/bin/timeit-agent-ping"
# TIMEIT_PING_INTERVAL: 1-120 s, else 45 (D-3). Over 180 s every gap would exceed TimeIt's ping-gap
# allowance and bill nothing. Regex first, so the numeric test never sees a non-number.
TIMEIT_INTERVAL=45
if [[ "${TIMEIT_PING_INTERVAL:-}" =~ ^[1-9][0-9]{0,2}$ ]] && [[ "$TIMEIT_PING_INTERVAL" -le 120 ]]; then
  TIMEIT_INTERVAL="$TIMEIT_PING_INTERVAL"
fi

# timeit_write <name> <value> / timeit_read <name> — the timer's state files (temp file + mv)
timeit_write() {
  [[ -n "$TIMEIT_DIR" ]] || return 0
  { printf '%s' "$2" > "$TIMEIT_DIR/$1.tmp.$BASHPID" && mv -f "$TIMEIT_DIR/$1.tmp.$BASHPID" "$TIMEIT_DIR/$1"; } 2>/dev/null
  return 0
}
timeit_read() {
  local v=""
  [[ -n "$TIMEIT_DIR" && -f "$TIMEIT_DIR/$1" ]] && { v=$(<"$TIMEIT_DIR/$1"); } 2>/dev/null
  printf '%s' "$v"
}
# timeit_run_id — one UUID per run, derived from the run issue URL the loop already holds, so every
# launch of run #N (--tickets, then each --run N) joins one TimeIt run (D-44). No gh call. Only if
# the URL is empty: a random UUID for this launch. Prints nothing when neither is possible.
timeit_run_id() {
  local h v
  if [[ -n "$TIMEIT_RUN_URL" ]]; then
    h=$(printf 'timeit-run:%s' "$TIMEIT_RUN_URL" | sha1sum 2>/dev/null | cut -c1-32)
    if [[ "$h" =~ ^[0-9a-f]{32}$ ]]; then
      v=$(printf '%x' $(( (0x${h:16:1} & 3) | 8 )))
      printf '%s-%s-5%s-%s%s-%s' "${h:0:8}" "${h:8:4}" "${h:13:3}" "$v" "${h:17:3}" "${h:20:12}"
      return 0
    fi
  fi
  h=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
  [[ "$h" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && printf '%s' "$h"
  return 0
}
# timeit_ping [--bg] [extra options] — one bounded, silent call with the last known values; empty
# optional values are left out (an empty argument could swallow the next option). --bg reads the
# values now and backgrounds only the call, so it still goes out if the loop exits right after.
timeit_ping() {
  local id st it tk sc bg=0
  [[ "${1:-}" == --bg ]] && { bg=1; shift; }
  [[ -n "$TIMEIT_CMD" && -n "$TIMEIT_DIR" ]] || return 0
  id=$(timeit_read runid); [[ -n "$id" ]] || return 0
  st=$(timeit_read state); [[ "$st" == waiting ]] || st=working
  it=$(timeit_read iter); tk=$(timeit_read ticket); sc=$(timeit_read scope)
  local sg pe
  sg=$(timeit_read stage); pe=$(timeit_read prevend)
  local args=(--run-id "$id" --worker-id 1 --state "$st" --project-dir "$PROJECT_DIR")
  [[ -n "$sc" ]] && args+=(--ticket-scope "$sc")
  [[ -n "$tk" ]] && args+=(--current-ticket "$tk")
  [[ -n "$it" ]] && args+=(--iteration "$it")
  [[ -n "$sg" ]] && args+=(--stage "$sg")
  [[ -n "$pe" ]] && args+=(--previous-session-end "$pe")
  if (( bg )); then
    timeout 10 "$TIMEIT_CMD" "${args[@]}" "$@" </dev/null >/dev/null 2>&1 9>&- &
  else
    timeout 10 "$TIMEIT_CMD" "${args[@]}" "$@" </dev/null >/dev/null 2>&1 9>&-
  fi
  return 0
}
# timeit_poll — one bounded read of the run body (the same read as the heartbeat): the current
# ticket (Story ID before " @"; none/absent → no ticket), the stage, and the Scope: field as
# "#a,#b". A failed or timed-out read keeps the last known values.
timeit_poll() {
  local body line t="" sc="" n
  body=$(timeout 20 gh issue view "$RUN" --json body --jq .body 2>/dev/null) || return 0
  line=$(printf '%s\n' "$body" | grep -m1 -i 'Current ticket' | tr -d '\r' | sed 's/[*`]//g')
  if [[ "$line" == *:* ]]; then
    t="${line#*:}"
    t="${t%% @*}"
    t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"
    [[ "${t,,}" == none ]] && t=""
  fi
  timeit_write ticket "$t"
  timeit_write stage "$(timeit_stage "$line")"
  for n in $(scope_numbers "$body"); do sc="${sc:+$sc,}#$n"; done
  [[ -n "$sc" ]] && timeit_write scope "$sc"
  return 0
}
# timeit_stage <Current ticket line> — the stage for --stage, built only from these parts of the
# line: "@ Stage {n} ({name})" → "{n} {name}" (name lowercased), "@ CLEANUP" → "CLEANUP", plus
# " (waiting on CI)" when the line has "— waiting on CI". Plain ASCII only (TimeIt strips non-ASCII
# bytes on machines without iconv). Prints nothing when no stage can be read.
timeit_stage() {
  local line="$1" sg=""
  if [[ "$line" =~ @[[:space:]]*Stage[[:space:]]+([0-9]+[0-9a-z.]*)[[:space:]]*\(([A-Za-z][A-Za-z -]*)\) ]]; then
    sg="${BASH_REMATCH[1]%.} ${BASH_REMATCH[2],,}"
    sg="${sg%"${sg##*[![:space:]]}"}"
  elif [[ "$line" =~ @[[:space:]]*CLEANUP ]]; then
    sg="CLEANUP"
  fi
  [[ -n "$sg" && "$line" == *"— waiting on CI"* ]] && sg="$sg (waiting on CI)"
  printf '%s' "$sg"
}
# start_timeit_ping — once per launch, after the run is bound. Each tick: stop if the loop is gone
# (so a kill -9'd loop never bills), ping, start a body read unless one is still running, sleep.
start_timeit_ping() {
  local id loop_pid="$$"
  [[ -n "$TIMEIT_CMD" ]] || return 0
  id=$(timeit_run_id)
  [[ -n "$id" ]] || return 0
  TIMEIT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/timeit-loop.XXXXXX" 2>/dev/null) || TIMEIT_DIR=""
  [[ -n "$TIMEIT_DIR" && -d "$TIMEIT_DIR" ]] || { TIMEIT_DIR=""; return 0; }
  timeit_write runid "$id"
  timeit_write state working
  timeit_write scope "$SCOPE"
  timeit_write prevend none
  (
    poll_pid=""
    while kill -0 "$loop_pid" 2>/dev/null; do
      timeit_ping
      if [[ -z "$poll_pid" ]] || ! kill -0 "$poll_pid" 2>/dev/null; then
        timeit_poll </dev/null >/dev/null 2>&1 9>&- &
        poll_pid=$!
      fi
      sleep "$TIMEIT_INTERVAL"
    done
  ) 9>&- </dev/null >/dev/null 2>&1 &
  TIMEIT_PID=$!
  disown "$TIMEIT_PID" 2>/dev/null
  return 0
}
stop_timeit_ping() {
  [[ -n "$TIMEIT_PID" ]] && kill "$TIMEIT_PID" 2>/dev/null
  TIMEIT_PID=""
  [[ -n "$TIMEIT_DIR" ]] && rm -rf "$TIMEIT_DIR" 2>/dev/null
  TIMEIT_DIR=""
  return 0
}

echo "orchestrate-loop-v6: project=$PROJECT_DIR run=#$RUN N=$N timeout=${TIMEOUT}s max-iter=$MAX_ITER"
echo "orchestrate-loop-v6: log=$RUNLOG | heartbeat=${HEARTBEAT_INTERVAL}s"
echo "orchestrate-loop-v6: resume later with: --run $RUN"
echo "orchestrate-loop-v6: live progress -> tail -f $RUNLOG   |   snapshot -> $SCRIPT_DIR/orchestrate-status-v6.sh $PROJECT_DIR $RUN"

start_timeit_ping
# record_session_end <line> — the session ending, to the terminal, the run log and (fully detached,
# never waited on, never failing the loop) an event-log comment on the run issue.
record_session_end() {
  echo "$1" | tee -a "$RUNLOG" 9>&-
  timeout 20 gh issue comment "$RUN" --body "$1" </dev/null >/dev/null 2>&1 9>&- &
  disown $! 2>/dev/null
  return 0
}

iter=0
limit_waits=0
prev_end=none     # how the previous session of this launch ended (ORCHESTRATE_PREVIOUS_SESSION_END)
retry=0           # 1 when this session re-runs the number of one that hit the usage limit
while (( iter < MAX_ITER )); do
  iter=$(( iter + 1 ))
  timeit_write iter "$iter"
  timeit_write state working
  timeit_write prevend "$prev_end"
  export ORCHESTRATE_PREVIOUS_SESSION_END="$prev_end"
  echo "──── orchestrate-loop-v6: run #${RUN} · iteration ${iter}/${MAX_ITER} ────"
  logfile="$(mktemp)"
  echo "── iteration ${iter} · $(date -u '+%H:%M:%SZ') ──" | tee -a "$RUNLOG" 9>&-
  start_heartbeat "$iter"
  # Close the lock fd (9) for the session and tee so long-lived background descendants of
  # `claude -p` never inherit the flock (see v5 loop notes).
  timeout "$TIMEOUT" claude -p "$PROMPT" --dangerously-skip-permissions 9>&- 2>&1 | tee -a "$RUNLOG" "$logfile" 9>&-
  rc=${PIPESTATUS[0]}
  stop_heartbeat
  # D-6: flag the hang-guard timeout to TimeIt at once (backgrounded; holds neither fd 9 nor stdout).
  if (( rc == 124 )) && [[ -n "$TIMEIT_PID" ]]; then
    timeit_ping --bg --timed-out </dev/null >/dev/null 2>&1 9>&-
  fi

  limit_hit=0
  if tail -n 15 "$logfile" | grep -Eiq "$LIMIT_PATTERN"; then limit_hit=1
  elif (( rc != 0 )) && tail -n 15 "$logfile" | grep -Eiq "$LIMIT_PATTERN_LOOSE"; then limit_hit=1; fi
  reset_line=$(tail -n 15 "$logfile" | grep -Eio 'reset[s]?( at)? [0-9]{1,2}(:[0-9]{2})? ?([ap]m)?' | tail -1)
  reset_tz=$(tail -n 15 "$logfile" | grep -Eo '\([A-Za-z_]+/[A-Za-z_]+\)' | tail -1 | tr -d '()')
  rm -f "$logfile"

  # Record why the session ended — before the run-state check below, which can exit.
  if (( limit_hit )); then
    end="limit-wait"; line="⏸ session ${iter} hit the usage limit"
  elif (( rc == 124 )); then
    end="timed-out";  line="⏱ session ${iter} timed out after ${TIMEOUT}s"
  elif (( rc != 0 )); then
    end="crashed:$rc"; line="✖ session ${iter} crashed (rc=${rc})"
  else
    end="clean";      line="■ session ${iter} ended cleanly"
  fi
  (( retry )) && line="$line (retry after a usage-limit wait)"
  record_session_end "$line"
  prev_end="$end"
  retry=$limit_hit

  # Stop ONLY when the bound run issue is CLOSED (never on a stdout substring).
  state=$(gh issue view "$RUN" --json state --jq .state 2>/dev/null || echo "?")
  case "$state" in
    CLOSED)
      echo "──── orchestrate-loop-v6: run #$RUN CLOSED — fixpoint reached. Stopping. ────"
      exit 0 ;;
    OPEN)
      if gh issue view "$RUN" --json body --jq '.body' 2>/dev/null \
           | grep -qi 'Run state:[[:space:]]*\**[[:space:]]*AWAITING_HUMAN'; then
        echo "──── orchestrate-loop-v6: run #$RUN PAUSED at a human gate — not relaunching. ────"
        echo "orchestrate-loop-v6: approve via the issue's Operator-message slot, then re-run with --run $RUN." >&2
        exit 0
      fi ;;
    *)
      echo "orchestrate-loop-v6: WARNING — could not read run #$RUN state (gh error); relaunching cautiously." ;;
  esac

  # Guard 4: usage/rate-limit exit → wait, don't burn an iteration.
  if (( limit_hit )); then
    limit_waits=$(( limit_waits + 1 ))
    if (( limit_waits > LIMIT_MAX_WAITS )); then
      echo "orchestrate-loop-v6: usage limit still hit after $LIMIT_MAX_WAITS waits — halting; resume later with --run $RUN." >&2
      exit 5
    fi
    iter=$(( iter - 1 ))
    wait_s="$LIMIT_WAIT_SECS"
    if [[ -n "$reset_line" ]]; then
      t="$(sed -E 's/^reset[s]?( at)? //I' <<<"$reset_line")"
      # Honor a timezone printed with the reset time, e.g. "resets 3pm (America/New_York)".
      if target=$(date -d "${reset_tz:+TZ=\"$reset_tz\" }$t" +%s 2>/dev/null); then
        now=$(date +%s); (( target <= now )) && target=$(( target + 86400 ))
        wait_s=$(( target - now + 60 + RANDOM % 120 ))
        # Never sleep longer than LIMIT_MAX_SLEEP in one go: if the parse was off, re-check sooner.
        (( wait_s > LIMIT_MAX_SLEEP )) && wait_s="$LIMIT_MAX_SLEEP"
      fi
    fi
    retry_at=$(date -d "@$(( $(date +%s) + wait_s ))" '+%H:%M' 2>/dev/null || echo "?")
    timeit_write state waiting   # before set_run_state: its gh calls have no timeout (D-42)
    echo "orchestrate-loop-v6: session hit the Claude usage/rate limit — LIMIT_WAIT ${wait_s}s (retry ~$retry_at), not counted toward MAX_ITER." | tee -a "$RUNLOG"
    set_run_state "LIMIT_WAIT (retry ~$retry_at)" || true
    sleep "$wait_s"
    continue
  fi
  limit_waits=0

  if (( rc == 124 )); then
    echo "orchestrate-loop-v6: session TIMED OUT after ${TIMEOUT}s — relaunching (hang guard)."
  elif (( rc != 0 )); then
    echo "orchestrate-loop-v6: session exited rc=${rc} — relaunching (crash guard)."
  else
    echo "orchestrate-loop-v6: session exited cleanly, run #$RUN still open — work remains, relaunching."
  fi
done

echo "orchestrate-loop-v6: hit MAX_ITER=${MAX_ITER} without run #$RUN being closed." >&2
echo "orchestrate-loop-v6: CIRCUIT BREAKER — halting and flagging a human. Investigate, then resume with --run $RUN." >&2
exit 3
