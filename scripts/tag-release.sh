#!/usr/bin/env bash
# Tags the plugin version at a commit, once: `stoda--v<version>` (the plugin version-tag form Claude Code resolves
# dependency ranges against). Never moves or deletes a tag.
#   tagged <tag> <sha>    created locally (publish.sh pushes it)
#   exists <tag> <sha>    already on this commit: nothing to do
#   released <tag> <tag-sha>   the version is already released from another commit and nothing users receive (the
#                              paths in release-surface) changed since: nothing to do
#   error tag-elsewhere <tag> <other-sha>   something users receive changed since that release without a new version
# Usage: tag-release.sh <commit>. Reads the version from that commit's plugin.json, not the working tree.
set -euo pipefail
(( $# == 1 )) || { echo "error usage"; exit 2; }
sha=$(git rev-parse -q --verify "$1^{commit}") || { echo "error unknown-commit"; exit 2; }
version=$(git show "$sha:plugins/stoda/.claude-plugin/plugin.json" | jq -er '.version') || { echo "error no-version"; exit 1; }
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error not-semver"; exit 1; }
tag="stoda--v$version"
# shellcheck source=release-lib.sh source-path=SCRIPTDIR
source "$(dirname "${BASH_SOURCE[0]}")/release-lib.sh"
if existing=$(git rev-parse -q --verify "refs/tags/$tag^{commit}"); then
  if [[ "$existing" == "$sha" ]]; then echo "exists $tag $sha"; exit 0; fi
  # Anything users receive under either commit's list (or always): a list that drops a path can't hide a change.
  list=$(surface_paths "$existing" "$sha") || { echo "error no-release-surface"; exit 1; }
  paths=()
  while IFS= read -r p; do paths+=("$p"); done <<< "$list"
  if git diff --quiet "$existing" "$sha" -- "${paths[@]}"; then echo "released $tag $existing"; exit 0; fi
  echo "error tag-elsewhere $tag $existing"; exit 1
fi
git tag "$tag" "$sha"
echo "tagged $tag $sha"
