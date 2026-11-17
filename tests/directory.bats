#!/usr/bin/env bats

# What Anthropic's plugin directory needs from the plugin folder (pre-submission checklist and Software Directory
# Policy 3B, 3C, 3E), and what the plugin discloses about what it runs and sends.
setup() {
  plugin=$BATS_TEST_DIRNAME/../plugins/stoda
  readme=$plugin/README.md
  manifest=$plugin/.claude-plugin/plugin.json
}

@test "the plugin folder has its own README of at least 40 words outside code blocks" {
  [ -f "$readme" ]
  words=$(awk '/^```/ {fence = !fence; next} !fence' "$readme" | wc -w)
  [ "$words" -ge 40 ]
}

@test "the manifest carries the approved listing fields and nothing that awaits a decision" {
  [ "$(jq -r .description "$manifest")" = "Stoda's read-only repository orientation guide for Claude Code." ]
  [ "$(jq -r .displayName "$manifest")" = "Stoda" ]
  [ "$(jq -r .supportUrl "$manifest")" = "https://github.com/stoda-ai/stoda-plugin/issues" ]
  [ "$(jq -r .documentationUrl "$manifest")" = "https://github.com/stoda-ai/stoda-plugin/blob/main/plugins/stoda/README.md" ]
  # A privacy policy link and an icon each wait on their own approval, so neither is set yet.
  [ "$(jq 'has("privacyPolicyUrl") or has("icon")' "$manifest")" = false ]
}

@test "the README discloses the GitHub CLI call, the conversation and that there is no Stoda backend" {
  grep -qF 'gh auth status --hostname github.com' "$readme"
  grep -qF 'contacts GitHub (github.com) using your existing GitHub CLI sign-in' "$readme"
  grep -qF 'enter your Claude conversation' "$readme"
  grep -qF 'no Stoda-operated backend and no telemetry' "$readme"
  # The inspector's gh call is what the README discloses; if it changes, so must the README.
  grep -qF 'gh auth status --hostname github.com' "$plugin/scripts/inspect.sh"
}

@test "the README makes no blanket data claims and claims no endorsement" {
  run grep -inE 'collects nothing|no retention|nothing to anyone|endorsed by|sponsored by|partner of anthropic' "$readme"
  [ "$status" -eq 1 ]
}

@test "the README gives at least three example prompts, support and a private security route" {
  n=$(sed -n '/^## Use it/,/^## /p' "$readme" | grep -c '^- ')
  [ "$n" -ge 3 ]
  grep -qF 'https://github.com/stoda-ai/stoda-plugin/issues' "$readme"
  grep -qF 'https://github.com/stoda-ai/stoda-plugin/security/advisories/new' "$readme"
  grep -qF "Don't put exploit details or credentials in a" "$readme"
}

# Runs the inspector with only traced copies of the commands the README names on PATH, in a repository whose branch
# has an upstream (so every fact is reported): a fact, a command or a git or gh call the README doesn't disclose fails.
@test "the inspector reports, runs and calls only what the README discloses" {
  export HOME=$BATS_TEST_TMPDIR/home GIT_CONFIG_NOSYSTEM=1
  mkdir -p "$HOME"
  git config --global user.name Tester
  git config --global user.email tester@example.com
  git config --global init.defaultBranch main
  git config --global commit.gpgsign false
  app=$BATS_TEST_TMPDIR/app
  git init -q "$app" && cd "$app"
  git commit -q --allow-empty -m one
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git push -q -u origin main

  trace=$BATS_TEST_TMPDIR/trace
  shims=$BATS_TEST_TMPDIR/traced
  mkdir -p "$shims"
  for c in git sed head awk dirname; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >> "%s"\nexec %s "$@"\n' "$c" "$trace" "$(command -v "$c")" > "$shims/$c"
  done
  # gh is a stub: the test never contacts GitHub.
  printf '#!/bin/sh\nprintf "%%s\\n" "gh $*" >> "%s"\nexit 0\n' "$trace" > "$shims/gh"
  chmod +x "$shims"/*
  # A command that isn't on PATH is traced too, even if its error output is discarded.
  printf 'command_not_found_handle() { printf "missing %%s\\n" "$1" >> "%s"; return 127; }\n' "$trace" > "$BATS_TEST_TMPDIR/env"
  BASH_ENV=$BATS_TEST_TMPDIR/env PATH=$shims run "$BASH" "$plugin/scripts/inspect.sh"
  [ "$status" -eq 0 ]

  facts=$(printf '%s\n' "$output" | awk '{print $1}' | LC_ALL=C sort -u | tr '\n' ' ')
  [ "$facts" = "branch folder gh-auth github plugin repo submodules tool unpushed upstream " ] || { echo "$facts"; false; }
  for phrase in "folder's name" "git repository" "the branch" "owner/repo" "upstream" "submodules" \
    "unpushed commits" "installed" "sign-in state" "plugin's version"; do
    grep -qF "$phrase" "$readme" || { echo "missing: $phrase"; false; }
  done

  # The other paths: an upstream that no longer resolves (the config fallback), and outside any repository.
  git config branch.main.merge refs/heads/gone
  BASH_ENV=$BATS_TEST_TMPDIR/env PATH=$shims run "$BASH" "$plugin/scripts/inspect.sh"
  grep -qx 'upstream unknown' <<< "$output"
  mkdir -p "$BATS_TEST_TMPDIR/plain" && cd "$BATS_TEST_TMPDIR/plain"
  BASH_ENV=$BATS_TEST_TMPDIR/env PATH=$shims run "$BASH" "$plugin/scripts/inspect.sh"
  grep -qx 'repo no' <<< "$output"

  # Only the commands the README names were on PATH, so anything else was traced as missing; all of them ran here.
  commands=$(awk '{print $1}' "$trace" | LC_ALL=C sort -u | tr '\n' ' ')
  [ "$commands" = "awk dirname gh git head sed " ] || { echo "$commands"; false; }
  grep -qF 'The script uses `git`, `gh`, `sed`, `head`, `awk` and `dirname`, and nothing else outside the' "$readme"
  # Every git call, after its -c and -C options, is one of these exact read-only forms; the fallback form ran too.
  awk '$1 == "git" {i = 2; while ($i == "-c" || $i == "-C") i += 2; s = $i; for (i++; i <= NF; i++) s = s " " $i; print s}' \
    "$trace" | LC_ALL=C sort -u > "$BATS_TEST_TMPDIR/calls"
  grep -qx 'config --get branch.main.merge' "$BATS_TEST_TMPDIR/calls"
  while read -r call; do
    case $call in
      'rev-parse --is-inside-work-tree' | 'rev-parse --git-dir' | 'rev-parse --show-toplevel' | \
        'rev-parse -q --abbrev-ref --symbolic-full-name @{upstream}' | 'symbolic-ref -q --short HEAD' | \
        'remote get-url origin' | 'config --get branch.main.merge' | 'ls-files -s' | 'rev-list --count @{upstream}..HEAD') ;;
      *) echo "undisclosed: git $call"; false ;;
    esac
  done < "$BATS_TEST_TMPDIR/calls"
  for s in rev-parse symbolic-ref 'remote get-url' config ls-files rev-list; do
    grep -qF "\`$s\`" "$readme" || { echo "README doesn't name git $s"; false; }
  done
  [ "$(grep '^gh ' "$trace" | LC_ALL=C sort -u)" = "gh auth status --hostname github.com" ]
}
