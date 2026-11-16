#!/usr/bin/env bash
# The guide's read-only inspection of where the builder is: it never writes a file, a git index or lock, or any
# state (GIT_OPTIONAL_LOCKS=0 keeps `git status` from refreshing the index). One `<fact> <value>` line each:
#   plugin <version>                       the installed stoda plugin's version
#   folder <name>                          the current folder's name (not its full path)
#   repo yes|no                            whether the folder is inside a git repository
#   branch <name>|detached                 (repo only)
#   github <owner/repo>|none|other         origin's GitHub repository, none without origin, other off GitHub (repo only)
#   changes <n>                            uncommitted changes: modified, staged and untracked paths (repo only)
#   unpushed <n>|no-upstream               commits on this branch not on its upstream (repo only)
#   tool git|gh yes|no                     whether the command is installed
#   gh-auth signed-in|signed-out|no-gh     GitHub CLI sign-in, from `gh auth status`'s exit code only
# Always exits 0; a fact it can't read is reported as it is, never guessed.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0 LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)
echo "plugin ${version:-unknown}"
echo "folder ${PWD##*/}"

has() { command -v "$1" >/dev/null 2>&1; }
if has git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "repo yes"
  if branch=$(git symbolic-ref -q --short HEAD); then echo "branch $branch"; else echo "branch detached"; fi
  if url=$(git remote get-url origin 2>/dev/null); then
    slug=$(sed -nE 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p' <<< "$url")
    slug=${slug%.git}
    echo "github ${slug:-other}"
  else
    echo "github none"
  fi
  echo "changes $(git status --porcelain --untracked-files=normal 2>/dev/null | wc -l | tr -d ' ')"
  if git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
    echo "unpushed $(git rev-list --count '@{upstream}..HEAD')"
  else
    echo "unpushed no-upstream"
  fi
else
  echo "repo no"
fi
for t in git gh; do if has "$t"; then echo "tool $t yes"; else echo "tool $t no"; fi; done
if ! has gh; then echo "gh-auth no-gh"
elif gh auth status --hostname github.com >/dev/null 2>&1; then echo "gh-auth signed-in"
else echo "gh-auth signed-out"; fi
exit 0
