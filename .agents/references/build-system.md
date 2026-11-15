# Build system and repository tools

## Build system

| Tool        | Pinned via   |
|-------------|--------------|
| Tuist       | `.mise.toml` |
| SwiftFormat | `.mise.toml` |
| ShellCheck  | `.mise.toml` |
| Ruby        | `.mise.toml` |
| Fastlane and Ruby dependencies | `Gemfile.lock` |
| Node.js     | `.mise.toml` |
| Astro and TypeScript | `package-lock.json` |
| Swift PM    | `Package.swift` (`swift-tools-version`) |
| Bumper Bowling | `Package.swift` / `Package.resolved` |
| Xcode snapshot renderer | `.xcode-version` |


Read the exact pinned versions from those files. Do not trust a copy in prose. A version in a doc goes stale without notice.

Update deployment targets, simulator command defaults, CI Xcode selection, and
snapshot runtime/renderer pins together. Review renderer changes before product
changes. Validate both the iOS suites and the native-macOS suite after an Xcode upgrade.

Library targets live in the root [`Package.swift`](../../Package.swift) (one local
package). Apps, app extensions, and test bundles are Tuist targets in
[`Project.swift`](../../Project.swift) (plus [`Tuist.swift`](../../Tuist.swift)). That file
references the package via `Package.local(path: .relativeToRoot("."))`. The
two manifests are the authoritative target catalog. This file does not duplicate that catalog.

