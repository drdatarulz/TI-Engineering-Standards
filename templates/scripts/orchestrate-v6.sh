#!/usr/bin/env bash
# Thin per-project entrypoint for the v6 orchestration loop.
#
# Vendor this into a project as `scripts/orchestrate-v6.sh` (it's stable and safe to commit).
# It self-updates the canonical driver from the standards repo every run, then hands off —
# all logic lives in `developer-tools/orchestrate-loop-v6.sh` upstream, so this never drifts.
#
# Usage (from the project root) — exactly one of --tickets / --run:
#   ./scripts/orchestrate-v6.sh --tickets "#7,#8,#9"   # start a new run for these tickets
#   ./scripts/orchestrate-v6.sh --run 123              # continue (or resume) run #123
#   ./scripts/orchestrate-v6.sh --status [123]         # all open runs, or one run's detail
#   ./scripts/orchestrate-v6.sh --run 123 --n 3 --timeout 7200   # any orchestrate-loop-v6.sh flag
#
# Several orchestrators may run against one repo at once, each in its OWN clone, each on its own
# run with non-overlapping tickets. Never run v5 and v6 against the same repo.
#
# Stop it: Ctrl-C (resume with --run), or it stops itself when the run issue is closed, at a
# milestone gate, or when the max-iterations circuit breaker trips.
set -euo pipefail

STD="../TI-Engineering-Standards"
if [[ ! -d "$STD" ]]; then
  echo "scripts/orchestrate-v6.sh: missing sibling standards repo at $STD." >&2
  echo "  clone it: git clone https://github.com/drdatarulz/TI-Engineering-Standards.git $STD" >&2
  exit 1
fi

git -C "$STD" pull --ff-only || echo "scripts/orchestrate-v6.sh: standards pull skipped (offline?) — using local copy."

exec "$STD/developer-tools/orchestrate-loop-v6.sh" --project-dir "$(pwd)" "$@"
