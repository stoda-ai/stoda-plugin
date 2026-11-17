# Stoda

Stoda's read-only repository orientation guide for Claude Code. It tells you where you are (the folder, its git
repository, its GitHub remote and your GitHub CLI sign-in) and gives you one next step. It never makes changes
itself.

## Install

In Claude Code:

```
/plugin marketplace add stoda-ai/stoda-plugin
/plugin install stoda@stoda
```

## Use it

The plugin has one skill, `guide`. Claude may choose it when your request matches, or you can run it yourself as
`/stoda:guide`. For example:

- "Where am I?"
- "What should I do next?"
- "What state is this repo in?"
- `/stoda:guide`

You get a short card of what the guide found and exactly one next step, such as pushing your branch or signing in to
the GitHub CLI. The guide doesn't carry out the step; ask for it next if you want it done.

For the turn it answers, the guide removes Claude Code's shell, file, web and subagent tools (Bash, Write, Edit,
NotebookEdit, Read, Glob, Grep, WebFetch, WebSearch, Agent, Task). Tools from MCP servers you have connected are not
removed; the guide is only instructed not to use them. This is guidance, not a security sandbox. On your next
message, Claude has its usual tools and permissions again.

## What it runs and what it sends

When the guide loads, it runs one bundled script, `scripts/inspect.sh`. It runs nothing else of its own.

- **Local reads.** The script uses `git`, `gh`, `sed`, `head`, `awk` and `dirname`, and nothing else outside the
  shell. With local `git` commands only (`rev-parse`, `symbolic-ref`, `remote get-url`, `config`, `ls-files` and
  `rev-list`), it reads the repository's refs, config, index and commit history (to count unpushed commits), and
  checks whether a `.gitmodules` file exists. It also reads this plugin's own `plugin.json` for its version. It
  doesn't run `git status`, doesn't read the contents of your working-tree files and doesn't fetch. Git's optional
  locks, fsmonitor hook and untracked cache are turned off for these reads.
- **The GitHub CLI.** If `gh` is installed, it runs `gh auth status --hostname github.com` and uses only its exit
  code. That command contacts GitHub (github.com) using your existing GitHub CLI sign-in. GitHub handles that request
  under its own terms and privacy policy.
- **Your Claude conversation.** The facts it finds enter your Claude conversation: the current folder's name (not
  its full path), whether it's a git repository, the branch, the GitHub owner/repo of the `origin` remote, the
  recorded upstream, whether there are submodules, the count of unpushed commits, whether `git` and `gh` are
  installed, your GitHub CLI sign-in state, and this plugin's version. Claude handles the conversation under its
  own terms and privacy policy.
- **Stoda.** There is no Stoda-operated backend and no telemetry. The plugin sends nothing to Stoda, and its script
  writes no files.

## Where it works

The guide is built and tested for Claude Code, in a folder on your own machine. It hasn't been tested in other
Claude apps.

## Troubleshooting

- **"I couldn't tell"**: the guide couldn't read that fact. Run `git status` in your terminal and tell Claude what it
  says.
- **`git` or `gh` not installed**: the card says so. Install the missing tool, then ask again.
- **Signed out of GitHub**: run `gh auth login` in your terminal.
- **Install fails on a machine without a GitHub SSH key**: set `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1`, then install
  again.

## Support and security

- **Questions and bugs**: open an issue at https://github.com/stoda-ai/stoda-plugin/issues.
- **Security vulnerabilities**: report them privately at
  https://github.com/stoda-ai/stoda-plugin/security/advisories/new. Don't put exploit details or credentials in a
  public issue.

## License

MIT, copyright Stoda (see `LICENSE`). The license grants no rights to the Stoda name or logo.
