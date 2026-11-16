#!/usr/bin/env bats

# A temp repo with the plugin manifest and copies of the release scripts.
setup() {
  export HOME=$BATS_TEST_TMPDIR/home GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  git config --global user.name Tester
  git config --global user.email tester@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  repo=$BATS_TEST_TMPDIR/repo
  mkdir -p "$repo/plugins/stoda/.claude-plugin" "$repo/scripts" "$repo/docs" "$repo/.claude-plugin"
  cp "$BATS_TEST_DIRNAME"/../scripts/{check-version,tag-release,release-gate}.sh "$repo/scripts/"
  cp "$BATS_TEST_DIRNAME/../release-surface" "$repo/"
  printf '# readme\n' > "$repo/README.md"
  cd "$repo"
  git init -q
  version 0.1.0
  commit
}

version() { printf '{"name": "stoda", "version": "%s"}\n' "$1" > plugins/stoda/.claude-plugin/plugin.json; }
commit() { git add -A; git commit -q -m "${1:-change}"; }

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

@test "a change outside the plugin needs no bump; a lower or non-semver version fails" {
  base=$(git rev-parse HEAD)
  printf 'x\n' > docs/readme.md; commit
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

@test "a release is tagged once, and re-running on the same commit is a no-op" {
  sha=$(git rev-parse HEAD)
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "tagged stoda--v0.1.0 $sha" ]
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "exists stoda--v0.1.0 $sha" ]
}

@test "the same version from another commit is refused and the tag never moves" {
  first=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf 'x\n' > plugins/stoda/notes.md; commit
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "error tag-elsewhere stoda--v0.1.0 $first" ]
  [ "$(git rev-parse stoda--v0.1.0^{commit})" = "$first" ]
}

@test "a later commit that changes nothing in the plugin is already released, not an error" {
  first=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf 'x\n' > docs/readme.md; commit
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "released stoda--v0.1.0 $first" ]
}

@test "the version comes from the commit, not the working tree" {
  sha=$(git rev-parse HEAD)
  version 9.9.9
  run scripts/tag-release.sh "$sha"
  [ "$output" = "tagged stoda--v0.1.0 $sha" ]
}

@test "a README or manifest change needs a new version, and after a release it is not a no-op" {
  base=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf 'more\n' >> README.md; commit
  run scripts/check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-not-raised 0.1.0" ]
  run scripts/tag-release.sh HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == "error tag-elsewhere stoda--v0.1.0 "* ]]
  printf '{"name": "stoda", "owner": {"name": "Stoda"}, "plugins": []}\n' > .claude-plugin/marketplace.json
  version 0.1.1; commit
  run scripts/check-version.sh "$base"
  [ "$output" = ok ]
}

@test "the release gate holds while RELEASE-HOLD exists or LICENSE is missing, and opens with LICENSE alone" {
  printf 'license-undecided: reason\n' > RELEASE-HOLD; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held license-undecided" ]
  git rm -q RELEASE-HOLD; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held no-license" ]
  printf 'terms\n' > LICENSE; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = open ]
}

@test "the workflow runs the release gate before tagging, and the repository is held" {
  wf=$BATS_TEST_DIRNAME/../.github/workflows/ci.yml
  gate=$(grep -n 'scripts/release-gate.sh' "$wf" | cut -d: -f1)
  tag=$(grep -n 'scripts/tag-release.sh' "$wf" | cut -d: -f1)
  [ -n "$gate" ] && [ -n "$tag" ] && (( gate < tag ))
  [ -f "$BATS_TEST_DIRNAME/../RELEASE-HOLD" ]
  [ ! -e "$BATS_TEST_DIRNAME/../LICENSE" ]
}
