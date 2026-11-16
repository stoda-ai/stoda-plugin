---
name: guide
description: "Where am I and what should I do next? Reads this folder, its git repository and the GitHub CLI sign-in, without changing anything, and gives one next step. Use when someone asks where they are, what's next, what state their app or repo is in, or isn't sure what to do."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh)
disallowed-tools: Write, Edit, NotebookEdit
---
Look before suggesting anything, and change nothing: this skill only reads.

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh` once. Each line is `<fact> <value>`; use only what it printed.

2. Show a short card, plain words, one line each, only for facts it printed:
   - Folder: `folder`, and whether it is a git repository (`repo`)
   - Branch: `branch`; GitHub: `github` (`none`: not connected to GitHub; `other`: hosted somewhere else)
   - Unsaved work: `changes` files changed; `unpushed` commits not on GitHub (`no-upstream`: the branch isn't on
     GitHub yet)
   - GitHub sign-in: `gh-auth`
   - Stoda plugin: version `plugin`

3. Give exactly one next step, the first that applies:

   | When | Next step |
   |---|---|
   | `repo no` | Open your project's folder in Claude Code, then ask me again. |
   | `tool git no` | Install git, then ask me again. |
   | `changes` above 0 | Review your changes and save them in a commit. |
   | `unpushed` above 0, or `no-upstream` with a `github` repo | Push this branch to GitHub. |
   | `tool gh no` or `gh-auth signed-out` | Sign in to GitHub: run `gh auth login` in your terminal. |
   | otherwise | Everything is saved and on GitHub. Tell me what you'd like to change next. |

4. Never carry out the step yourself from this skill, even when asked to in the same message: say what it will do,
   and ask before doing anything. Don't read `.env` files or print tokens, keys or passwords.
