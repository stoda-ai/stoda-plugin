#!/usr/bin/env bash
# The `release-ready` CI check: succeeds only for a push to main whose commit passes the release gate. On a pull request
# (whose checks run on a merge tree but attach to the PR's head commit), or any other event or branch, it fails rather
# than skips, so no commit that isn't main's ever carries a successful release-ready, which the release branch's
# ruleset requires. Prints `ready` or `not-ready <reason>` (exit 1). Reads GITHUB_EVENT_NAME and GITHUB_REF.
# Usage: release-ready.sh <commit>
set -euo pipefail
(( $# == 1 )) || { echo "error usage"; exit 2; }
if [[ "${GITHUB_EVENT_NAME:-}" != push || "${GITHUB_REF:-}" != refs/heads/main ]]; then
  echo "not-ready not-a-push-to-main: only a commit pushed to main can be released"
  exit 1
fi
if ! out=$("$(dirname "${BASH_SOURCE[0]}")/release-gate.sh" "$1"); then echo "not-ready $out"; exit 1; fi
echo ready
