# shellcheck shell=bash
# Sourced by the release scripts. The release surface: every path users receive.
# surface_paths <commit>...: prints literal pathspecs from the repository root, one per line: the paths every one of the given commits'
# release-surface lists, plus the ones that are always part of a release whatever a list says (the manifests, the
# plugin and the list itself), so a list that drops a path can't hide a change to it. A commit without a list (the
# first one) adds nothing. Exit 1 when no list is readable at all.
surface_paths() {
  local c found=no
  {
    printf '%s\n' .claude-plugin plugins/stoda release-surface
    for c in "$@"; do
      if git cat-file -e "$c:release-surface" 2>/dev/null; then
        found=yes
        git show "$c:release-surface" | grep -v -e '^#' -e '^$' || true
      fi
    done
    [[ $found == yes ]]
  } | sort -u | sed 's/^/:(top,literal)/'
  return "${PIPESTATUS[0]}"
}
