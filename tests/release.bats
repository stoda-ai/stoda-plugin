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
  for s in check-version tag-release release-gate release-ready publish promote; do cp "$BATS_TEST_DIRNAME/../scripts/$s.sh" "$repo/scripts/"; done
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

# CI never publishes: no job can write to the repository, and nothing in the workflow tags, pushes or releases.
@test "the workflow never publishes: read-only token, no release job, no push or tag" {
  wf=$BATS_TEST_DIRNAME/../.github/workflows/ci.yml
  grep -qx '  contents: read' "$wf"
  code=$(grep -v -E '^[[:space:]]*#' "$wf")
  run grep -n -e 'contents: write' -e 'permissions: write' -e 'write-all' -e '^  release:' -e 'publish.sh' \
    -e 'promote.sh' -e 'tag-release.sh' -e 'git push' -e 'git tag' <<< "$code"
  [ "$status" -eq 1 ]
}

@test "the release gate holds while LICENSE still has its unverified copyright-holder line" {
  printf 'MIT License\n\nCopyright (c) 2026 [copyright holder: to be verified before release]\n' > LICENSE; commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held copyright-holder-unverified" ]
}

# Codex review 13: a large LICENSE can't make the gate fail open; a retry still sends the tag; any directory works.
@test "a large LICENSE with the unverified holder line near the top is still held" {
  { printf 'MIT License\n\nCopyright (c) 2026 [copyright holder: to be verified before release]\n'
    for i in $(seq 1 20000); do printf 'filler line %s of the license text\n' "$i"; done; } > LICENSE
  commit
  run scripts/release-gate.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "held copyright-holder-unverified" ]
}

@test "a retry after a failed push still sends the version tag" {
  sha=$(git rev-parse HEAD)
  run scripts/publish.sh HEAD "$BATS_TEST_TMPDIR/missing.git"
  [ "$status" -eq 1 ]
  [ "$(git rev-parse -q --verify 'stoda--v0.1.0^{commit}')" = "$sha" ]
  run scripts/publish.sh HEAD "$remote"
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "exists stoda--v0.1.0 $sha" ]
  [ "$(remote_ref refs/heads/release)" = "$sha" ]
  [ "$(remote_ref 'refs/tags/stoda--v0.1.0^{commit}')" = "$sha" ]
}

@test "the version check and the tagger give the same answer from a subdirectory" {
  base=$(git rev-parse HEAD)
  scripts/tag-release.sh HEAD
  printf 'more\n' >> README.md; commit
  cd scripts
  run ./check-version.sh "$base"
  [ "$status" -eq 1 ]
  [ "$output" = "error version-not-raised 0.1.0" ]
  run ./tag-release.sh HEAD
  [ "$status" -eq 1 ]
}

# Bootstrap: the catalog on main must never install main. Its plugin entry fetches the CI-moved release branch, which
# doesn't exist before the first release, so an install fails closed rather than taking untested code.
@test "the catalog's plugin entry installs only from the release branch of this repository" {
  cat=$BATS_TEST_DIRNAME/../.claude-plugin/marketplace.json
  [ "$(jq -c '[.plugins[] | .source]' "$cat")" = '[{"source":"git-subdir","url":"stoda-ai/stoda-plugin","path":"plugins/stoda","ref":"release"}]' ]
  run jq -e '[.plugins[] | .source | strings] | length == 0' "$cat"
  [ "$status" -eq 0 ]
}

# The installed plugin is only plugins/stoda, so it must carry the license itself: a regular file identical to the
# canonical root LICENSE (the one place it is edited), not a symlink out of the plugin.
@test "the plugin carries the same LICENSE as the repository, as a regular file" {
  root=$BATS_TEST_DIRNAME/..
  [ -f "$root/plugins/stoda/LICENSE" ] && [ ! -L "$root/plugins/stoda/LICENSE" ]
  cmp "$root/LICENSE" "$root/plugins/stoda/LICENSE"
  grep -qx 'Copyright (c) 2026 Stoda' "$root/LICENSE"
}

