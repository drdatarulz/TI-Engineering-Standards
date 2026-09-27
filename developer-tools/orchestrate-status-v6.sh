#!/usr/bin/env bash
# One-glance status of v6 orchestration runs for a project.
#
# v6 allows several open runs at once (one per orchestrator), so:
#   no RUN given  → one line per open `orchestration-run` issue (number, run state, scope, current)
#   RUN given     → the detailed view of that run: scope, current ticket+stage, completed/injected,
#                   the CLEANUP audit fields, and the recent event-log timeline.
#
# READ-ONLY: no writes, no git pull, no board changes — safe to `watch`:
#   watch -n 30 ../TI-Engineering-Standards/developer-tools/orchestrate-status-v6.sh . 123
# Also reachable as `./scripts/orchestrate-v6.sh --status [RUN]` (that path git-pulls first).
#
# Usage: orchestrate-status-v6.sh [PROJECT_DIR] [RUN]   (default: cwd, all open runs)
set -uo pipefail

DIR="${1:-$(pwd)}"
RUN="${2:-}"; RUN="${RUN#\#}"
cd "$DIR" 2>/dev/null || { echo "orchestrate-status-v6: cannot cd to '$DIR'" >&2; exit 1; }
PROJ="$(basename "$DIR")"

# pull a single-line field's value from a body
field() { printf '%s\n' "$1" | grep -m1 -i "$2" | sed 's/[*`]//g' | sed "s/.*$2[[:space:]]*//I; s/[[:space:]]*\$//"; }

if [[ -z "$RUN" ]]; then
  runs=$(gh issue list --label orchestration-run --state open --limit 100 --json number,body \
           --jq '.[] | @base64' 2>/dev/null) || { echo "orchestrate-status-v6: gh error listing runs" >&2; exit 1; }
  if [[ -z "$runs" ]]; then
    echo "● $PROJ: no open orchestration-run issues."
    exit 0
  fi
  echo "● $PROJ open runs:"
  for r in $runs; do
    num=$(base64 -d <<<"$r" | jq -r .number)
    body=$(base64 -d <<<"$r" | jq -r .body)
    printf '  #%-6s %-28s scope %-24s current %s\n' "$num" \
      "$(field "$body" 'Run state:')" "$(field "$body" 'Scope:')" "$(field "$body" 'Current ticket:')"
  done
  echo "  (details: orchestrate-status-v6.sh $DIR <RUN>)"
  exit 0
fi

info=$(gh issue view "$RUN" --json state,createdAt,updatedAt,body 2>/dev/null) \
  || { echo "orchestrate-status-v6: cannot read issue #$RUN" >&2; exit 1; }
state=$(jq -r .state <<<"$info"); created=$(jq -r .createdAt <<<"$info")
updated=$(jq -r .updatedAt <<<"$info"); body=$(jq -r .body <<<"$info")

elapsed=""
if start_s=$(date -u -d "$created" +%s 2>/dev/null); then
  elapsed="  (elapsed $(( ( $(date -u +%s) - start_s ) / 60 ))m)"
fi
# A long gap since the last update may mean a stuck session (or a relaunch / limit-wait pause).
stale=""
if upd_s=$(date -u -d "$updated" +%s 2>/dev/null); then
  ago=$(( ( $(date -u +%s) - upd_s ) / 60 ))
  stale="last update ${ago}m ago"
  (( ago >= ${STALE_MINS:-60} )) && stale="⚠ $stale (possibly stalled)"
fi
section() { printf '%s\n' "$body" | awk -v h="$1" 'index($0,h){f=1;next} f&&/^- /{print "    "$0} f&&/^###/{exit}'; }

echo "● $PROJ orchestration-run #$RUN [$state]   $stale$elapsed"
echo "  Run state: $(field "$body" 'Run state:')"
echo "  Scope:     $(field "$body" 'Scope:')"
echo "  Current:   $(field "$body" 'Current ticket:')"
echo "  Completed: $(field "$body" 'Completed this run:')"
echo "  Injected:  $(field "$body" 'Injected this run:')"
echo "  Test pyramid (last CLEANUP):"
section 'Test pyramid'
echo "  Gate audit (last CLEANUP):"
section 'Gate audit'

echo "  ── recent event log ──"
gh issue view "$RUN" --json comments \
  --jq '.comments[-6:][] | "    [\(.createdAt|sub("T";" ")|sub("Z";""))] \(.body | gsub("\n";" ") | .[0:140])"' 2>/dev/null \
  || echo "    (no comments yet)"
