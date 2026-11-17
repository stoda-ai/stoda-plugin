#!/usr/bin/env bash
# Releases one commit of main, by hand. Run by a repository admin (only admins may create or move `release` and create
# version tags). Everything is bound to one repository, REPO below: the `origin` remote's fetch and push URLs must both
# be it, and every CI record read must belong to it. Refuses unless, for this exact commit:
#   1. it is on main, as just fetched from origin;
#   2. REPO's `ci` workflow (.github/workflows/ci.yml) has a completed run for a push to main at this commit (the
#      newest such run is used), and in that run the `test` and `release-ready` jobs both succeeded. Read with
#      `gh api`; any API error refuses. Nothing is written there.
# then runs publish.sh against origin: the release gate, the version tag once, and one atomic, fast-forward-only push
# of `release` with that tag. Prints each step's line; exit 1 on a refusal, 2 on bad usage.
# Usage: promote.sh <40-hex commit of main>
set -euo pipefail
REPO=stoda-ai/stoda-plugin
(( $# == 1 )) || { echo "error usage"; exit 2; }
sha=$1
[[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "error usage: give the full 40-character commit"; exit 2; }

# github.com/<owner>/<repo> from an https, scp-style or ssh GitHub URL; any other form (a local path, another host) gives
# nothing, so it never matches.
where() {
  local u=$1
  u=${u%.git}
  case $u in
    https://github.com/*) echo "github.com/${u#https://github.com/}" ;;
    git@github.com:*) echo "github.com/${u#git@github.com:}" ;;
    ssh://git@github.com/*) echo "github.com/${u#ssh://git@github.com/}" ;;
    *) echo "" ;;
  esac
}
want="github.com/$REPO"
fetch_url=$(git remote get-url origin 2>/dev/null) || { echo "refused no-origin"; exit 1; }
push_urls=$(git remote get-url --push --all origin 2>/dev/null) || { echo "refused no-origin"; exit 1; }
[[ "$(where "$fetch_url")" == "$want" ]] || { echo "refused origin-not-$REPO"; exit 1; }
while IFS= read -r u; do
  [[ "$(where "$u")" == "$want" ]] || { echo "refused push-url-not-$REPO"; exit 1; }
done <<< "$push_urls"

git fetch -q origin main || { echo "refused fetch-failed"; exit 1; }
git cat-file -e "$sha^{commit}" 2>/dev/null || { echo "refused unknown-commit"; exit 1; }
git merge-base --is-ancestor "$sha" FETCH_HEAD || { echo "refused not-on-main"; exit 1; }
echo "on-main $sha"

run=$(gh api "repos/$REPO/actions/runs?head_sha=$sha&event=push&branch=main&status=completed&per_page=100" --jq "
  [.workflow_runs[] | select(.head_sha == \"$sha\" and .event == \"push\" and .head_branch == \"main\"
    and .status == \"completed\" and .path == \".github/workflows/ci.yml\" and .repository.full_name == \"$REPO\")
  | .id] | sort | last // empty") || { echo "refused ci-unreadable"; exit 1; }
[[ "$run" =~ ^[0-9]+$ ]] || { echo "refused no-main-push-run"; exit 1; }
jobs=$(gh api "repos/$REPO/actions/runs/$run/jobs?per_page=100" --jq "
  [.jobs[] | select(.run_id == $run and .head_sha == \"$sha\" and (.name == \"test\" or .name == \"release-ready\"))
  | \"\(.name)=\(.conclusion)\"] | sort | join(\" \")") || { echo "refused ci-unreadable"; exit 1; }
[[ "$jobs" == "release-ready=success test=success" ]] || { echo "refused ci-not-green run $run: ${jobs:-no jobs}"; exit 1; }
echo "ci-green run $run"

exec "$(dirname "${BASH_SOURCE[0]}")/publish.sh" "$sha" origin
