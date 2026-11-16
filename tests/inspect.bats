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
  [ "${lines[6]}" = "changes 0" ]
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

@test "uncommitted and unpushed work are counted, and a detached HEAD is named" {
  repo
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git push -q -u origin main
  printf 'more\n' >> a.txt
  printf 'new\n' > b.txt
  git commit -q --allow-empty -m two
  run "$inspect"
  [ "${lines[6]}" = "changes 2" ]
  [ "${lines[7]}" = "unpushed 1" ]
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

# Declarations only: allowed-tools pre-approves, it doesn't restrict (other Bash commands still follow the session's
# permissions). Enforcement in a live session is a separate, open check.
@test "the guide skill pre-approves only the inspector and removes the file-editing tools" {
  skill=$BATS_TEST_DIRNAME/../plugins/stoda/skills/guide/SKILL.md
  grep -qx 'allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh)' "$skill"
  grep -qx 'disallowed-tools: Write, Edit, NotebookEdit' "$skill"
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

@test "facts it can't read are unknown, never clean; inside .git is not a working tree" {
  repo
  printf 'garbage' > .git/index
  run "$inspect"
  [ "${lines[2]}" = "repo yes" ]
  grep -qx 'changes unknown' <<< "$output"
  cd .git
  run "$inspect"
  [ "${lines[2]}" = "repo no" ]
  run grep -c -e '^branch ' -e '^changes ' <<< "$output"
  [ "$output" = 0 ]
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

@test "the guide claims a push only with an upstream, and treats unknown as unknown" {
  skill=$BATS_TEST_DIRNAME/../plugins/stoda/skills/guide/SKILL.md
  grep -q '| otherwise | Everything is committed and pushed to `upstream`.' "$skill"
  grep -q '`unpushed` above 0, or `upstream none` | Push this branch.' "$skill"
  grep -q 'never treat it as zero' "$skill"
  run grep -c 'on GitHub\.' "$skill"
  [ "$output" = 0 ]
}
