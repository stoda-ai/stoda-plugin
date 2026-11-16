#!/usr/bin/env bash
# The guide's read-only inspection of where the builder is. It writes nothing itself: no file, git index or lock
# (GIT_OPTIONAL_LOCKS=0), no fsmonitor hook or daemon (core.fsmonitor=false), no submodule recursion, and no temporary
# file (no here-strings, which bash 3.2 backs with a temp file). Limit: a clean/smudge filter the repository itself
# configures can still run when git compares a file's content. One `<fact> <value>` line each:
#   plugin <version>                       the installed stoda plugin's version
#   folder <name>                          the current folder's name (not its full path)
#   repo yes|no|unknown                    whether the folder is inside a git working tree
#   branch <name>|detached                 (repo yes only)
#   github <owner/repo>|none|other         origin's GitHub repository, none without origin, other off GitHub
#   upstream <remote>/<branch>|none        the branch's upstream, if it has one
#   changes <n>|unknown                    uncommitted changes: modified, staged and untracked paths
#   unpushed <n>|no-upstream|unknown       commits on this branch not on its upstream
#   tool git|gh yes|no                     whether the command is installed
#   gh-auth signed-in|signed-out|no-gh     GitHub CLI sign-in, from `gh auth status`'s exit code only
# A fact it can't read is `unknown`, never a clean state. Always exits 0.
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0 LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" | head -n 1)
echo "plugin ${version:-unknown}"
echo "folder ${PWD##*/}"

has() { command -v "$1" >/dev/null 2>&1; }
g() { git -c core.fsmonitor=false -c core.untrackedCache=false "$@"; }
inside=no
if has git; then
  if out=$(g rev-parse --is-inside-work-tree 2>/dev/null); then
    [[ "$out" == true ]] && inside=yes
  elif g rev-parse --git-dir >/dev/null 2>&1; then
    inside=unknown
  fi
fi
echo "repo $inside"
if [[ $inside == yes ]]; then
  if branch=$(g symbolic-ref -q --short HEAD); then echo "branch $branch"; else echo "branch detached"; fi
  if url=$(g remote get-url origin 2>/dev/null); then
    slug=$(printf '%s\n' "$url" | sed -nE 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+)$#\2#p')
    slug=${slug%.git}
    echo "github ${slug:-other}"
  else
    echo "github none"
  fi
  if up=$(g rev-parse -q --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
    echo "upstream $up"
  else
    up=
    echo "upstream none"
  fi
  if status=$(g status --porcelain --untracked-files=normal --ignore-submodules=all 2>/dev/null); then
    if [[ -z "$status" ]]; then echo "changes 0"; else echo "changes $(printf '%s\n' "$status" | wc -l | tr -d ' ')"; fi
  else
    echo "changes unknown"
  fi
  if [[ -z "$up" ]]; then
    echo "unpushed no-upstream"
  elif n=$(g rev-list --count '@{upstream}..HEAD' 2>/dev/null); then
    echo "unpushed $n"
  else
    echo "unpushed unknown"
  fi
fi
for t in git gh; do if has "$t"; then echo "tool $t yes"; else echo "tool $t no"; fi; done
if ! has gh; then echo "gh-auth no-gh"
elif gh auth status --hostname github.com >/dev/null 2>&1; then echo "gh-auth signed-in"
else echo "gh-auth signed-out"; fi
exit 0
