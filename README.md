# stoda-plugin

The Stoda plugin for Claude Code, and the marketplace it is installed from.

## Status

Pre-release. The plugin has one skill, `guide`: ask "where am I?" or "what's next?" (or run `/stoda:guide`) and it
reads the current folder, its git repository and your GitHub CLI sign-in, without changing anything, and gives one
next step. It never makes changes itself: for the turn it answers, its shell, file, web and subagent tools are
removed (a request to run a command in that turn is denied). This is guidance, not a security sandbox; on your next
message Claude has its usual tools and permissions again. Nothing here is published yet; this README describes how installing and
updating will work once it is.

Not done yet, so no release is made (`RELEASE-HOLD` lists each): the verified copyright holder in `LICENSE`, an
approved Stoda logo and plugin icon, and review of this README and the first skill.

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

Users install from the `release` branch. Changes merge to `main`; CI tests every commit on `main`, and only a commit
that passed moves `release` (fast-forward only, together with its version tag, in one push), so nothing untested reaches
users. The catalog's plugin entry itself points at `release`, so the plugin comes from `release` even when the catalog
is read from `main`; until the first release there is no `release` branch, and installing fails instead of taking
untested code. A change reaches installed copies only when it raises `version` in `plugins/stoda/.claude-plugin/plugin.json`;
CI refuses a pull request that changes anything users receive (`release-surface`) without raising it.
Run `/plugin marketplace update stoda` (or turn on auto-update for the `stoda` marketplace in `/plugin`) to pick up
a new version.

Each released version is tagged `stoda--v<version>` on the commit it was released from. To stay on one version, add
the marketplace at that tag instead: `/plugin marketplace add stoda-ai/stoda-plugin#stoda--v<version>`.

## What this repository holds

Only generic Stoda plugin source: skills, their scripts, and the plugin and marketplace manifests. No organization's
settings, names, keys or other client information belong here. A skill that needs an organization's values reads
them at run time from outside the plugin.

## License

MIT, for the Stoda-owned code, skills and configuration in this repository (`LICENSE`). It doesn't relicense anything
a third party owns: such files keep their own license and notices. The Stoda name and logo are not covered by it.

## Development

Needs `just`, `bats`, `shellcheck`, `jq` and Claude Code.

- `just test`: validate the marketplace and plugin manifests, lint the scripts, run the tests. CI runs it on every
  pull request and on `main`.
- `scripts/check-version.sh <base-ref>`: the version check CI runs on pull requests.
- `scripts/publish.sh <commit>`: what CI runs after `test` passes on `main`. It refuses while `RELEASE-HOLD` exists or
  `LICENSE` is missing, tags a new version once (`scripts/tag-release.sh`, which never moves a tag), and moves `release`
  to the commit with that tag in one atomic, fast-forward-only push.

Load the plugin from a checkout without installing it: `claude --plugin-dir plugins/stoda`.
