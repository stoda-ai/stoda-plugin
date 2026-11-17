#!/usr/bin/env bash
# The last step of a release, run by scripts/promote.sh on a repository admin's machine, after it checked CI's push run
# on main for this commit. Users install from the `release` branch, never from main, so nothing reaches them until this
# runs.
#   1. release-gate.sh: refuses while RELEASE-HOLD exists or LICENSE is missing (nothing is pushed)
#   2. tag-release.sh: tags stoda--v<version> once, or finds that version already released with nothing users
#      receive changed since; refuses otherwise
#   3. one atomic push of the `release` branch to the commit (fast-forward only: a push that isn't is rejected) and,
#      for a new version, its tag. Either both move or neither does.
# Prints each step's line and `published <sha>`; exit 1 on a refusal, 2 on bad usage.
# Usage: publish.sh <commit> [<remote>]   (remote defaults to origin)
set -euo pipefail
(( $# == 1 || $# == 2 )) || { echo "error usage"; exit 2; }
sha=$(git rev-parse -q --verify "$1^{commit}") || { echo "error unknown-commit"; exit 2; }
remote=${2:-origin}
here=$(dirname "${BASH_SOURCE[0]}")
"$here/release-gate.sh" "$sha"
out=$("$here/tag-release.sh" "$sha") || { echo "$out"; exit 1; }
echo "$out"
# The version tag goes in every push, not only a new one: a retry after a failed push finds the tag already made
# here (`exists`) and must still send it. Pushing a tag the remote already has at the same commit changes nothing.
tag=${out#* }
tag=${tag%% *}
refs=("$sha:refs/heads/release" "refs/tags/$tag")
git push --atomic --porcelain "$remote" "${refs[@]}" >/dev/null || { echo "error push-rejected"; exit 1; }
echo "published $sha"
