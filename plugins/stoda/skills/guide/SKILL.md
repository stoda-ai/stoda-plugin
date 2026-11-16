---
name: guide
description: "Where am I and what should I do next? Reads this folder, its git repository and the GitHub CLI sign-in, without changing anything, and gives one next step. Use when someone asks where they are, what's next, what state their app or repo is in, or isn't sure what to do."
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh)
disallowed-tools: Bash, Write, Edit, NotebookEdit, Read, Glob, Grep, WebFetch, WebSearch, Agent, Task
---
This skill only reads. It gives guidance; it doesn't act: don't call any tool, including MCP tools (Claude Code's
built-in shell, file, web and subagent tools are removed for this turn). The inspection already ran:

!`${CLAUDE_PLUGIN_ROOT}/scripts/inspect.sh`

Each line above is `<fact> <value>`. Use only those facts.

1. Show a short card, plain words, one line each, only for facts that were printed:
   - Folder: `folder`, and whether it is a git repository (`repo`)
   - Branch: `branch`; GitHub repository: `github` (`none`: no `origin` remote; `other`: `origin` isn't on GitHub)
   - Not yet sent: `unpushed` commits not on `upstream` (as last fetched here). With `upstream none`, say only that
     this branch has no upstream recorded here; don't say whether it was ever pushed.
   - GitHub sign-in: `gh-auth`
   - Stoda plugin: version `plugin`
   Say "I couldn't tell" for an `unknown` fact; never treat it as zero. Say that you didn't look at uncommitted
   files: `git status` in a terminal shows them.

2. Give exactly one next step, the first that applies:

   | When | Next step |
   |---|---|
   | `repo no` | Open your project's folder in Claude Code, then ask me again. |
   | `tool git no`, or `repo`, `branch`, `upstream` or `unpushed` is `unknown` | I couldn't read this repository; run `git status` in your terminal and tell me what it says. |
   | `branch detached` | You're not on a branch; switch to one before saving work. |
   | `github none` | This repository isn't connected to GitHub yet. |
   | `unpushed` above 0, or `upstream none` | Push this branch. |
   | `tool gh no` or `gh-auth signed-out` | Sign in to GitHub: run `gh auth login` in your terminal. |
   | otherwise | No commits are waiting to be pushed to `upstream` (as last fetched here; with `submodules` `yes` or `unknown`, add "I didn't check the submodules"). Tell me what you'd like to change next. |

3. Don't carry out the step: say what it would do, and that the person can ask for it next. Never print tokens, keys
   or passwords.
