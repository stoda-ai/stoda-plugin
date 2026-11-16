#!/usr/bin/env bash
# The release job's first step: refuses while RELEASE-HOLD exists (its first line is the reason) or LICENSE is
# missing at the commit being released. Prints `open` (exit 0) or `held <reason>` (exit 1).
# Usage: release-gate.sh <commit>
set -euo pipefail
(( $# == 1 )) || { echo "error usage"; exit 2; }
sha=$(git rev-parse -q --verify "$1^{commit}") || { echo "error unknown-commit"; exit 2; }
if git cat-file -e "$sha:RELEASE-HOLD" 2>/dev/null; then
  echo "held $(git show "$sha:RELEASE-HOLD" | head -n 1 | cut -d: -f1)"; exit 1
fi
git cat-file -e "$sha:LICENSE" 2>/dev/null || { echo "held no-license"; exit 1; }
echo open
