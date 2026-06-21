#!/usr/bin/env bash
# Thin per-project entrypoint for the v5 orchestration loop.
#
# Vendor this into a project as `scripts/orchestrate.sh` (it's stable and safe to commit).
# It self-updates the canonical driver from the standards repo every run, then hands off —
# all logic lives in `developer-tools/orchestrate-loop.sh` upstream, so this never drifts.
#
# Usage (from the project root):
#   ./scripts/orchestrate.sh                          # full board, N=3, autonomous
#   ./scripts/orchestrate.sh --tickets "#7,#8,#9"     # scope the run to these tickets
#   ./scripts/orchestrate.sh --n 5 --timeout 2400     # any orchestrate-loop.sh flag
#
# Stop it: Ctrl-C, or it stops itself at the run's fixpoint (RUN_COMPLETE) or when the
# max-iterations circuit breaker trips. Watch progress on the GitHub `orchestration-run`
# tracking issue, not the terminal.
set -euo pipefail

STD="../TI-Engineering-Standards"
if [[ ! -d "$STD" ]]; then
  echo "scripts/orchestrate.sh: missing sibling standards repo at $STD." >&2
  echo "  clone it: git clone https://github.com/drdatarulz/TI-Engineering-Standards.git $STD" >&2
  exit 1
fi

git -C "$STD" pull --ff-only || echo "scripts/orchestrate.sh: standards pull skipped (offline?) — using local copy."

exec "$STD/developer-tools/orchestrate-loop.sh" --project-dir "$(pwd)" "$@"
