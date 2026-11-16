#!/usr/bin/env bats

# The guide's inspector reads and never writes (design decision D3: inspection performs only reads).
setup() {
  inspect="$BATS_TEST_DIRNAME/../plugins/stoda/scripts/inspect.sh"
  export HOME=$BATS_TEST_TMPDIR/home GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  git config --global user.name Tester
  git config --global user.email tester@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  # A gh stub whose sign-in result each test chooses; git stays the real one.
  shims=$BATS_TEST_TMPDIR/shims
  mkdir -p "$shims"
  printf '#!/usr/bin/env bash\n[ "$1 $2" = "auth status" ] && exit "${GH_STUB_AUTH:-0}"\nexit 9\n' > "$shims/gh"
  chmod +x "$shims/gh"
  export PATH=$shims:$PATH
  app=$BATS_TEST_TMPDIR/my-app
  mkdir -p "$app"
  cd "$app"
}

repo() {
  git init -q
  printf 'hello\n' > a.txt
  git add -A
  git commit -q -m one
}

# Every path, mode, size and content hash under the folder, .git included.
snapshot() { (cd "$app" && find . -print0 | LC_ALL=C sort -z | xargs -0 ls -ld | awk '{print $1, $5, $NF}'; find . -type f -exec shasum {} + | LC_ALL=C sort); }

@test "outside a repository: the folder, the plugin version and the tools, and nothing about git" {
  run "$inspect"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "plugin $(jq -r .version "$BATS_TEST_DIRNAME/../plugins/stoda/.claude-plugin/plugin.json")" ]
  [ "${lines[1]}" = "folder my-app" ]
  [ "${lines[2]}" = "repo no" ]
  [ "${lines[3]}" = "tool git yes" ]
  [ "${lines[4]}" = "tool gh yes" ]
  [ "${lines[5]}" = "gh-auth signed-in" ]
}

@test "in a clean repository without a remote" {
  repo
  run "$inspect"
  [ "$status" -eq 0 ]
  [ "${lines[2]}" = "repo yes" ]
  [ "${lines[3]}" = "branch main" ]
  [ "${lines[4]}" = "github none" ]
  [ "${lines[5]}" = "upstream none" ]
  [ "${lines[6]}" = "submodules no" ]
  [ "${lines[7]}" = "unpushed no-upstream" ]
}

@test "GitHub remotes in https, ssh and scp form give owner/repo; anything else is other" {
  repo
  for url in https://github.com/acme/widget.git git@github.com:acme/widget.git ssh://git@github.com/acme/widget \
    https://gitlab.com/acme/widget.git; do
    git remote remove origin 2>/dev/null || true
    git remote add origin "$url"
    run "$inspect"
    case $url in
      *gitlab*) [ "${lines[4]}" = "github other" ] ;;
      *) [ "${lines[4]}" = "github acme/widget" ] || { echo "$url: ${lines[4]}"; false; } ;;
    esac
  done
}

@test "unpushed commits are counted, uncommitted files aren't inspected, and a detached HEAD is named" {
  repo
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git push -q -u origin main
  printf 'more\n' >> a.txt
  printf 'new\n' > b.txt
  git commit -q --allow-empty -m two
  run "$inspect"
  [ "${lines[7]}" = "unpushed 1" ]
  run grep -c '^changes ' <<< "$output"
  [ "$output" = 0 ]
  git checkout -q --detach HEAD
  run "$inspect"
  [ "${lines[3]}" = "branch detached" ]
}

@test "GitHub CLI sign-in comes from gh's exit code; without gh it says so" {
  GH_STUB_AUTH=1 run "$inspect"
  [ "${lines[${#lines[@]}-1]}" = "gh-auth signed-out" ]
  rm "$shims/gh"
  nogh=$BATS_TEST_TMPDIR/nogh
  mkdir -p "$nogh"
  for c in git sed head wc tr dirname; do ln -s "$(command -v "$c")" "$nogh/$c"; done
  PATH=$nogh run "$BASH" "$inspect"
  [ "${lines[${#lines[@]}-2]}" = "tool gh no" ]
  [ "${lines[${#lines[@]}-1]}" = "gh-auth no-gh" ]
}

# A plain `git status` refreshes a stale index; the inspector must not, nor write anything else.
@test "inspecting changes nothing in the folder, not even git's index after file times change" {
  repo
  # Same content, new times: the case where a plain `git status` rewrites the index to record them.
  sleep 1
  touch a.txt
  printf 'new\n' > b.txt
  before=$(snapshot)
  run "$inspect"
  [ "$status" -eq 0 ]
  [ "$(snapshot)" = "$before" ]
  [ ! -e .git/index.lock ]
}

