#!/usr/bin/env bats

# A temp repo with the plugin, its catalog, README, LICENSE, release list and copies of the release scripts, plus a
# bare "remote" to publish to.
setup() {
  export HOME=$BATS_TEST_TMPDIR/home GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  git config --global user.name Tester
  git config --global user.email tester@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  repo=$BATS_TEST_TMPDIR/repo
  mkdir -p "$repo/plugins/stoda/.claude-plugin" "$repo/scripts" "$repo/docs" "$repo/.claude-plugin"
  for s in check-version tag-release release-gate publish; do cp "$BATS_TEST_DIRNAME/../scripts/$s.sh" "$repo/scripts/"; done
  cp "$BATS_TEST_DIRNAME/../scripts/release-lib.sh" "$BATS_TEST_DIRNAME/../release-surface" "$repo/"
  mv "$repo/release-lib.sh" "$repo/scripts/"
  printf '# readme\n' > "$repo/README.md"
  printf '{"name": "stoda", "owner": {"name": "Stoda"}, "plugins": []}\n' > "$repo/.claude-plugin/marketplace.json"
  printf 'terms\n' > "$repo/LICENSE"
  cd "$repo"
  git init -q
  version 0.1.0
  commit
  remote=$BATS_TEST_TMPDIR/remote.git
  git init -q --bare "$remote"
}

version() { printf '{"name": "stoda", "version": "%s"}\n' "$1" > plugins/stoda/.claude-plugin/plugin.json; }
commit() { git add -A; git commit -q -m "${1:-change}"; }
remote_ref() { git --git-dir="$remote" rev-parse -q --verify "$1" || true; }

@test "a plugin change with a raised version passes; without one it fails" {
  base=$(git rev-parse HEAD)
  printf 'x\n' > plugins/stoda/notes.md; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-not-raised 0.1.0" ]
  version 0.1.1; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "a change outside what users receive needs no bump; a lower or non-semver version fails" {
  base=$(git rev-parse HEAD)
  printf 'x\n' > docs/notes.md; commit
  run scripts/check-version.sh "$base"
  [ "$output" = unchanged ]
  version 0.0.9; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-went-down 0.1.0 0.0.9" ]
  version 0.2.0-rc1; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error not-semver" ]
  run scripts/check-version.sh no-such-ref
  [ "$status" -eq 2 ]
}

# Codex review 12 finding 4: the catalog alone, with no other change, is part of the release.
@test "a catalog-only change without a bump is refused by both the version check and the tagger" {
  base=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf '{"name": "stoda", "owner": {"name": "Someone"}, "plugins": []}\n' > .claude-plugin/marketplace.json; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-not-raised 0.1.0" ]
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "error tag-elsewhere stoda--v0.1.0 $base" ]
  version 0.1.1; commit
  run scripts/check-version.sh "$base"
  [ "$output" = ok ]
}

@test "README and LICENSE changes need a new version" {
  base=$(git rev-parse HEAD)
  for f in README.md LICENSE; do
    git reset -q --hard "$base"
    printf 'more\n' >> "$f"; commit
    run scripts/check-version.sh "$base"
    [ "$status" -eq 1 ] || { echo "$f: $output"; false; }
  done
}

# Codex review 12 finding 1: the list is read from both commits and always includes itself, so a list that drops a
# path (and its own entry) can't hide a change to that path.
@test "dropping README and the list's own entry while changing README is still refused by both scripts" {
  base=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  grep -v -x -e README.md -e release-surface release-surface > rs && mv rs release-surface
  printf 'more\n' >> README.md; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-not-raised 0.1.0" ]
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == "error tag-elsewhere stoda--v0.1.0 "* ]]
}

@test "a release is tagged once; the same version from a changed commit is refused and the tag never moves" {
  first=$(git rev-parse HEAD)
  run scripts/tag-release.sh HEAD
  [ "$output" = "tagged stoda--v0.1.0 $first" ]
  run scripts/tag-release.sh HEAD
  [ "$output" = "exists stoda--v0.1.0 $first" ]
  printf 'x\n' > plugins/stoda/notes.md; commit
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 1 ]
  [ "$(git rev-parse 'stoda--v0.1.0^{commit}')" = "$first" ]
}

