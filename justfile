# Free checks; CI runs this.
test: validate directory lint bats

validate:
    claude plugin validate --strict .
    claude plugin validate --strict plugins/stoda

# The directory's own checks, on a copy of the plugin folder outside any git repository: inside one, the validator
# takes a missing plugin README from the repository root, which the directory documents as belonging in the plugin
# folder. Fails on anything the directory refuses; warnings (the icon, until there is one) pass.
directory:
    #!/usr/bin/env bash
    set -euo pipefail
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
    tmp=$(mktemp -d /tmp/stoda-directory.XXXXXX)
    trap 'rm -rf "$tmp"' EXIT
    cp -R plugins/stoda "$tmp/stoda"
    # The validator takes the nearest parent folder with .git as the repository; there must be none, on the
    # resolved path (macOS's /tmp is /private/tmp), up to and including /.
    d=$(cd "$tmp" && pwd -P)
    while :; do
      if [ -e "${d%/}/.git" ]; then echo "directory: ${d%/}/.git is above the copy; can't check the plugin README" >&2; exit 1; fi
      [ "$d" = / ] && break
      d=$(dirname "$d")
    done
    claude plugin validate --profile directory "$tmp/stoda"

lint:
    shellcheck -x scripts/*.sh plugins/stoda/scripts/*.sh

bats:
    bats tests
