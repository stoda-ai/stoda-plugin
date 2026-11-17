#!/usr/bin/env bash
# Releases one commit of main, by hand. Run by a repository admin (only admins may create or move `release` and create
# version tags). Refuses unless, for this exact commit:
#   1. it is on origin/main (after a fetch);
#   2. this repository's `ci` workflow (.github/workflows/ci.yml) has a completed run for a push to main at this commit,
#      and its `test` and `release-ready` jobs both succeeded (read with `gh api`; nothing is written there);
# then runs publish.sh: the release gate, the version tag once, and one atomic, fast-forward-only push of `release`
# with that tag. Prints each step's line; exit 1 on a refusal, 2 on bad usage.
# Usage: promote.sh <40-hex commit of main> [<owner/repo>] [<remote>]   (defaults: stoda-ai/stoda-plugin, origin)
set -euo pipefail
(( $# >= 1 && $# <= 3 )) || { echo "error usage"; exit 2; }
sha=$1
repo=${2:-stoda-ai/stoda-plugin}
remote=${3:-origin}
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "error usage: give the full 40-character commit"; exit 2; }
git fetch -q "$remote" main || { echo "refused fetch-failed"; exit 1; }
git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "refused unknown-commit"; exit 1; }
git merge-base --is-ancestor "$sha" FETCH_HEAD || { echo "refused not-on-main"; exit 1; }
echo "on-main $sha"

runs=$(gh api "repos/$repo/actions/runs?head_sha=$sha&event=push&branch=main&status=completed&per_page=100" \
  --jq '[.workflow_runs[] | select(.path == ".github/workflows/ci.yml") | .id] | sort | reverse | .[]') \
  || { echo "refused ci-unreadable"; exit 1; }
run=${runs%%$'\n'*}
[[ -n "$run" ]] || { echo "refused no-main-push-run"; exit 1; }
jobs=$(gh api "repos/$repo/actions/runs/$run/jobs?per_page=100" \
  --jq '[.jobs[] | select(.name == "test" or .name == "release-ready") | "\(.name)=\(.conclusion)"] | sort | join(" ")') \
  || { echo "refused ci-unreadable"; exit 1; }
[[ "$jobs" == "release-ready=success test=success" ]] || { echo "refused ci-not-green run $run: ${jobs:-no jobs}"; exit 1; }
echo "ci-green run $run"

exec "$(dirname "${BASH_SOURCE[0]}")/publish.sh" "$sha" "$remote"
