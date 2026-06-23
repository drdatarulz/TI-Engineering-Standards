#!/usr/bin/env bash
# One-glance status of the active v5 orchestration run for a project.
#
# Finds the open `orchestration-run` tracking issue and pretty-prints scope, current
# ticket+stage, completed/injected, the CLEANUP audit fields, and the recent event-log
# timeline — turning a manual `gh issue view ... --json body` into a single command.
#
# READ-ONLY: no writes, no git pull, no board changes — safe to `watch`:
#   watch -n 30 ../TI-Engineering-Standards/developer-tools/orchestrate-status.sh .
# Also reachable as `./scripts/orchestrate.sh --status` (that path git-pulls first).
#
# Usage: orchestrate-status.sh [PROJECT_DIR]   (default: cwd)
set -uo pipefail

DIR="${1:-$(pwd)}"
cd "$DIR" 2>/dev/null || { echo "orchestrate-status: cannot cd to '$DIR'" >&2; exit 1; }
PROJ="$(basename "$DIR")"

num=$(gh issue list --label orchestration-run --state open --json number --jq '.[0].number // empty' 2>/dev/null)
if [[ -z "$num" ]]; then
  echo "● $PROJ: no open orchestration-run issue."
  echo "  (the last run finished and self-closed, or none has started)"
  exit 0
fi

read -r created updated < <(gh issue view "$num" --json createdAt,updatedAt \
  --jq '[.createdAt, .updatedAt] | @tsv' 2>/dev/null)
body=$(gh issue view "$num" --json body --jq .body 2>/dev/null)

# elapsed since run start (GNU date)
elapsed=""
if start_s=$(date -u -d "$created" +%s 2>/dev/null); then
  mins=$(( ( $(date -u +%s) - start_s ) / 60 ))
  elapsed="  (elapsed ${mins}m)"
fi
# staleness since last update — a long gap may mean a stuck session (or a relaunch pause).
# Default threshold 45m: a single long stage (a big story's implement) legitimately runs
# ~30m with no tracking-issue update, but the per-session timeout is 60m, so 45m flags a
# likely hang with headroom before the loop kills it. Override with STALE_MINS.
stale=""
if upd_s=$(date -u -d "$updated" +%s 2>/dev/null); then
  ago=$(( ( $(date -u +%s) - upd_s ) / 60 ))
  stale="last update ${ago}m ago"
  (( ago >= ${STALE_MINS:-45} )) && stale="⚠ $stale (possibly stalled)"
fi

# pull a single-line field's value: strip up to and including the (last) matched label,
# so a label sharing a line with another (e.g. "Chunk size N:** 3 **Scope:** #21,#23")
# still yields just the value.
field() { printf '%s\n' "$body" | grep -m1 -i "$1" | sed 's/[*`]//g' | sed "s/.*$1[[:space:]]*//I; s/[[:space:]]*\$//"; }
# pull the bullet line(s) that follow a section header
section() { printf '%s\n' "$body" | awk -v h="$1" 'index($0,h){f=1;next} f&&/^- /{print "    "$0} f&&/^###/{exit}'; }

echo "● $PROJ orchestration-run #$num   $stale$elapsed"
echo "  Scope:     $(field 'Scope:')"
echo "  Current:   $(field 'Current ticket:')"
echo "  Completed: $(field 'Completed this run:')"
echo "  Injected:  $(field 'Injected this run:')"
echo "  Test pyramid (last CLEANUP):"
section 'Test pyramid'
echo "  Gate audit (last CLEANUP):"
section 'Gate audit'

echo "  ── recent event log ──"
gh issue view "$num" --json comments \
  --jq '.comments[-6:][] | "    [\(.createdAt|sub("T";" ")|sub("Z";""))] \(.body | gsub("\n";" ") | .[0:140])"' 2>/dev/null \
  || echo "    (no comments yet)"
