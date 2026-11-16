#!/usr/bin/env bash
# Fails a change that touches plugins/stoda/ without raising its plugin.json version: an installed copy updates only
# when that string changes. Usage: check-version.sh <base-ref>. Prints `ok`, `unchanged` (nothing under the plugin
# changed) or `error <reason>`; exit 1 on a missing bump, 2 on bad usage.
set -euo pipefail
(( $# == 1 )) || { echo "error usage"; exit 2; }
base=$1
manifest=plugins/stoda/.claude-plugin/plugin.json
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "error unknown-base"; exit 2; }
if git diff --quiet "$base" HEAD -- plugins/stoda/; then echo unchanged; exit 0; fi
new=$(jq -er '.version' "$manifest") || { echo "error no-version"; exit 1; }
old=$(git show "$base:$manifest" 2>/dev/null | jq -er '.version' 2>/dev/null) || { echo ok; exit 0; }
[[ "$new" != "$old" ]] || { echo "error version-not-raised $old"; exit 1; }
# The new version must sort after the old one (semver core only, no pre-release ordering).
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$old" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error not-semver"; exit 1; }
greater() {
  local -a a b
  local i
  IFS=. read -ra a <<< "$1"
  IFS=. read -ra b <<< "$2"
  for i in 0 1 2; do
    if (( 10#${a[i]} > 10#${b[i]} )); then return 0; fi
    if (( 10#${a[i]} < 10#${b[i]} )); then return 1; fi
  done
  return 1
}
greater "$new" "$old" || { echo "error version-went-down $old $new"; exit 1; }
echo ok