`./ide` regenerates the Xcode project and does the surrounding setup. That setup includes external agent skills and `core.hooksPath`. Use `./ide` to regenerate. Do not use `tuist generate` alone. Agents must always pass `--no-open` (see [Generating the
Xcode project](#generating-the-xcode-project)). On a fresh machine, run `./ide
--bootstrap` first. That command installs missing Homebrew and mise tools before
generating. See [Getting started](../../README.md#getting-started) for the workstation setup.
Plain `./ide` fails fast if Git LFS or mise is missing and points at bootstrap.
`./ide --bootstrap` and `./ide --install` also install the locked site and Fastlane dependencies.
After a site lockfile change, run `mise exec -- npm ci`.

The executables in the repo root are the dev scripts. They are `ide`, `test`,
`swiftformat`, `sf-symbols`, `sync-agents`, `profile`, `flyover`, `icons`, `flaky`, `simulator`,
`worktree`, `signing`, `xcstrings`, `attribution`, `shellcheck`, `codex-watchdog`, `tla-check`,
`circleci-artifacts`, `snapshot-shards`, `loc`. Each takes `--help`. Use one of these scripts instead of
hand-rolling its job. `./test` owns iOS and host-side tests
(see [Running tests](../skills/running-tests/SKILL.md#architecture-and-host-checks)). `./icons`, `./attribution`, and `./simulator` own state that is
easy to corrupt by hand. `./simulator` owns a per-checkout device (see the
[`running-tests`](../skills/running-tests/SKILL.md) skill).

Retained Python and Ruby implementations are importable and directly tested
under `Tools/Tests`; shell around them is limited to public argument handling,
bootstrap, and process orchestration. In particular,
`tla-check` owns discovery and the pinned TLC download while
`Tools/tla_check.py` owns manifest validation, TLC argv, and result policy.
Read [`Tools/AGENTS.md`](../../Tools/AGENTS.md) for changes to these implementations
or their public command wrappers.

### Managing app icons

`./icons` is the single command for the Where app's alternate icons (see
`./icons --help`). It keeps both asset catalogs and the picker's
`AppIcons.json` manifest in sync — never hand-edit those or add icon Swift.
It stages and validates the whole change before replacing anything and supports
`--dry-run`. Never hand-edit those files. Never add icon Swift. Run
`./ide --no-open` after adding one. Icon-set names are independent of
primary/alternate status: each Where audience selects its primary icon in
[`Project.swift`](../../Project.swift), and every other set remains selectable as an
alternate. Change an audience's primary before asking `./icons` to remove that
asset; the command refuses to delete any configured primary.

### Where build audiences

The Where host targets have three explicit schemes — **Where Development**
(`Debug`), **Where Beta** (`Beta`), and **Where App Store** (`Release`) — whose
audience descriptors live in [`Project.swift`](../../Project.swift). Keep bundle IDs,
App Group, display name, primary icon, configuration, and the matching
`WHERE_DEVELOPMENT` / `WHERE_BETA` / `WHERE_APP_STORE` compiler condition in
that one descriptor. These custom conditions belong only to the app, widget,
and share-extension targets; package targets receive audience-dependent values
by injection. Development uses its own bundle family and local-only store;
Beta and App Store share the production bundle family and CloudKit store.

### Version and build metadata

Bump the Where app's `CFBundleShortVersionString` / `CFBundleVersion`
explicitly in [`Project.swift`](../../Project.swift) (Settings > About shows them).
How the app was built is stamped by a post-build script
([`Where/Where/Scripts/stamp-build-info.sh`](../../Where/Where/Scripts/stamp-build-info.sh)).
The script writes the commit into `WhereGitSHA` / `WhereGitStatus`. It writes how the Swift compiler
was invoked into `WhereConfiguration` / `WhereSwiftOptimizationLevel` /
`WhereSwiftCompilationMode`. All of it is read back by `WhereCore.BuildInfo`.
Settings > About uses it. Every Periscope logging session uses it for attributes.
Where builds call [`Tools/InstallerKit/stamp-installer-info.sh`](../../Tools/InstallerKit/stamp-installer-info.sh) before signing for shared InstallerKit identity.
The Development audience descriptor provides app, repository, feed URL, and the local channel.
CI archives override the channel, run, and attempt. Local builds keep honest Git status and no publication identity.
The optimization level tells you if a recorded span duration means
anything. Only the app is stamped. Tripwires: it must stay a **post** script
(before signing seals the bundle). Keep `basedOnDependencyAnalysis: false`. If you do not, an unchanged tree ships the previous commit's SHA. Set
`ENABLE_USER_SCRIPT_SANDBOXING` unset (it reads `.git`). Every key it
writes must fall back to `unknown`. Do not let `set -u` abort the build
over a build setting Xcode didn't export.

## Attribution

An app ships an **attribution report**. It lists every third-party work it is built
with, with license notices inline. **Re-run `./attribution` and commit the result
whenever you add or bump a package, an agent skill, or a development tool**.
`./attribution --check` fails CI if you forget (offline, sub-second). An app's
own tests can't do this job. A test bundle can't read `Package.swift`.

- [`Shared/CreditKit`](../../Shared/CreditKit/AGENTS.md) owns the types and the
  reporting tool and holds **no credits of its own**. Each app declares its
  sources in an `attribution-sources.json` and ships the report in its own
  resources (for Where, `Where/Where/Resources/attribution.json`).
- The report derives from `.product(name:package:)` links (pinned by
  `Package.resolved`), `.agents/external-skills.json`, and
  `.agents/development-tools.json`. Notices are read at the pinned revision. Tooling-only packages are not credited.
- **Kind is derived, not declared**. Anything reachable from `shippedFrom`'s
  target closure is a library. Any other linked package is a development tool.
  Linking is not shipping. A UI must keep the two apart.
- Data-source provenance for bundled geometry stays with its data, in
  [`RegionKit`](../../Where/RegionKit/AGENTS.md).

## Architecture lint

Bumper Bowling enforces the production Where module graph, the shared
InstallerKit/InstallerKitUI boundaries and selected source-level invariants. Classified logging
authoring rules also cover the Periscope and consumer source/test paths. The entry point is
[`BumperBowling.swift`](../../BumperBowling.swift). Repository-owned shapes and rules
live in [`.bumper/Sources`](../../.bumper/Sources). [`.bumper/RULES.md`](../../.bumper/RULES.md) is the rule catalog.

Run `./test --architecture-only` after changing a Where dependency,
composition root, or documented concurrency boundary. This command validates
the configuration, tests the rules, and runs the lint. Keep the relevant
`AGENTS.md`, the executable rule, its catalog entry, and its mutation test in
the same change.
Use the failing production syntax in the mutation fixture, including implicit
members where applicable. State known enforcement gaps in the rule catalog.
For graph assertions, mutate the project configuration while retaining its rule settings.
Assert the expected diagnostic and severity, plus a valid neighboring configuration.

## Generating the Xcode project

Agents must never open Xcode on the user's machine. It steals focus and
disrupts the user's session. Regenerate with `./ide --no-open`.
Do not bypass `./ide` with a direct `tuist generate` invocation.

`tuist test` / `tuist build` are CLI-only and do not open Xcode. No
flag is needed there.
