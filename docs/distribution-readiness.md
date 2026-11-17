# Distribution readiness: data inventory and directory checklist

This is the living engineering record of what the Stoda plugin reads, runs, sends and stores. It also tracks every
requirement for distributing it, including Anthropic's plugin directory.

**What this document is not:**

- It is **not** a privacy policy.
- It does not attest that any policy covers the plugin.
- It is not a legal opinion.
- It does not mean the plugin has been submitted to or approved by any directory.

**Ownership:**

- **Engineering:** the distribution workstream maintains this document.
- **Privacy-policy decisions:** no owner has been chosen yet (see [Responsibilities](#5-responsibilities)).

Last reviewed: 2026-11-17, against the official sources listed in [Sources](#sources).

## Maintenance rule

1. **Update with each change.** Every change to a skill, script, hook, MCP server or tool, integration, manifest or
   catalog entry updates this document in the same pull request, together with its evidence. That includes changes
   to what it reads, runs, sends, stores or promises.
2. **Coverage review before release.** A change to any of the following needs a coverage review, recorded here,
   before the affected version is considered ready to release:
   - data categories;
   - recipients or network destinations;
   - credentials or permissions;
   - storage or retention;
   - telemetry;
   - user-visible promises (README, manifest, listing text).
3. **Future work references this document.** Every future ticket and pull request that adds or changes a skill or
   MCP server or tool must link this document and add its inventory rows (marked *planned* until released).
   - Approval of the current read-only guide does not cover future MCP or backend work.
   - Nothing here authorizes that work.
4. **Unknowns stay unknown.**
   - Retention, deletion or behaviour controlled by a provider or host is written as such.
   - Nothing is described as "zero retention" or "collects nothing" without evidence.
5. **Recheck official requirements before any submission.** The rules below were read on the date above and can
   change.
6. **Keep the readiness states separate:** source slice done, submission-ready, submitted, approved, listed.

## Versions covered

| State | Version | Commit | What's in it |
|---|---|---|---|
| Released (`release` branch, tag `stoda--v0.1.20`) | 0.1.20 | `5bb84b6` | Catalog `.claude-plugin/marketplace.json`; plugin `plugins/stoda`: `plugin.json`, `LICENSE`, skill `guide`, script `scripts/inspect.sh` |
| Candidate (draft pull request #4, STO-1530; not merged or released) | 0.1.21 | `6bad462` | Adds `plugins/stoda/README.md` and the listing fields `displayName`, `supportUrl` and `documentationUrl`, with a new description. **No behaviour change**: `scripts/` and `skills/` are byte-identical to 0.1.20. |
| Planned | — | — | No further skills, hooks, MCP servers or integrations are approved. Rows are added here when a ticket proposes one (rule 3). |

## 1. Components

| Component | Runs where | Operated by | Released | Purpose |
|---|---|---|---|---|
| Catalog `.claude-plugin/marketplace.json` | Read by Claude Code at install and update | Stoda (content); GitHub (hosting) | 0.1.20 | Points Claude Code at `plugins/stoda` on the `release` branch |
| Manifest `plugins/stoda/.claude-plugin/plugin.json` | Read by Claude Code; read by `inspect.sh` for its version | Stoda (content) | 0.1.20 (fields added in 0.1.21) | Identity, version and listing metadata |
| Skill `guide` (`skills/guide/SKILL.md`) | Loaded into the Claude conversation when chosen by Claude or run as `/stoda:guide` | Stoda (text); Anthropic (model) | 0.1.20 | Read-only orientation: one card, one next step. It removes Claude Code's built-in acting tools for that turn. MCP tools are not removed; the skill only instructs Claude not to use them. |
| Script `scripts/inspect.sh` | The user's machine, as a subprocess, when the skill loads | Stoda (code); the user's machine (execution) | 0.1.20 | Gathers the facts in [Data](#2-data) |
| Plugin README | GitHub, the installed plugin folder, and a directory listing if one is ever made | Stoda | 0.1.21 candidate | User documentation and disclosure |

## 2. Data

These are all the facts `inspect.sh` prints. Its own header and the traced test in `tests/directory.bats` pin this
list.

| Fact | Source | Purpose | Necessary? | Sensitivity | Optional? |
|---|---|---|---|---|---|
| `plugin` version | The plugin's own `plugin.json` | Show which version answered | Yes (support) | None | No |
| `folder` | The last component of the current folder's path (the full path is read locally but not emitted) | Orientation | Yes | Low to moderate: a folder name can reveal a project or customer name | No (the skill always runs the script) |
| `repo` | `git rev-parse` | Whether there is a repository to reason about | Yes | Low | No |
| `branch` | `git symbolic-ref` | Orientation, next step | Yes | Low to moderate: branch names can carry ticket or customer names | No |
| `github` | `origin` remote URL, reduced to `owner/repo` for GitHub URLs; anything else prints `other` | Whether the repository is on GitHub | Yes | Moderate: private repository names | No |
| `upstream` | `git rev-parse @{upstream}`, or `config --get branch.<name>.merge` as a fallback | The push next step | Yes | Low to moderate | No |
| `submodules` | `.gitmodules` exists, or the index has gitlink entries (`git ls-files -s`) | So the guide can say what it didn't check | Yes | Low | No |
| `unpushed` | `git rev-list --count @{upstream}..HEAD` | The push next step | Yes | Low | No |
| `tool git` / `tool gh` | `command -v` | The install next step | Yes | Low | No |
| `gh-auth` | The exit code of `gh auth status --hostname github.com` | The sign-in next step | Yes (for that step) | Low as output. The command itself uses a credential (see [Credentials](#3-credentials-and-permissions)). | No; there's no option to skip it today |

**Read locally versus sent to Claude.** The table above is what `inspect.sh` **emits**, which is what enters the
Claude conversation. To produce it, the script **reads more than it emits**. All of that stays on the user's machine,
in the script's memory and in the processes it starts:

| Read locally (not emitted) | Why | What is emitted instead |
|---|---|---|
| The current folder's **full path** (the shell's working directory) | To name the folder | Only the last path component |
| The **full `origin` remote URL** (`git remote get-url origin`, captured into a shell variable) | To find a GitHub owner/repo | Only `owner/repo` for an exact `https://github.com/`, `git@github.com:` or `ssh://git@github.com/` URL; otherwise `other`. A URL with credentials embedded (for example, user information before the host) doesn't match those patterns and is emitted as `other`. **The URL, credentials included, still passes through git and the script's memory.** The plugin makes no secure-erasure promise, and no promise about what the host logs. Evidence: `inspect.sh` lines 40–43 and `tests/inspect.bats` (https, ssh, scp and non-GitHub forms). **There is no dedicated test for a credential-bearing URL (gap).** |
| The plugin's own `plugin.json` (plugin metadata, not the user's files) | Its version | `plugin <version>` |
| Repository metadata: refs, config, the index (`ls-files -s`: paths, modes and object ids) and **commit objects** (`rev-list --count` walks the history between upstream and HEAD) | Branch, upstream, submodules, unpushed count | Only the facts in the table |
| Whether `.gitmodules` exists (an existence check, not its contents) | Submodules | `submodules yes/no/unknown` |

**Not explicitly queried or emitted.** These are limits on what the script asks for and outputs. They are not a
claim that the data never passes through memory:

- **Working-tree files:** the script runs no command that reads their contents or uncommitted changes (no
  `git status` or diff).
- **Commit messages, author names and emails:** the script doesn't query or emit them. `rev-list --count` emits only
  a number. Git reads whole commit objects internally to walk history, so these fields are **not excluded from Git's
  internal reads**.
- **GitHub CLI tokens:** the script makes no intentional extraction. It doesn't read or print `GH_TOKEN`,
  `GITHUB_TOKEN` or `gh`'s stored credential; `gh` uses its own credential internally (see
  [Credentials](#3-credentials-and-permissions)). **Exception:** any credential embedded in the `origin` remote URL is
  captured into the script's memory with that URL, transiently (see above). It is not emitted, and there is no
  provenance or secure-erasure guarantee.

**Derived data:** the card and next step Claude writes from these facts, in the conversation.

**Personal or customer data:** none is sought. But folder, branch and repository names are free text chosen by the
user and can contain personal, customer or confidential names. Treat them as potentially sensitive.

## 3. Credentials and permissions

| Credential | Accessed by | How | Plugin handling | Unknowns |
|---|---|---|---|---|
| GitHub CLI credential. **Categories:** an OAuth or personal access token that `gh` takes from the environment (`GH_TOKEN` or `GITHUB_TOKEN`, when set) or from its own stored login (the system keyring or `gh`'s config). This inventory records categories only: it never inspects actual values, sources or scopes. | `gh`, run by `inspect.sh` | `gh auth status` tests the account against GitHub | The plugin makes no intentional extraction of the token, and doesn't print or store it. `gh`'s output is discarded; only the exit code is used. The skill tells Claude never to print tokens, keys or passwords. | **Which source applies, and the token's scopes, are unknown to us; not probed.** It is unverified whether `gh` sends anything beyond the authentication check (for example, update checks). |
| Git credentials and helpers | Not invoked | The git commands used are local and never contact a remote | None | — |
| Claude account | Not accessed by the plugin | — | — | — |
| Plugin `userConfig`, secrets, OAuth | None declared | — | — | — |

**Optional, and with no field-level opt-out.** The whole plugin is optional: a user can uninstall or disable it.
While it is enabled:

- Claude may choose the guide whenever a request matches its description, or the user runs `/stoda:guide`.
- Each run reads and emits every fact above.
- There is **no per-field opt-out**. In particular, there is no option to skip the `gh auth status` call while `gh`
  is installed.

**Permissions:**

- The plugin declares no MCP servers, hooks or `userConfig`.
- The skill pre-approves only its own script (`allowed-tools`) and removes Claude Code's built-in acting tools for the
  turn (`disallowed-tools`).

## 4. Flows, recipients, storage and retention

| Flow | From → to | Operator | What | Stored where | Retention and deletion |
|---|---|---|---|---|---|
| Install and update | GitHub → the user's machine | GitHub (hosting); Anthropic's Claude Code (client) | Plugin files; GitHub sees the request (IP address, client) | Claude Code's plugin cache on the user's machine | **Host-controlled.** Claude Code manages the cache. GitHub's request logs are provider-controlled and unknown to us. |
| Local inspection | The user's repository → `inspect.sh` → the skill text | The user's machine | Reads the local items in [Data](#2-data), including the full path and the full `origin` URL; emits only the facts | The script writes no files, logs or git index entries | Values pass through the script's memory and the git processes; there is no secure-erasure promise and no promise about host logging. |
| **Conversation** | Skill text with the facts → Claude | Anthropic | The facts, and Claude's card and next step | Wherever the user's Claude product keeps conversations (for example, Claude Code's local transcripts and Anthropic's service) | **Provider- and host-controlled; unknown to us.** It depends on the user's Claude plan and settings. Not zero. |
| **GitHub sign-in check** | `gh` → GitHub (github.com) | GitHub | An authenticated request using the user's existing gh credential | GitHub | **Provider-controlled; unknown to us.** `gh` may also keep its own local state; unverified. |
| Telemetry | — | — | **None from the plugin.** There is no Stoda-operated backend, so nothing reaches Stoda at run time. | — | Claude Code's and gh's own telemetry, if any, is host-controlled and outside the plugin. |
| Support and security reports | User → GitHub issues (public) or GitHub security advisories (private) | GitHub; Stoda maintainers read them | What the user chooses to write | GitHub | Provider-controlled; Stoda maintainers can see reports |
| Directory usage figures (only if ever listed) | Anthropic → the submitting organization's portal | Anthropic | Installs, versions, runs and error rates, per the directory docs | Anthropic | **Unknown; a future flow to Stoda.** It needs a coverage review before listing. |

### Deletion controls

| Where data ends up | Deletion control | Known? |
|---|---|---|
| Plugin files in Claude Code's plugin cache | Claude Code's `plugin uninstall` and its cache handling | **Host-controlled.** Whether every cached version is removed is not verified here. |
| Facts and answers in the conversation | The user's Claude product: local transcripts in Claude Code, and conversation history on Anthropic's side | **Unknown and provider- or host-controlled.** Uninstalling the plugin does **not** delete conversation history or anything already sent. |
| Anthropic's service logs | Anthropic | **Unknown**; provider-controlled |
| GitHub's logs of the `gh auth status` request | GitHub | **Unknown**; provider-controlled |
| Local state `gh` may keep | `gh` | **Unknown**; not verified |
| Support issues (public) and security advisories (private) | GitHub's controls for authors, maintainers and admins | **Provider-controlled.** Copies others have already seen (notifications, email) aren't deletable by Stoda. |
| Directory usage figures (only if ever listed) | Anthropic | **Unknown** |

## 5. Responsibilities

| Area | Who |
|---|---|
| Code, tests, this inventory, README disclosures | Distribution workstream (engineering) |
| Releases (`scripts/promote.sh`) | Repository admins |
| Privacy-policy coverage, wording and URL | **Undecided.** No decision owner has been chosen, and discussion recipients are not assignees. The record of where this stands is kept privately in STO-1529, not here. |
| Directory submitter and listing organization | **Undecided**; settled only at the portal stage |
| The model and conversation handling | Anthropic, under the user's Claude terms |
| `gh` and GitHub request handling | GitHub, under the user's GitHub terms |

## 6. Disclosure and evidence

| What | Where | State |
|---|---|---|
| What runs and sends | `plugins/stoda/README.md`, "What it runs and what it sends" | 0.1.21 candidate (PR #4) |
| Inspector behaviour | `plugins/stoda/scripts/inspect.sh` header | Released |
| Read-only: no writes, filters, hooks or index refresh; unknown facts reported as unknown | `tests/inspect.bats` | Released; CI |
| Every fact, command and exact `git`/`gh` argument list is disclosed, including the fallback paths | `tests/directory.bats` (traced run) | Candidate. CI `test` passed on `6bad462`. `release-ready` fails on pull requests by design; no release-ready claim is made. |
| Listing fields; no privacy URL or icon set | `plugins/stoda/.claude-plugin/plugin.json`, `tests/directory.bats` | Candidate |
| Directory validation on a copy outside git, checking every resolved ancestor up to `/` | `just directory` | Candidate; CI |
| Claude Code install and update of a release; the guide answering correctly | Release canary records for 0.1.19 and 0.1.20 (Claude Code 2.1.326) | Done for Claude Code only |
| Privacy-policy URL in the manifest | — | **Not set**, pending a decision owner and coverage. Not set merely because a policy page exists. |

## Directory checklist

Results are what the official pages say happens when a check fails:

- **Blocks:** the plugin can't be submitted.
- **Hold:** a reviewer must clear the version.
- **Warning:** submission is allowed.

The **Policy** and **Terms** rows come from the full text of the Software Directory Policy and Terms. "Conditional"
means the item applies only if the plugin has that feature.

### Required

| Item | Source | State | Stage it blocks | Tracking |
|---|---|---|---|---|
| A README of at least 40 words in the plugin folder | Pre-submission checklist (blocks) | **Candidate** (PR #4) | Submission | STO-1530 |
| A licence file or field | Pre-submission checklist (blocks) | Met (MIT, both) | — | — |
| Valid manifest and front matter; paths inside the plugin; no symlinks, LFS, system files or bad names; size limits | Pre-submission checklist (blocks or stops validation) | Met (local validation, directory profile) | — | — |
| No real credentials in any file | Pre-submission checklist (blocks) | Met | — | — |
| A name that is ours, not reserved, not taken | Pre-submission checklist | Locally met; "not taken" is checked only by the portal | Submission | Portal |
| README describes everything run, sent or fetched (security scan) | Pre-submission checklist | **Candidate** (PR #4) | Submission | STO-1530 |
| Documentation of how it works, its purpose and troubleshooting | Policy 3C | **Candidate** | Review | STO-1530 |
| Verified support channel | Policy 3B | **Candidate** (`supportUrl`, issues) | Review | STO-1530 |
| Security-report mechanism | Terms | Private vulnerability reporting enabled; documented in the candidate | Review | STO-1530 |
| At least three working example prompts | Policy 3E | Text in the candidate. "Working" is proven in Claude Code only. | Review | STO-1530; surface testing |
| **Privacy policy link**: the plugin "connects to a remote service" (gh to GitHub) | Policy 3A; Terms (iv) | **Open.** No decision owner; coverage unverified. | Submission and review | STO-1529 |
| Standard test account with sample data | Policy 3D | Applicability unverified (there's no account system) | Review | Reviewer outcome |
| Own or control the endpoints connected to | Policy 3F | Unverified how a third-party CLI's own call is treated | Review | Reviewer outcome |
| Descriptions match behaviour; no hidden instructions; no unrequested external calls | Policy 2B, 2D, 2G | Met in text; the README discloses the gh call | Review | — |
| Raise the version with every release | Submit page | Met (CI version check) | Each release | — |
| Notify Anthropic of material changes (functionality, descriptions, data practices, connected endpoints) **after listing**; they may be re-reviewed | Policy 3H | Not yet applicable. Applies to every post-listing change the maintenance rule flags. | After listing | Maintenance rule |
| Maintain the software and address issues in reasonable time | Policy 3G | Ongoing | After listing | — |
| No statement suggesting partnership with, sponsorship by or endorsement by Anthropic | Terms | Met in the current text. Every README or listing change is checked for it. | Review | — |
| Rights to everything provided; no third-party IP infringement | Terms (i); Policy 1F | Code: MIT, copyright Stoda. **The licence covers code only, not the Stoda name or logo.** The Terms grant Anthropic a licence to display the name, logos and branding, so brand rights must be confirmed by whoever holds them before an icon is submitted. | Submission | STO-1523 |
| Submitting organization, plan and role; GitHub connected with push access | Submit page; Publish page | **Open** | Portal | Portal |
| Data-handling answers; contact email; acknowledgements; Terms accepted | Submit page | **Open.** Answers must match this inventory. | Portal | Portal |
| Repository public before going live | Submit page | Met | — | — |
| Security scan passes; every new listing is reviewed by a person | Pre-submission checklist; Publish page | Not run | After submission | Portal |

### Conditional (none applies today)

These apply only when the plugin adds the feature: package launchers (pinned versions), registry config files, MCP
servers (schema, `https`/`wss`, `command` and `args`, OAuth for authenticated remote servers), hooks, lockfiles,
bundled binaries, and `userConfig` for credentials. Any future skill, MCP or backend work must add its rows here (rule 3).

### Recommended

| Item | Source | State | Tracking |
|---|---|---|---|
| Icon: square PNG or JPEG, 512–2048 px. **It becomes the listing icon only at the first portal save or submit.** | Local validator; manifest reference | Missing (warning). Waiting for STO-1523 before the first portal save is recommended. | STO-1523 |
| `displayName`, `documentationUrl`, `supportUrl` | Manifest reference; build page | Candidate | STO-1530 |
| Test on each surface the portal lists (skills load in claude.ai chat, Cowork and Claude Code) | Build page; platform support | **Claude Code only.** Chat and Cowork are untested; a README statement is not testing. | STO-1529 |
| Evaluate with `claude plugin eval` | Pre-submission checklist | Not done | — |
| Track the `release` branch and path `plugins/stoda` in the portal; set up the push webhook | Submit page | Portal decision | Portal |
| `termsOfServiceUrl` | Manifest reference | Not set; optional | — |

### Open gaps

| Gap | Impact | Next step or decision | Owner | Blocks |
|---|---|---|---|---|
| Privacy-policy coverage and URL | Required by Policy 3A | Choose a decision owner. That owner decides coverage against this inventory. No URL is set until then. | Undecided | Submission |
| Icon | Set once, permanently, at the first portal save | Deliver STO-1523 before any portal save | STO-1523 | First portal save (recommended) |
| Chat and Cowork behaviour | Listing claims and example prompts there | A test on those surfaces, under separate approval | Unassigned | Submission-readiness |
| gh's extra network behaviour and local state | Disclosure accuracy | Confirm from gh's documentation, or with a network-isolated test | Engineering | Coverage review |
| Credential hold, test account, endpoint ownership | Possible reviewer hold | Reviewer outcome after submission | Anthropic | Listing |
| No test that a credential-bearing `origin` URL is emitted as `other` | Evidence for a privacy-relevant claim rests on source reading only | Add a test in a later source slice (not this docs change) | Engineering | Coverage review |
| Directory usage figures reaching Stoda | A new data flow if listed | Coverage review before listing | Undecided | Listing |
| Submitting organization and portal ownership | The first organization to submit owns the listing | Decide at the portal stage | Undecided | Portal |

## Sources

All retrieved 2026-11-17:

- [Submit your plugin](https://claude.com/docs/plugins/submit)
- [Plugin pre-submission checklist](https://claude.com/docs/plugins/pre-submission-checklist.md)
- [Publish to the directory](https://claude.com/docs/directory/publish.md)
- [Plugin structure and testing](https://claude.com/docs/plugins/build.md)
- [Plugin feature support across platforms](https://claude.com/docs/plugins/platform-support.md)
- [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference)
- [Anthropic Software Directory Policy](https://support.claude.com/en/articles/13145358-anthropic-software-directory-policy)
- [Anthropic Software Directory Terms](https://support.claude.com/en/articles/13145338-anthropic-software-directory-terms)