# The check the release branch's ruleset requires: it runs on every event (never skipped, which a required check would
# treat as passing) and its only command is the gate, so it fails while held.
@test "the release-ready job always runs the release gate and never skips" {
  wf=$BATS_TEST_DIRNAME/../.github/workflows/ci.yml
  job=$(awk '/^  release-ready:/{f=1; print; next} f && /^  [a-z]/{exit} f' "$wf")
  [ -n "$job" ]
  # No condition at the job or any step level, and nothing that turns a failure into success.
  run grep -n -E -e '^[[:space:]]+(-[[:space:]]+)?if:' -e 'continue-on-error' -e '\|\| true' <<< "$job"
  [ "$status" -eq 1 ]
  grep -qx '      - run: scripts/release-ready.sh HEAD' <<< "$job"
}

# A pull request's checks run on a merge tree but attach to its head commit: release-ready must never succeed there,
# nor for any event or branch but a push to main, and it must fail (not skip). On a main push it is the release gate.
@test "release-ready succeeds only for a push to main that passes the release gate" {
  for ev in "pull_request refs/pull/7/merge" "pull_request_target refs/heads/main" "push refs/heads/feature" "workflow_dispatch refs/heads/main" " "; do
    set -- $ev
    GITHUB_EVENT_NAME=${1:-} GITHUB_REF=${2:-} run scripts/release-ready.sh HEAD
    [ "$status" -eq 1 ] || { echo "$ev: $output"; false; }
    [[ "$output" == "not-ready not-a-push-to-main"* ]]
  done
  GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main run scripts/release-ready.sh HEAD
  [ "$status" -eq 0 ]
  [ "$output" = ready ]
  printf 'release-gates-open: reason\n' > RELEASE-HOLD; commit
  GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main run scripts/release-ready.sh HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "not-ready held release-gates-open" ]
}

# promote.sh: an admin's manual release. `gh` is a stub that applies the script's own --jq filter to raw API JSON
# (GH_RUNS_JSON, GH_JOBS_JSON), records each endpoint, and fails when GH_FAIL is set; so the filtering is what's tested.
promote_setup() {
  git --git-dir="$remote" config receive.denyNonFastForwards true
  git push -q "$remote" HEAD:refs/heads/main
  stub=$BATS_TEST_TMPDIR/stub
  mkdir -p "$stub"
  cat > "$stub/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1" = api ] && [ "$3" = --jq ] || exit 9
printf '%s\n' "$2" >> "$BATS_TEST_TMPDIR/gh-calls"
[ -z "${GH_FAIL-}" ] || exit 1
case $2 in
  *"/runs?"*) jq -r "$4" <<< "${GH_RUNS_JSON:-{\"workflow_runs\": []\}}" ;;
  *"/jobs?"*) jq -r "$4" <<< "${GH_JOBS_JSON:-{\"jobs\": []\}}" ;;
  *) exit 9 ;;
esac
STUB
  chmod +x "$stub/gh"
  export PATH=$stub:$PATH
  # The release location, for the test only: the copy expects origin to be this bare remote instead of GitHub.
  # (where() drops a trailing .git, as GitHub URLs may or may not carry it.)
  sed -i.bak -e "s#^want=\"github.com/\$REPO\"#want=\"${remote%.git}\"#" -e 's#^    \*) echo "" ;;#    *) echo "$u" ;;#' \
    scripts/promote.sh && rm scripts/promote.sh.bak
  grep -q "^want=\"${remote%.git}\"" scripts/promote.sh
  grep -q '^    \*) echo "\$u" ;;' scripts/promote.sh
  git remote add origin "$remote"
}

run_json() { # run_json <id> <sha> [event] [branch] [path] [repo] [status]
  printf '{"id": %s, "head_sha": "%s", "event": "%s", "head_branch": "%s", "path": "%s", "repository": {"full_name": "%s"}, "status": "%s"}' \
    "$1" "$2" "${3:-push}" "${4:-main}" "${5:-.github/workflows/ci.yml}" "${6:-stoda-ai/stoda-plugin}" "${7:-completed}"
}
jobs_json() { # jobs_json <run> <sha> <test-conclusion> <ready-conclusion>
  printf '{"jobs": [{"run_id": %s, "head_sha": "%s", "name": "test", "conclusion": "%s"}, {"run_id": %s, "head_sha": "%s", "name": "release-ready", "conclusion": "%s"}]}' \
    "$1" "$2" "$3" "$1" "$2" "$4"
}