# The model gets no tools while the guide is active: the inspector runs by injection when the skill loads. Whether
# the client honours this is checked in a live session (see RELEASE-HOLD); this checks the declarations match it.
@test "the guide runs only the inspector by injection and removes every acting tool" {
  skill=$BATS_TEST_DIRNAME/../plugins/stoda/skills/guide/SKILL.md
  grep -qx '!`${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh`' "$skill"
  grep -qx 'allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh)' "$skill"
  grep -qx 'disallowed-tools: Bash, Write, Edit, NotebookEdit, Read, Glob, Grep, WebFetch, WebSearch, Agent, Task' "$skill"
  run grep -c 'scripts/' "$skill"
  [ "$output" -eq 2 ]
}

# Codex review 13: a configured fsmonitor hook must not run; bash 3.2's here-strings needed a writable temp folder.
@test "a configured fsmonitor hook never runs, and an unwritable temp folder changes no fact" {
  repo
  git remote add origin https://github.com/acme/widget.git
  printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/hook"
  chmod +x "$BATS_TEST_TMPDIR/hook"
  git config core.fsmonitor "$BATS_TEST_TMPDIR/hook"
  ro=$BATS_TEST_TMPDIR/ro
  mkdir -p "$ro" && chmod 500 "$ro"
  for sh in "$BASH" /bin/bash; do
    [ -x "$sh" ] || continue
    TMPDIR=$ro run "$sh" "$inspect"
    [ "$status" -eq 0 ]
    [ "${lines[4]}" = "github acme/widget" ] || { echo "$sh: $output"; false; }
  done
  [ ! -e "$BATS_TEST_TMPDIR/hook-ran" ]
}

@test "inside .git is not a working tree, and nothing about the repo is reported there" {
  repo
  cd .git
  run "$inspect"
  [ "${lines[2]}" = "repo no" ]
  run grep -c -e '^branch ' -e '^unpushed ' <<< "$output"
  [ "$output" = 0 ]
}

# Codex review 14 P1: a clean filter the repository configures must never run, because nothing reads file contents.
@test "a repository-configured clean filter never runs" {
  repo
  printf '#!/bin/sh\ntouch "%s/filter-ran"\ncat\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/filter"
  chmod +x "$BATS_TEST_TMPDIR/filter"
  git config filter.spy.clean "$BATS_TEST_TMPDIR/filter"
  printf '*.txt filter=spy\n' > .gitattributes
  git add .gitattributes && git commit -q -m attrs
  # Same size, new time: git can only tell by reading the content, which runs the clean filter.
  sleep 1
  printf 'jello\n' > a.txt
  git -c core.fsmonitor=false status --porcelain >/dev/null
  [ -e "$BATS_TEST_TMPDIR/filter-ran" ] || skip "this git didn't run the filter for status; nothing to compare"
  rm "$BATS_TEST_TMPDIR/filter-ran"
  sleep 1
  printf 'hello\n' > a.txt
  run "$inspect"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/filter-ran" ]
}

@test "the upstream is reported, and a repo without one has no unpushed count" {
  repo
  run "$inspect"
  grep -qx 'upstream none' <<< "$output"
  grep -qx 'unpushed no-upstream' <<< "$output"
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git push -q -u origin main
  run "$inspect"
  grep -qx 'upstream origin/main' <<< "$output"
  grep -qx 'unpushed 0' <<< "$output"
}

@test "the guide claims nothing about uncommitted files or GitHub, and treats unknown as unknown" {
  skill=$BATS_TEST_DIRNAME/../plugins/stoda/skills/guide/SKILL.md
  grep -q '| otherwise | No commits are waiting to be pushed to `upstream` (as last fetched here' "$skill"
  grep -q "you didn't look at uncommitted" "$skill"
  grep -q '`unpushed` above 0, or `upstream none` | Push this branch.' "$skill"
  grep -q 'never treat it as zero' "$skill"
  run grep -c 'on GitHub\.' "$skill"
  [ "$output" = 0 ]
}

@test "submodules are flagged as not inspected, and a broken upstream is unknown, not none" {
  repo
  git init -q "$BATS_TEST_TMPDIR/sub" && (cd "$BATS_TEST_TMPDIR/sub" && git commit -q --allow-empty -m s)
  git -c protocol.file.allow=always submodule -q add "$BATS_TEST_TMPDIR/sub" sub
  git commit -q -m sub
  run "$inspect"
  grep -qx 'submodules yes' <<< "$output"
  git config branch.main.remote origin
  git config branch.main.merge refs/heads/main
  run "$inspect"
  grep -qx 'upstream unknown' <<< "$output"
}
