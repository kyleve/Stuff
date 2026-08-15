# Stuff – Repository Shape

This file is the repo-wide contract. It covers the build system, Swift conventions, and how to work with branches, commits, PRs, and CI. **Every module also carries its own `AGENTS.md`**. That file covers scope, layering, and invariants. Read this file first. Then read the module's file. The two files do not repeat each other. Neither file is sufficient alone.

Roughly, this file covers:

- **Building and testing** — [Build system](#build-system),
  [Formatting](#formatting), [Targets](#targets), [Deployment](#deployment),
  [Generating the Xcode project](#generating-the-xcode-project),
  [Running tests](#running-tests),
  and the [Linux/Cloud caveats](#cursor-cloud-specific-instructions).
- **Writing code** — [Per-module docs](#per-module-docs) (and the module layout),
  [Repo-level docs](#repo-level-docs), and [Conventions](#conventions)
  (including [Modeling state](#modeling-state) and
  [Composition](#composition-create-once-inject-down)). Load the
  [`building-ui`](.agents/skills/building-ui/SKILL.md) skill for SwiftUI/UIKit
  construction, Broadway styling, accessibility, previews, and snapshots.
- **Working** — [Working in this repo](#working-in-this-repo): commits.
  [GitHub](#github) and [running tests](#running-tests) load their skills when
  needed.

## Build system

| Tool        | Pinned via   |
|-------------|--------------|
| Tuist       | `.mise.toml` |
| SwiftFormat | `.mise.toml` |
| Ruby        | `.mise.toml` |
| Swift PM    | `Package.swift` (`swift-tools-version`) |
| Bumper Bowling | `Package.swift` / `Package.resolved` |


Read the exact pinned versions from those files. Do not trust a copy in prose. A version in a doc goes stale without notice.

Library targets live in the root [`Package.swift`](Package.swift) (one local
package). Apps, app extensions, and test bundles are Tuist targets in
[`Project.swift`](Project.swift) (plus [`Tuist.swift`](Tuist.swift)). That file
references the package via `Package.local(path: .relativeToRoot("."))`. The
two manifests are the authoritative target catalog. This file does not duplicate that catalog.

`./ide` regenerates the Xcode project and does the surrounding setup. That setup includes external agent skills and `core.hooksPath`. Use `./ide` to regenerate. Do not use `tuist generate` alone. Agents must always pass `--no-open` (see [Generating the
Xcode project](#generating-the-xcode-project)). On a fresh machine, run `./ide
--bootstrap` first. That command installs `mise` and the pinned tools before
generating. Plain `./ide` fails fast and points at bootstrap.

The executables in the repo root are the dev scripts. They are `ide`, `test`,
`swiftformat`, `sf-symbols`, `sync-agents`, `profile`, `icons`, `flaky`, `simulator`,
`worktree`, `xcstrings`, `attribution`, `codex-watchdog`, `tla-check`,
`circleci-artifacts`, `snapshot-shards`, `test-impact`, `loc`. Each takes `--help`. Use one of these scripts instead of
hand-rolling its job. `./test` is the only way to run tests (see [Running
tests](#running-tests)). `./icons`, `./attribution`, and `./simulator` own state that is
easy to corrupt by hand. `./simulator` owns a per-checkout device (see the
[`running-tests`](.agents/skills/running-tests/SKILL.md) skill).

### Managing app icons

`./icons` is the single command for the Where app's alternate icons (see
`./icons --help`). It keeps both asset catalogs and the picker's
`AppIcons.json` manifest in sync. Never hand-edit those files. Never add icon Swift.
Run `./ide --no-open` after adding one.

### Version and build metadata

Bump the Where app's `CFBundleShortVersionString` / `CFBundleVersion`
explicitly in [`Project.swift`](Project.swift) (Settings > About shows them).
How the app was built is stamped by a post-build script
([`Where/Where/Scripts/stamp-build-info.sh`](Where/Where/Scripts/stamp-build-info.sh)).
The script writes the commit into `WhereGitSHA` / `WhereGitStatus`. It writes how the Swift compiler
was invoked into `WhereConfiguration` / `WhereSwiftOptimizationLevel` /
`WhereSwiftCompilationMode`. All of it is read back by `WhereCore.BuildInfo`.
Settings > About uses it. Every Periscope logging session uses it for attributes.
The optimization level tells you if a recorded span duration means
anything. Only the app is stamped. Tripwires: it must stay a **post** script
(before signing seals the bundle). Keep `basedOnDependencyAnalysis: false`. If you do not, an unchanged tree ships the previous commit's SHA. Set
`ENABLE_USER_SCRIPT_SANDBOXING` unset (it reads `.git`). Every key it
writes must fall back to `unknown`. Do not let `set -u` abort the build
over a build setting Xcode didn't export.

## Formatting

- **SwiftFormat** uses [`.swiftformat`](.swiftformat). Run `./swiftformat` to
  format the tree. Run `./swiftformat --lint` to make sure that formatting is correct (as in CI).
- The pre-commit hook (enabled by `./ide` via `core.hooksPath`) formats staged
  `*.swift` files in place and re-stages them.
- **String Catalogs are stored exactly as Xcode serializes them**. `./xcstrings` (`--lint` in CI) enforces this. A catalog written by anything
  else parses fine. The next IDE build then produces thousands of lines of
  whitespace churn. Write catalogs through Xcode. Or normalize with the
  script afterwards (it touches formatting only, never content).

## Attribution

An app ships an **attribution report**. It lists every third-party work it is built
with, with license notices inline. **Re-run `./attribution` and commit the result
whenever you add or bump a package, an agent skill, or a development tool**.
`./attribution --check` fails CI if you forget (offline, sub-second). An app's
own tests can't do this job. A test bundle can't read `Package.swift`.

- [`Shared/CreditKit`](Shared/CreditKit/AGENTS.md) owns the types and the
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
  [`RegionKit`](Where/RegionKit/AGENTS.md).

## Architecture lint

Bumper Bowling enforces the production Where module graph and selected
source-level invariants. The entry point is
[`BumperBowling.swift`](BumperBowling.swift). Repository-owned shapes and rules
live in [`.bumper/Sources`](.bumper/Sources). [`.bumper/RULES.md`](.bumper/RULES.md) is the rule catalog.

Run `./test --architecture-only` after changing a Where dependency,
composition root, or documented concurrency boundary. This command validates
the configuration, tests the rules, and runs the lint. Keep the relevant
`AGENTS.md`, the executable rule, its catalog entry, and its mutation test in
the same change.

## Agent instructions sync

`AGENTS.md` is the source of truth for AI agent instructions. Cursor reads
`AGENTS.md` natively. Claude Code uses `CLAUDE.md` and `.claude/skills/`.
Generated files (`CLAUDE.md`, `.claude/skills/`) are gitignored and produced
by `./sync-agents`.

- `./sync-agents` — generate `CLAUDE.md` next to each `AGENTS.md` and mirror
  `.agents/skills/` into `.claude/skills/`.
- `./sync-agents --install` — fetch external skills listed in
  `.agents/external-skills.json`. Rarely run by hand. `mise install` calls it
  from a `postinstall` hook. Installing tools also installs skills on a dev
  machine and a cloud agent. CI sets `MISE_NO_HOOKS=1` because CI does not use
  agent skills.
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills to the latest commit.

`.agents/external-skills.json` pins the **external** skills to a commit.
`.agents/skills/.gitignore` excludes those fetched copies. Anything else
under `.agents/skills/` is **repo-owned** and committed. External skills are
also an **attribution** input. After adding or updating one, re-run
`./attribution` (see [Attribution](#attribution)). The same applies to
`.agents/development-tools.json` when pinned verification or other non-SPM
tooling changes.

**`.agents/skills/` is the real home**. Edit the source. Never edit the
`.claude/skills/` mirror. Run `./sync-agents` after adding or editing a
skill. Cursor loads both directories. The winning copy is undocumented.
Do not let them drift. A fresh clone carries only the repo-owned skills. The
external ones arrive with the first `mise install`.

A skill carries **procedure**. That is the steps of an occasional job. It includes
rules that apply only while that job runs (GitHub, running tests, backlog
triage). **Always-on** rules every edit must honor stay in `AGENTS.md` or
`TODOs.md`.

## Targets

- For the current list of library products, apps, extensions, and test
  bundles, read [`Package.swift`](Package.swift) and
  [`Project.swift`](Project.swift). Each module's own `README.md` /
  `AGENTS.md` says what it is and how it can be used.
- Add SPM library targets in `Package.swift` and wire apps/tests in `Project.swift` (see existing `unitTests` helper. Native-macOS test bundles are declared directly, like `LedgerCoreTests`, since that helper hosts iOS bundles in StuffTestHost). A new module also ships a root `README.md` and `AGENTS.md` — see [Per-module docs](#per-module-docs).
- **CI schemes**: CI runs explicit shared schemes rather than the autogenerated `Stuff-Workspace` scheme. **Stuff-iOS-Tests** covers the iOS bundles. **Ledger-macOS-Tests** (the Ledger app + `LedgerCoreTests`) runs in its own `test-macos` job. The workspace mixes iOS targets with the native-macOS **Ledger** ones. No single xcodebuild destination can build both. Add a new test bundle to the matching scheme in `Project.swift`. If you do not, CI will not run it.
- **CircleCI build handoff**: CircleCI builds both iOS schemes sequentially on one `m4pro.large` builder. The unit worker and parallel snapshot workers attach its products and run without compilation. Each worker validates the build manifest and shadow test-impact selection before it starts a simulator. Shadow mode runs the full assigned scope and publishes selection audits without skipping tests. `./snapshot-shards` owns deterministic suite assignments and must match the snapshot job parallelism.
- **Image snapshots are the exception: one bundle per module, one shared scheme.** Each module owning image references has its own `*SnapshotTests` target over its `SnapshotTests/` folder. All are listed in the single shared **StuffSnapshotTests** scheme and its dedicated CI `snapshot` job. Snapshots are slow and LFS-backed. They are **out of** `Stuff-iOS-Tests`. References under any `__Snapshots__/` directory are Git LFS (`.gitattributes`. The CI job hydrates them explicitly). Framework halves: `Shared/SnapshotKit` (shippable matrix + previews) and `Shared/SnapshotKitTesting` (test-only pipeline, whose own regression bundle **SnapshotKitTestingTests** pixel-probes without LFS and runs in `Stuff-iOS-Tests`).
- **A new image suite gets a target, not a scheme.** Add the `*SnapshotTests` target. List only `SnapshotKitTesting` in `extraPackageProducts`. Add it to the `StuffSnapshotTests` scheme's build and test lists. Never add a scheme or CI job of its own. An image bundle links only what its module needs (the Periscope and Inspector suites don't build against WhereUI at all). References follow the sources automatically via `#filePath`.
- **Separate snapshot bundles are safe because each `.xctest` gets its own `StuffTestHost` process** (measured on Xcode 27 — `ProcessInfo.processIdentifier` probes. Details in the snapshot-bundle comment in [`Project.swift`](Project.swift)). Each bundle statically embeds its own copy of `SnapshotKitTesting`'s capture state. Two copies in one process corrupt each other. Tripwire: if a toolchain ever shares one host process across bundles, re-measure before adding another image bundle.
- **Snapshots containing scrolling content use full-content sizing.** Use SnapshotKit's full-content device presets for ordinary `ScrollView`, `List`, `Form`, or equivalent UIKit-backed content. Those presets keep the normal device width and minimum viewport height while growing vertically. Use an explicit two-axis preset for a spatial canvas that intentionally scrolls in both dimensions. Its bounded capture grows from the normal viewport along both axes. Fixed device frames are for subjects without scrolling content. Preserve production navigation, tab, sheet, search, and toolbar chrome when measurement converges. Snapshot an intentionally bounded or greedy container's shared scrolling child directly. Never add snapshot-only production layout (see `SnapshotConfiguration.Frame.fullContent` and `.fullContent2D`).

### Never double-link a product WhereUI already carries

A target that depends on **WhereUI** must not also list one of WhereUI's own
statically absorbed dependencies (WhereCore, Broadway, LifecycleKitUI,
Periscope, SnapshotKit, Inspector, …) in `extraPackageProducts`. Reach them
transitively. A second copy splits the module's type metadata across the WhereUI
boundary. Every type-keyed lookup (SwiftUI `EnvironmentKey`s,
`UITraitBridgedEnvironmentKey` bridging such as SnapshotKit's
`\.isCapturingSnapshot`, Broadway's
`BTraits`/`BThemes`/`BStylesheets`) silently resolves against the wrong one.

It reproduces only in the full multi-bundle scheme (`./test --all`). It does not reproduce in an
isolated `./test WhereUITests` run. Guard:
`WhereStylesheetTests.resolvesTraitAwareTokensFromTheBroadwayRoot` fails if a
duplicate copy answers.

**Exception:** `WhereUITests` names `LifecycleKit` and `SFSafeSymbols` because
its test sources use those public types directly and Xcode 27 emits those
products as shared package frameworks in this graph. Copying them transitively
through `WhereUI` does not put them on the test bundle's link command. This
links the same generated frameworks rather than another static copy. Re-measure
on a toolchain change.

The guard test is the authority on whether a given duplication is harmful.
Measured symbol-coalescing detail and the correction history: PR #145.

## Deployment

Platforms and minimum OS live in [`Project.swift`](Project.swift). The iOS
targets and the native-macOS **Ledger** app are there. That is why the package declares
both platforms. To get the app onto a connected iPhone without the Xcode UI, use
[`./Where/install`](Where/install). That command is macOS-only. It needs a signing team
configured once via `./ide --team-id` (see
[`Where/AGENTS.md`](Where/AGENTS.md#installing-to-a-device)).
[`./Ledger/install`](Ledger/install) is the equivalent for Ledger. It builds a
Release and installs it to `/Applications` (ad-hoc signed, no team needed).

## Per-module docs

Shared modules live under `Shared/`. Feature modules live under a top-level folder
per feature (`Where/`, `Ledger/`). **Every module is a folder containing `Sources/`,
`Tests/`, `README.md`, and `AGENTS.md`** (apps additionally carry `Resources/`).
A new module must add both docs:

- `README.md` — the human-facing overview: what the module is, install, a quick
  start, the public API, how it works, and any contracts/limitations.
- `AGENTS.md` — the agent-facing module shape, kept **short**: one
  paragraph on what the module is (pointing at the `README.md`), scope &
  dependency rules (what it can and cannot import, where it's wired), the
  architecture/layering rules, any invariants an agent cannot re-derive from
  the code (a line or two each), and a brief testing pointer. It complements
  this root file (which owns build/format/global rules) and must link back to
  it. It does **not** repeat global rules. It does not catalog the module's types. It does not
  restate behavior the source already documents. Agents read code for that.

A module group that spans several targets (`Shared/Broadway/`,
`Shared/Periscope/`) carries the same pair one level up. It covers only what the
group shares. That is the dependency graph between its modules and the invariants no
single module owns.

Keep both **current as the code changes**. Treat stale docs as a bug. When you
change a module's architecture, public API, conventions, or a documented
behavior, update that module's `README.md` and `AGENTS.md` in the *same* change.
If you change a global rule, a target, or the build/test flow, update this root
`AGENTS.md` too. After adding or renaming an `AGENTS.md`, run `./sync-agents`. That produces the generated (gitignored) `CLAUDE.md` next to it.

**Point at the source instead of copying it.** The lists that rot fastest are
the ones the code already owns. That includes every style group on a stylesheet, every
collaborator on a service, and every pinned tool version. Name the one or two worth
learning from. Say where the live list is. An exhaustive copy reads
authoritative long after it stops being true. That is worse than no list.

**Rules state what, not why.** A rule is an imperative sentence. Add at most one
clause of consequence. Do that only when the rule would otherwise look wrong enough to
"fix". Add a pointer to the proof. That is the guard test, the PR number or commit
SHA (squash merges keep PR bodies reachable via `git log`), or a `TODOs.md`
entry. Keep, at one line each: **tripwires** (conditions that invalidate a
rule — "re-measure if X"), **diagnostic signatures** (the literal error text
of a failure mode), and **decision rules**. History narration, mechanism
walkthroughs, and persuasion belong in the PR that proved them. Point to them. Do not
restate.

## Repo-level docs

A few files outside the module pair carry *state* rather than rules:

- **`TODOs.md`** — the durable backlog, and the **only** place an actionable item
  lives. One per area, at that area's root, plus the root
  [`TODOs.md`](TODOs.md), which additionally owns the **item format** and the
  **placement rule**: an item goes in the *lowest* `TODOs.md` spanning every area
  it touches, up to root. Read that file before adding an item. Have a new
  area's file link to it rather than copying the header. File anything
  deferred rather than dropping it (see the
  [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill). A completed
  item moves to "Completed issues". Never delete a completed item.
- **`INBOX.md`** — the root drop-box for raw, unverified human notes. Agents
  **read from it and promote out of it**. They never file new items there
  (agent-found work goes straight to the right `TODOs.md`). The `todo-triage`
  skill drains it. It records a verdict for anything it declines.
- **`FLAKY_TESTS.md`** — generated by `./flaky`. Never hand-edit it. Re-run the
  script.
- **`MODULE_AUDIT.md`** — a dated, **derived** snapshot across every module.
  It lists the source/test inventory, what each module verified clean, and the
  cross-cutting themes behind the current backlog. It carries **no actionable
  items**. Those are in the `TODOs.md` files. Read it to understand shape
  and drift, not as a work list. A weekly automation refreshes it and the
  `TODOs.md` files together through the `todo-triage` skill. It is current to
  its **header date**, not to `HEAD`. Anything that landed since is invisible to
  it. Make sure that you read current source before acting on what it says.

## Conventions

Global rules for all Swift in this repo. A module's own `AGENTS.md` layers its
scope and invariants on top rather than restating these.

### Testing

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- **Test files are 1:1 with implementation files.** A type in `Foo.swift` is
  tested in `FooTests.swift`. When a source file is split (e.g. one detector per
  file), split its tests to match. Do not keep one omnibus file. Shared
  fixtures/helpers live in their own support file (e.g.
  `WhereCoreTestSupport.swift`, `DataIssueDetectorTestSupport.swift`). Do not bundle them
  into a test file. That way a single test clock or input builder is not copy-pasted
  across suites.
- **Wait for conditions, not timing.** Prefer polling a predicate (`waitUntil`,
  `waitFor`, `waitForResolution`) over fixed run-loop counts or `sleep`. Fixed
  delays flake under load.
- **Test-only API is `@_spi(Testing)`, not a production parameter.** Hooks that
  exist for tests or previews — direct store mutation, failure injection, queue
  introspection, a capacity or clock override — are marked `@_spi(Testing)`, in
  `#if DEBUG` when release must not ship them, and imported as
  `@_spi(Testing) import <Module>`. Tests inject small values (a retry-queue
  size of 20) rather than hardcoding the production limit.
- **Test doubles conform to the production protocol.** Model a seam as a
  protocol the real and fake both conform to (`LocationSource` /
  `ScriptedLocationSource`). Never use an enum switch inside a production type
  that branches to fake behavior.
- State machines with many branches (launch runners, lifecycle drives) benefit
  from **seeded fuzz/adversarial tests** that replay failures exactly.

### Types, state, and API design

- Prefer small named structs over tuples for any value with more than
  one field or that escapes a single function. Tuples are fine as
  ad-hoc inline returns. They must not appear in property types,
  collection element types, or public API.
- **Group large flat types into sub-structs and child types.** When a type
  grows a long flat property list (e.g. a config with a cluster of watchdog
  knobs) or a file accretes several behavioral areas, group related properties
  into nested structs and split responsibilities into focused child types.
  Do not let one god-type keep growing.
- Identifiers/keys are `Hashable`. Use a typed enum, or a dedicated struct when
  the identity has structure (Where's `StoreURL` composite keys), or
  `AnyHashable`. Never use raw `String`s. A typed token can't silently typo into
  a new, untracked id. Prefer carrying the *concrete* type where a generic
  can (`LaunchPlan` is generic over its step `ID`). Reach for `AnyHashable`
  only where a generic can't reach (a non-generic environment value, a
  heterogeneous container). Examples: `LaunchStepID`,
  `WherePreferences.Keys`, `StoreURL`.
- **Keep domain values typed through API and helper boundaries.** Accept the
  strongest existing domain type (`Region`, `CalendarDay`, a nested `ID`). Unwrap its `rawValue` / storage key only at the persistence, wire, or system
  boundary that requires the primitive. When no domain type exists and a raw
  scalar is unavoidable, give it a role-specific label (`sampleID`,
  `evidenceID`). Never use an ambiguous `id`.
- **Avoid parameter defaults on Core/store APIs.** Prefer explicit call-site
  arguments so new behavior is not silently opted into. Reserve defaults for
  SwiftUI convenience inits and obvious zero values (`[]`, `.zero`) where
  omission can't change semantics. Test overrides use `@_spi(Testing)` hooks or
  dedicated test factories. Do not use production parameter defaults.
- **`didSet` must skip work when the value is unchanged.** When the stored
  type is `Equatable`, guard `oldValue != newValue` before invalidation,
  logging, or other side effects. Reassigning the same value must be a no-op.
- Don't use a bare `default:` in a `switch` over an enum. Enumerate every case
  so adding one is a compile error, not a silent fall-through. For non-frozen
  enums from other modules (e.g. `UNAuthorizationStatus`), handle known cases
  explicitly plus `@unknown default:`, which still flags newly added cases.
- **Non-obvious types get a brief doc comment** on the type. Detectors,
  geometry/algorithm helpers, and the like state what they do and their key
  invariants.

### Errors and failure

- **Never silently swallow errors.** Core APIs surface failure by `throw`ing
  (or returning a `Result`/typed error). Never absorb it into a benign-looking
  default like `[]`, `nil`, or `false`. Don't discard errors with `try?` or an
  empty `catch {}` that hides the failure. At minimum a `catch` must log
  (a `warning`/`error` on the relevant `WhereLog` scope, ideally a typed
  `LogEvent` carrying a `LogAttachment.error`) *and* leave observable state honest (preserve the
  last good value or move to a `failed` state — not a default that reads as
  success, e.g. an empty list rendering as "all clear"). Callers decide *how* to
  react (rethrow, log + keep state, set a `failed` case). The failure must
  always be observable — in logs, in state, or both.
- **Distinguish user failures from programmer errors.** User/recoverable failures
  must throw (or surface honest UI state) and log. Impossible/misconfigured
  states — corrupt bundled resources, duplicate step IDs, invalid invariants —
  use `precondition` / `assertionFailure` in debug with a minimal safe fallback
  in release. Do not paper over them with silent `??` defaults that read as
  success. "Degraded but handled" recovery belongs at `warning`, not hidden.

### Persistence and wire formats

- **Prefer compiler-synthesized `Codable`.** A hand-written conformance needs a
  load-bearing reason, documented on the conformance itself (see
  `LogJournalEntry`). A simple struct of primitives just uses the synthesized
  one (see `CalendarDay`). Two reasons qualify: **(a) a single-value wire
  shape** — a bare id string or UUID rather than a wrapped object (`Region`
  encodes as `"us-CA"`, not `{"rawValue":…}`). And **(b) a composite identity
  key**, which must be a `store://` URL via Where's `WhereStoreURLCodable`
  (parsed/built with `StoreURL`). Never use an ad-hoc joined `type:value` string.
- **Keep persisted formats rename-safe.** Anything persisted (journals,
  backups, stored preferences) must survive Swift-side renames. Synthesized
  coding of an enum with associated values freezes the *case names* into the
  wire format. Renaming a case silently breaks old data. Do not hand-roll
  a keyed `Codable` to paper over missing fields from an older shape. Reshape
  the data instead (see the no-in-app-migration rule in
  [`Where/WhereCore/AGENTS.md`](Where/WhereCore/AGENTS.md)).

### UI construction

Load the [`building-ui`](.agents/skills/building-ui/SKILL.md) skill when
creating, changing, or reviewing a SwiftUI/UIKit surface. It owns the general
view/model boundary, reuse, binding, Broadway stylesheet, layout,
accessibility, localization, UIKit-bridge, preview, and image-snapshot
procedures. Module `AGENTS.md` files add only their local seams and invariants.

SF Symbols use SFSafeSymbols' `SFSymbol` and `systemSymbol` overloads. Never
spell a symbol as a raw string or construct an unchecked `SFSymbol`. Run
`./sf-symbols --lint`. `WhereShortcuts.swift` is the sole exception because the
App Shortcuts metadata macro requires compile-time string literals.

### Repo hygiene

- Generated `.xcodeproj` and `Derived/` are git-ignored. Never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

### Modeling state

**Make invalid states unrepresentable.** When a set of values is only
meaningful in certain combinations, model it as a *single* type. Usually that is an
`enum` with associated values. Do not use parallel properties that can drift
into nonsensical combinations. Separate stored properties are the exception
to justify, not the reflex.

Worked examples, smallest to largest:

- `YearReportModel.LoadState` (`idle`/`loading`/`loaded`/`failed`) instead of
  `isLoading` + `error` + `data`, and `CalendarContentView`'s single
  `Result<[CalendarMonth], Error>?` — success and failure can't both be set,
  and "not loaded yet" is the `nil`.
- **LifecycleKit's typed `LaunchPlan`** applies it to *wiring*. Steps are
  types whose `Input`/`Output` must chain through the plan's combinators. A
  mis-ordered launch or a consumer without its producer is a compile error.
  Value-producing steps cannot be skipped. A hole in the data flow
  cannot be spelled either (PR #116).
- **`WhereScope`** applies it to *ownership*. The logged-in world is one
  value. That is the open store's services, the preferences driving it, and the log
  store they record into, created whole and never reconfigured. A
  logged-in surface can't read one world's store against another world's
  preferences (PR #150).

Smells that signal a missing type:

- **Several `Bool`s/optionals encoding one state machine** (`isLoading` +
  `loadError` + `value`) — collapse into an `enum` whose cases carry exactly
  the data each state needs.
- **Parallel collections kept in lockstep by index** — use one array of a
  small named struct.
- **Sentinel values standing in for "absent"** (`-1`, `""`, `Date.distantPast`)
  — use `Optional` or a dedicated case.
- **A `kind` tag beside optionals only valid for some kinds** — use an `enum`
  with associated values.
- **Stringly-typed status or flags** (`status == "active"`) — use a typed enum,
  per the identifier/keys convention above.

### Composition: create once, inject down

**A shared resource is created exactly once, at the composition root.** It
reaches every consumer by injection. Use init parameters, explicit arguments,
or a composition hook. Never re-resolve a global. Template: the Where
app's SwiftData store (the launch's `resolve-scope` step is the process's only
open. The resulting `WhereScope` carries it. The App Intents stack derives from
it via the `onServicesReady` hook). Two subsystems independently "opening the
same store" once raced a fresh install into a launch failure.

**Create it when it's needed, not before.** That step runs *behind* the
onboarding gate. An install whose user never onboards opens nothing. A
second world (demo mode) is another scope rather than a flag threaded through
the first. See [`Where/AGENTS.md`](Where/AGENTS.md#scopes-and-the-launch).

- **An alternate boot stack is a runtime implementation, not a mode switch.**
  Select one class-bound application runtime at process initialization and
  forward lifecycle/root calls through it. Never thread a launch-mode enum or
  repeated `if` checks through app code. Where's DEBUG Inspector runtime is the
  reference.
- **No singletons or static get-or-create registries** for anything that can
  be injected. A global invites the double-create race and forces tests to
  share process-wide state. Needing `@Suite(.serialized)` plus a reset hook
  is the smell. Injected dependencies get hermetic per-test instances.
- **When the platform instantiates the consumer** (App Intents, extension
  principal classes), use the platform's DI seam. Keep it a **handoff,
  not a factory**. The root installs what it created
  (`IntentServices.install(_:)`). Early callers await installation
  (`current()` parks, cancellation-aware). The seam never creates the
  resource itself. A "create it myself" fallback quietly reintroduces the
  duplicate the design exists to prevent.
- **Derive, don't re-derive.** A stack built from an existing layer reuses
  what that layer computed (the store, the live attributor, the clock).
  Derivation stays synchronous and non-throwing. It cannot drift from its
  base.
- **Re-fire composition hooks wherever the lifecycle re-creates the thing.**
  `onServicesReady` fires on every session (re)start. Consumers always
  hold the current instance, never the first one.

This is [Modeling state](#modeling-state) applied to ownership and lifetime.
One owner, created in one place, the illegal wirings unrepresentable.

## Generating the Xcode project

Agents must never open Xcode on the user's machine. It steals focus and
disrupts the user's session. Always pass `--no-open` when regenerating:

- `./ide --no-open` instead of `./ide`
- `mise exec -- tuist generate --no-open` instead of `tuist generate`

`tuist test` / `tuist build` are CLI-only and do not open Xcode. No
flag is needed there.

## Running tests

**Use [`./test`](test)** — the only way to run the iOS bundles. Never hand-roll
`tuist test` or `xcodebuild` for them. The one exception is the native-macOS
**Ledger-macOS-Tests** scheme, which `./test` does not know how to run at all.
The [`running-tests`](.agents/skills/running-tests/SKILL.md) skill carries its
invocation. Closing that gap is filed in [`TODOs.md`](TODOs.md). The command
runs the host-side backup-upgrader regression for affected or unit-capable iOS
scopes. Snapshot-only runs skip this regression. Every normal invocation runs
the Bumper Bowling checks first. **Run checks in proportion to risk.** Run
`./swiftformat --lint` when the changed files are in its scope. Run the
narrowest applicable `./test` tier for code, build, tooling, or behavior
changes. Pure documentation or comment-only changes can skip checks that
cannot exercise them. Record skipped checks in the commit or PR validation.
Semantic changes to configuration, scripts, generator inputs, executable
examples, or app-rendered copy are not documentation-only.

Load the [`running-tests`](.agents/skills/running-tests/SKILL.md) skill for
test tiers, snapshot opt-in, why not `tuist test`, and per-checkout simulator
management (`./simulator` resolves a UDID — never pass a device name to
`simctl`).

## Working in this repo

- **Never commit on `main`.** Branch first (`git checkout -b <name>`). Keep
  every commit for one piece of work on that one branch.
- **Run checks in proportion to risk.** Follow [Running tests](#running-tests).
  Never commit a known-red tree. Load the
  [`running-tests`](.agents/skills/running-tests/SKILL.md) skill to choose
  the applicable checks.
- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit completed work eagerly.** Once a coherent change is verified, commit
  it without waiting for a separate request. Never hand back a finished task
  with task-related changes left local, unpushed, or uncommitted. Honor an
  explicit request to keep work uncommitted.

### GitHub

Load the [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill
for PRs, pushes, review feedback, CI, and posting as the user. Always-on: use
`gh`. Open PRs ready-for-review. Mark AI-posted comments. **Plan-driven work
ends with push + PR** before handing back. **Addressing review feedback
includes GitHub replies** on the threads you touch — not code-only fixes.

## Codex worktree specific instructions

[`.codex/environments/environment.toml`](.codex/environments/environment.toml)
owns setup, cleanup, and toolbar actions for Codex-managed worktrees. Keep it
idempotent. Regenerate it through the ChatGPT desktop app's local environment
editor when changing its schema.

- macOS setup runs `./ide --bootstrap --no-open`. Bootstrap trusts the new
  checkout's `.mise.toml`, installs pinned tools, hydrates every Git LFS object
  referenced by the checkout, syncs agent files, and generates without opening
  Xcode.
- Linux setup delegates to [`.cursor/install.sh`](.cursor/install.sh). It has the
  same platform limits documented below.
- Setup first runs `./worktree --check-main`, which refreshes `origin/main` and
  warns without moving `HEAD` when the selected checkout does not contain it.
  An unavailable remote warns without blocking setup.
- The **Update to latest main** action runs `./worktree --update-main`. It only
  fast-forwards a checkout directly behind `origin/main`. It refuses divergent
  history.
- [`.worktreeinclude`](.worktreeinclude) copies only ignored machine-local files
  required by a new managed worktree. `AGENTS.override.md` is copied by Codex
  automatically and must not be listed there.
- Cleanup uses `./simulator --delete`, which deletes only that checkout's
  device. It is safe when no device was created.

## Cursor Cloud specific instructions

Cloud agent VMs run **Linux**, not macOS. This repo targets **iOS 26** with
**Xcode 27+** and **Tuist** (macOS-only). Treat Linux as a partial dev
environment. Formatting and agent sync work on Linux. Builds, tests, and running the
**Where** app require macOS (as in CI on the `xcode-27` runner image).

### Setup is committed, not configured in a dashboard

[`.cursor/environment.json`](.cursor/environment.json) runs
[`.cursor/install.sh`](.cursor/install.sh) after checkout. It installs `mise`,
trusts the config, runs `mise install`, installs `git-lfs`, and points Git at
`.githooks/`. Nothing about a cloud agent's setup lives in a dashboard.

`git-lfs` is not optional on either platform. The `.githooks/` LFS hooks
exit non-zero when the binary is missing. That breaks checkout/merge/push even
for work that never touches snapshots. Both bootstraps install it before
setting `core.hooksPath`. The repo-defined environment follows branches.
It **takes precedence over any dashboard-managed environment**. It must stay
idempotent. Cursor can re-run it against cached state.

### What works on Linux

**Tuist is scoped to `os = ["macos"]`** in `.mise.toml`. Mise skips an
OS-restricted tool entirely rather than failing on it. `mise install` and
every `mise exec --` now succeed here instead of dying on `unsupported env:
linux/amd64`. `mise install` also fires the `postinstall` hook that fetches the
external agent skills. Those skills are gitignored and absent from a bare checkout.

| Check | Command |
|-------|---------|
| Install the pinned tools | `mise install` (Ruby + SwiftFormat; skips Tuist) |
| Format lint (CI `format` job equivalent) | `./swiftformat --lint` |
| Agent file sync | `./sync-agents` or `./sync-agents --install` |
| Git LFS | `apt-get install git-lfs` — required by `.githooks/` |
| Pre-commit hook | works — `mise exec --` no longer pulls in Tuist |

### What does not work on Linux

- **Tuist** — `tuist test`, `tuist build`, and `./ide` (which generates the
  Xcode project)
- iOS Simulator, and running the **Where** app
- **Anything needing a Swift toolchain** — the VM ships none, so `swift run
  bumper` (the architecture lint) and `./xcstrings` (a `#!/usr/bin/swift`
  script) both fail here even though neither needs Xcode. Diagnostic signature
  for the latter: ``mise ERROR "./xcstrings" couldn't exec process: No such file
  or directory``.
- Anything else needing Xcode

These are limits of the **VM**, not of cloud agents generally. A remote-control
session runs iOS. Anything that needs the app actually running — reproducing
a bug, checking a screen, exercising a flow by hand — goes there rather than
being written off as untestable from a cloud agent.

### Full build & test (macOS only)

Matches CI `.github/workflows/ci.yml` — see the
[`running-tests`](.agents/skills/running-tests/SKILL.md) skill for simulator
setup and the full validation recipe.
