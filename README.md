# Stoda plugin for Claude Code

The [Stoda](https://stoda.ai) plugin for Claude Code, and the marketplace it is installed from.

## Status

Pre-release. The plugin has one skill, `guide`: ask "where am I?" or "what's next?" (or run `/stoda:guide`) and it
reads the current folder, its git repository and your GitHub CLI sign-in, without changing anything, and gives one
next step. It never makes changes itself. For the turn it answers it removes Claude Code's shell, file, web and
subagent tools (Bash, Write, Edit, NotebookEdit, Read, Glob, Grep, WebFetch, WebSearch, Agent, Task); tools from MCP
servers you have connected are not removed, and the guide is only instructed not to use them. This is guidance, not a
security sandbox; on your next message Claude has its usual tools and permissions again.

Unreleased: nothing can be installed until the first release (`RELEASE-HOLD` lists what is left before it).

## Install

In Claude Code:

```
/plugin marketplace add stoda-ai/stoda-plugin#release
/plugin install stoda@stoda
```

or from a shell: `claude plugin marketplace add stoda-ai/stoda-plugin#release`, then `claude plugin install stoda@stoda`.
Every command the plugin adds is `/stoda:<name>`. On a machine without a GitHub SSH key, set
`CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` first; no GitHub account is needed for this public repository.

## Updates

Users install from the `release` branch. Changes merge to `main` through reviewed pull requests; CI tests every pull
request and every push to `main`, and reports two checks: `test`, and `release-ready`, which passes only for a commit
pushed to `main` that passes the release gate (on a pull request it always fails). CI never publishes. A repository
admin releases a commit by hand:

```
scripts/promote.sh <40-character commit of main>
```

It refuses unless the commit is on `main` and CI's run for that push to `main`, at that exact commit, has `test` and
`release-ready` green; then it tags the version once and moves `release` to the commit with that tag in one
fast-forward-only push. Only repository admins may create or move `release` and create version tags; `release` can't
be force-pushed or deleted, and tags can't be moved or deleted. Releases therefore rely on repository admins being
trusted; the checks guard against mistakes. The catalog's plugin entry itself points at `plugins/stoda` on `release`, so
the plugin comes from `release` even when the catalog is read from `main`; until the first release there is no
`release` branch, and installing fails instead of taking untested code.

Each released version is also tagged `stoda--v<version>` on the commit it was released from, as a record. The
catalog installs from `release`, so pinning the marketplace to a tag doesn't pin the plugin.

## What this repository holds

Only generic Stoda plugin source: skills, their scripts, and the plugin and marketplace manifests. No organization's
settings, names, keys or other client information belong here. A skill that needs an organization's values reads
them at run time from outside the plugin.

## License

MIT, copyright Stoda (`LICENSE`, repeated as `plugins/stoda/LICENSE` so it ships with the installed plugin), for the
Stoda-owned code, skills and configuration in this repository. It doesn't
relicense anything a third party owns: such files keep their own license and notices. It grants no rights to the Stoda
name or logo. No logo is included yet.

## Development

Needs `just`, `bats`, `shellcheck`, `jq` and Claude Code.

- `just test`: validate the marketplace and plugin manifests, lint the scripts, run the tests. CI runs it on every
  pull request and on `main`.
- `scripts/check-version.sh <base-ref>`: the version check CI runs on pull requests.
- `scripts/promote.sh <commit>`: an admin's release of a `main` commit whose CI push run is green; it ends with
  `scripts/publish.sh`, which refuses while `RELEASE-HOLD` exists or `LICENSE` is missing, tags a new version once
  (`scripts/tag-release.sh`, which never moves a tag), and moves `release` with that tag in one atomic,
  fast-forward-only push.

Load the plugin from a checkout without installing it: `claude --plugin-dir plugins/stoda`.
