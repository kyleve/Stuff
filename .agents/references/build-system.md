# Build system and repository tools

## Build system

Update deployment targets, simulator command defaults, CI Xcode selection, and
snapshot runtime/renderer pins together. Review renderer changes before product
changes. Validate both the iOS suites and the native-macOS suite after an Xcode upgrade.

For a new workstation, use `./ide --bootstrap --no-open`; ordinary regeneration uses the root command contract.
Bootstrap installs missing Homebrew/mise tools, Git LFS, external skills, locked site/Fastlane dependencies, and Git hooks.
`./ide --install` also installs locked dependencies. After a site lockfile change, run `mise exec -- npm ci`.
Read [Tools ownership](../../Tools/AGENTS.md) before changing a command or its implementation.

### Managing app icons

After adding an icon with `./icons`, regenerate the project. Icon-set names are independent of audience selection.
Each audience selects its primary icon in `Project.swift`; every other set remains an alternate.
Change an audience's primary before removing that asset. `./icons --dry-run` previews its transaction.

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

The root contract defines when to regenerate attribution. `./attribution --check` detects drift offline.

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

Use the failing production syntax in the mutation fixture, including implicit
members where applicable. State known enforcement gaps in the rule catalog.
For graph assertions, mutate the project configuration while retaining its rule settings.
Assert the expected diagnostic and severity, plus a valid neighboring configuration.

## Generating the Xcode project

Use the [root command boundaries](../../AGENTS.md#essential-commands-and-boundaries).
