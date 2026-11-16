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
   - Branch: `branch`; GitHub repository: `github` (`none`: no `origin` remote; `other`: `origin` isn't on GitHub)
   - Saved here, not yet sent: `changes` uncommitted files; `unpushed` commits not on `upstream`
   - GitHub sign-in: `gh-auth`
   - Stoda plugin: version `plugin`
   Say "I couldn't tell" for an `unknown` fact; never treat it as zero.

3. Give exactly one next step, the first that applies:

   | When | Next step |
   |---|---|
   | `repo no` | Open your project's folder in Claude Code, then ask me again. |
   | `tool git no`, or `repo`, `changes` or `unpushed` is `unknown` | I couldn't read this repository; run `git status` in your terminal and tell me what it says. |
   | `branch detached` | You're not on a branch; switch to one before saving work. |
   | `changes` above 0 | Review your changes and save them in a commit. |
   | `github none` | This repository isn't connected to GitHub yet. |
   | `unpushed` above 0, or `upstream none` | Push this branch. |
   | `tool gh no` or `gh-auth signed-out` | Sign in to GitHub: run `gh auth login` in your terminal. |
   | otherwise | Everything is committed and pushed to `upstream`. Tell me what you'd like to change next. |

4. Never carry out the step yourself from this skill, even when asked to in the same message: say what it will do,
   and ask before doing anything. Don't read `.env` files or print tokens, keys or passwords.
