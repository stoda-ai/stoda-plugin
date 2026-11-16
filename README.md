# stoda-plugin

The Stoda plugin for Claude Code, and the marketplace it is installed from.

## Status

Pre-release. The plugin has no skills yet; the first one is being designed. Nothing here is published, and this
README describes how installing and updating will work once it is.

Not approved yet, and so not included: the license, the Stoda logo and plugin icon, and the wording of this README.
Until they are approved and added, no release is made (`RELEASE-HOLD`).

## Install

In Claude Code:

```
/plugin marketplace add stoda-ai/stoda-plugin
/plugin install stoda@stoda
```

or from a shell: `claude plugin marketplace add stoda-ai/stoda-plugin`, then `claude plugin install stoda@stoda`.
Every command the plugin adds is `/stoda:<name>`.

## Updates

The `main` branch is what users install. A change reaches installed copies only when it raises `version` in
`plugins/stoda/.claude-plugin/plugin.json`; CI refuses a pull request that changes the plugin without raising it.
Run `/plugin marketplace update stoda` (or turn on auto-update for the `stoda` marketplace in `/plugin`) to pick up
a new version.

Each released version is tagged `stoda--v<version>` on the commit it was released from. To stay on one version, add
the marketplace at that tag: `/plugin marketplace add stoda-ai/stoda-plugin#stoda--v<version>`.

## What this repository holds

Only generic Stoda plugin source: skills, their scripts, and the plugin and marketplace manifests. No organization's
settings, names, keys or other client information belong here. A skill that needs an organization's values reads
them at run time from outside the plugin.

## License

Not decided yet. No license is granted until a `LICENSE` file is added to this repository.

## Development

Needs `just`, `bats`, `shellcheck`, `jq` and Claude Code.

- `just test`: validate the marketplace and plugin manifests, lint the scripts, run the tests. CI runs it on every
  pull request and on `main`.
- `scripts/check-version.sh <base-ref>`: the version check CI runs on pull requests.
- `scripts/tag-release.sh <commit>`: what CI runs after `test` passes on `main` to tag the release. It never moves a
  tag; it refuses when the plugin changed since that version's tag without a new version.

Load the plugin from a checkout without installing it: `claude --plugin-dir plugins/stoda`.