@test "a later commit that changes nothing users receive is already released; the version comes from the commit" {
  first=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf 'x\n' > docs/notes.md; commit
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "released stoda--v0.1.0 $first" ]
  version 9.9.9
  run scripts/tag-release.sh HEAD
  [ "$output" = "released stoda--v0.1.0 $first" ]
}

@test "the release gate holds while RELEASE-HOLD exists or LICENSE is missing" {
  printf 'content-unapproved: reason\n' > RELEASE-HOLD; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held content-unapproved" ]
  git rm -q RELEASE-HOLD LICENSE; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held no-license" ]
  printf 'terms\n' > LICENSE; commit
  run scripts/release-gate.sh HEAD
  [ "$output" = open ]
}

# Codex review 12 finding 3 and the main-gating point: a held commit reaches neither the release branch nor a tag on
# the remote; an open one moves both in one push.
@test "publish pushes nothing while held, and the release branch and tag move together once open" {
  printf 'content-unapproved: reason\n' > RELEASE-HOLD; commit
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 1 ]
  [ "$output" = "held content-unapproved" ]
  [ -z "$(remote_ref refs/heads/release)" ]
  [ -z "$(remote_ref refs/tags/stoda--v0.1.0)" ]
  [ -z "$(git tag)" ]
  git rm -q RELEASE-HOLD; commit
  sha=$(git rev-parse HEAD)
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "tagged stoda--v0.1.0 $sha" ]
  [ "${lines[2]}" = "published $sha" ]
  [ "$(remote_ref refs/heads/release)" = "$sha" ]
  [ "$(remote_ref 'refs/tags/stoda--v0.1.0^{commit}')" = "$sha" ]
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "exists stoda--v0.1.0 $sha" ]
}

@test "a docs-only commit fast-forwards release; a non-fast-forward or an unbumped change is refused" {
  scripts/publish.sh HEAD "$remote"
  printf 'x\n' > docs/notes.md; commit
  docs=$(git rev-parse HEAD)
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 0 ]
  [ "$(remote_ref refs/heads/release)" = "$docs" ]
  run scripts/publish.sh HEAD~1 "$remote"
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "error push-rejected" ]
  [ "$(remote_ref refs/heads/release)" = "$docs" ]
  printf 'x\n' > plugins/stoda/notes.md; commit
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 1 ]
  [ "$(remote_ref refs/heads/release)" = "$docs" ]
}

# The release job: after `test`, on pushes to main, one at a time, and its only command is publish.sh, which fails
# the job on any refusal (no continue-on-error, no `|| true`). Nothing else in the workflow tags or pushes.
@test "the workflow publishes only through publish.sh after test, on main, without swallowing failures" {
  wf=$BATS_TEST_DIRNAME/../.github/workflows/ci.yml
  job=$(awk '/^  release:/{f=1} f' "$wf")
  grep -qx '    needs: test' <<< "$job"
  grep -qx "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'" <<< "$job"
  grep -qx '      cancel-in-progress: false' <<< "$job"
  [ "$(grep -c 'scripts/publish.sh' <<< "$job")" -eq 1 ]
  grep -qx '          scripts/publish.sh "\$SHA"' <<< "$job"
  run grep -n -e 'continue-on-error' -e '|| true' -e 'set +e' <<< "$job"
  [ "$status" -eq 1 ]
  run grep -n -e 'tag-release.sh' -e 'git push' -e 'git tag' "$wf"
  [ "$status" -eq 1 ]
}

@test "the release gate holds while LICENSE still has its unverified copyright-holder line" {
  printf 'MIT License\n\nCopyright (c) 2026 [copyright holder: to be verified before release]\n' > LICENSE; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held copyright-holder-unverified" ]
}