@test "promote refuses an origin, or any push URL, that isn't the release repository, before fetching" {
  sha=$(git rev-parse HEAD)
  git remote add origin https://github.com/someone/fork.git
  run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "$output" = "refused origin-not-stoda-ai/stoda-plugin" ]
  # A local path that merely looks like the repository is not it.
  git remote set-url origin github.com/stoda-ai/stoda-plugin.git
  run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "$output" = "refused origin-not-stoda-ai/stoda-plugin" ]
  git remote set-url origin git@github.com:stoda-ai/stoda-plugin.git
  git remote set-url --add --push origin https://github.com/stoda-ai/stoda-plugin.git
  git remote set-url --add --push origin https://github.com/someone/fork.git
  run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "$output" = "refused push-url-not-stoda-ai/stoda-plugin" ]
  run scripts/promote.sh "${sha:0:12}"
  [ "$status" -eq 2 ]
}

@test "promote refuses a commit not on main, an API error, and runs that aren't this repo's ci push on main" {
  promote_setup
  sha=$(git rev-parse HEAD)
  git switch -q -c side; printf 'x\n' > docs/side.md; commit
  run scripts/promote.sh "$(git rev-parse HEAD)"
  [ "$status" -eq 1 ]
  [ "$output" = "refused not-on-main" ]
  GH_FAIL=1 run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "refused ci-unreadable" ]
  other=$(git rev-parse HEAD)
  GH_RUNS_JSON="{\"workflow_runs\": [$(run_json 1 "$sha" pull_request), $(run_json 2 "$sha" push side), $(run_json 3 "$sha" push main .github/workflows/other.yml), $(run_json 4 "$sha" push main .github/workflows/ci.yml someone/fork), $(run_json 5 "$other"), $(run_json 6 "$sha" push main .github/workflows/ci.yml stoda-ai/stoda-plugin in_progress)]}" \
    run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "refused no-main-push-run" ]
  grep -q "^repos/stoda-ai/stoda-plugin/actions/runs?head_sha=$sha&event=push&branch=main&status=completed" "$BATS_TEST_TMPDIR/gh-calls"
}

@test "promote uses the newest green ci push run, and refuses one whose jobs aren't both green" {
  promote_setup
  sha=$(git rev-parse HEAD)
  runs="{\"workflow_runs\": [$(run_json 41 "$sha"), $(run_json 43 "$sha"), $(run_json 42 "$sha")]}"
  GH_RUNS_JSON=$runs GH_JOBS_JSON=$(jobs_json 43 "$sha" success failure) run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "refused ci-not-green run 43: release-ready=failure test=success" ]
  GH_RUNS_JSON=$runs GH_JOBS_JSON=$(jobs_json 99 "$sha" success success) run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "refused ci-not-green run 43: no jobs" ]
  GH_RUNS_JSON=$runs GH_JOBS_JSON=$(jobs_json 43 0123456789abcdef0123456789abcdef01234567 success success) \
    run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[1]}" = "refused ci-not-green run 43: no jobs" ]
  [ -z "$(remote_ref refs/heads/release)" ]
  [ -z "$(git tag)" ]
  GH_RUNS_JSON=$runs GH_JOBS_JSON=$(jobs_json 43 "$sha" success success) run scripts/promote.sh "$sha"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[1]}" = "ci-green run 43" ]
  [ "${lines[${#lines[@]}-1]}" = "published $sha" ]
  [ "$(remote_ref refs/heads/release)" = "$sha" ]
  [ "$(remote_ref 'refs/tags/stoda--v0.1.0^{commit}')" = "$sha" ]
  grep -q "^repos/stoda-ai/stoda-plugin/actions/runs/43/jobs" "$BATS_TEST_TMPDIR/gh-calls"
}

@test "promote still applies the release gate to a green main commit" {
  promote_setup
  printf 'release-gates-open: reason\n' > RELEASE-HOLD; commit
  git push -q origin HEAD:refs/heads/main
  sha=$(git rev-parse HEAD)
  GH_RUNS_JSON="{\"workflow_runs\": [$(run_json 7 "$sha")]}" GH_JOBS_JSON=$(jobs_json 7 "$sha" success success) \
    run scripts/promote.sh "$sha"
  [ "$status" -eq 1 ]
  [ "${lines[${#lines[@]}-1]}" = "held release-gates-open" ]
  [ -z "$(remote_ref refs/heads/release)" ]
}
