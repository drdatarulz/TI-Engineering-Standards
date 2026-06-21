#!/usr/bin/env bash
# Configure branch protection on a v5 project's main branch:
#   * require the `fast-tests` and `integration-tests` status checks
#   * require the branch to be up to date with main before merging (strict)
#
# Branch protection is GitHub *settings*, not a committed file — so the reusable artifact
# is this script. Run it once per repo (re-running is safe; the API call is idempotent).
# `ui-tests` is intentionally NOT required — the UI tier runs at the orchestration boundary.
#
# A merge queue is optional; add one only if merge traffic ever makes "keep the branch up
# to date" painful. See standards/testing.md → CI/CD Testing Tiers.
#
# Requirements: gh CLI, authenticated (`gh auth status`), admin on the repo.
#
# Usage:
#   ./setup-branch-protection.sh [owner/repo] [branch]
#     owner/repo  defaults to the current repo (gh repo view)
#     branch      defaults to main
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
BRANCH="${2:-main}"

echo "Configuring branch protection on ${REPO}@${BRANCH} …"
echo "  required checks: fast-tests, integration-tests (strict = branch must be up to date)"

gh api -X PUT "repos/${REPO}/branches/${BRANCH}/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["fast-tests", "integration-tests"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "Done. Verify in GitHub → Settings → Branches, or:"
echo "  gh api repos/${REPO}/branches/${BRANCH}/protection -q '.required_status_checks'"
