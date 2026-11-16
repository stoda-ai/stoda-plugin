#!/usr/bin/env bash
# The release job's first step: refuses while RELEASE-HOLD exists (its first line is the reason), LICENSE is missing
# at the commit being released, or LICENSE still has its unverified copyright-holder line. Prints `open` (exit 0) or `held <reason>` (exit 1).
# Usage: release-gate.sh <commit>
set -euo pipefail
(( $# == 1 )) || { echo "error usage"; exit 2; }
sha=$(git rev-parse -q --verify "$1^{commit}") || { echo "error unknown-commit"; exit 2; }
if git cat-file -e "$sha:RELEASE-HOLD" 2>/dev/null; then
  hold=$(git show "$sha:RELEASE-HOLD") || hold=unreadable
  hold=${hold%%$'\n'*}
  echo "held ${hold%%:*}"; exit 1
fi
git cat-file -e "$sha:LICENSE" 2>/dev/null || { echo "held no-license"; exit 1; }
# Read whole, then matched in the shell: a pipe into `grep -q` could end early and, under pipefail, read as no match.
license=$(git show "$sha:LICENSE") || { echo "held license-unreadable"; exit 1; }
shopt -s nocasematch
if [[ "$license" == *"to be verified"* ]]; then echo "held copyright-holder-unverified"; exit 1; fi
echo open
