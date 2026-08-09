# Stuff – Repository Shape

This file is the repo-wide contract: the build system, the conventions all
Swift here follows, and how to work (branches, commits, PRs, CI). **Every
module also carries its own `AGENTS.md`** covering its scope, layering, and
invariants. Read this file first, then the module's — they deliberately don't
repeat each other, so neither is sufficient alone.

Roughly, this file covers:

- **Building and testing** — [Build system](#build-system),
  [Formatting](#formatting), [Targets](#targets), [Deployment](#deployment),
  [Generating the Xcode project](#generating-the-xcode-project),
  [Running tests](#running-tests),
  and the [Linux/Cloud caveats](#cursor-cloud-specific-instructions).
- **Writing code** — [Per-module docs](#per-module-docs) (and the module layout),
  [Repo-level docs](#repo-level-docs), and [Conventions](#conventions)
  (including [Modeling state](#modeling-state) and
  [Composition](#composition-create-once-inject-down)); load the
  [`building-ui`](.agents/skills/building-ui/SKILL.md) skill for SwiftUI/UIKit
  construction, Broadway styling, accessibility, previews, and snapshots.
- **Working** — [Working in this repo](#working-in-this-repo): commits;
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


Read the exact pinned versions out of those files rather than trusting a copy
in prose — a version transcribed into a doc goes stale silently.

Library targets live in the root [`Package.swift`](Package.swift) (one local
package); apps, app extensions, and test bundles are Tuist targets in
[`Project.swift`](Project.swift) (plus [`Tuist.swift`](Tuist.swift)), which
references the package via `Package.local(path: .relativeToRoot("."))`. The
two manifests are the authoritative target catalog — it is deliberately not
duplicated here.

`./ide` regenerates the Xcode project *and* does the surrounding setup —
external agent skills, `core.hooksPath` — so it's the way to regenerate, not
`tuist generate` alone. Agents must always pass `--no-open` (see [Generating the
Xcode project](#generating-the-xcode-project)). A fresh machine needs `./ide
--bootstrap` first, which installs `mise` and the pinned tools before
generating; plain `./ide` fails fast pointing at it.

The executables in the repo root are the dev scripts — `ide`, `test`,
`swiftformat`, `sync-agents`, `profile`, `icons`, `flaky`, `simulator`,
`worktree`, `xcstrings`, `attribution`, `codex-watchdog`, `tla-check` — and each
takes `--help`. Reach for one rather than
hand-rolling its job: `test` is the only way tests should be run (see [Running
tests](#running-tests)), and `icons`, `attribution`, and `simulator` in particular own state that is
easy to corrupt by hand — `./simulator` owns a per-checkout device (see the
[`running-tests`](.agents/skills/running-tests/SKILL.md) skill).

### Managing app icons

`./icons` is the single command for the Where app's alternate icons (see
`./icons --help`). It keeps both asset catalogs and the picker's
`AppIcons.json` manifest in sync — never hand-edit those or add icon Swift.
Run `./ide --no-open` after adding one.

### Version and build metadata

Bump the Where app's `CFBundleShortVersionString` / `CFBundleVersion`
explicitly in [`Project.swift`](Project.swift) (Settings > About shows them).
How the app was built is stamped by a post-build script
([`Where/Where/Scripts/stamp-build-info.sh`](Where/Where/Scripts/stamp-build-info.sh)):
the commit into `WhereGitSHA` / `WhereGitStatus`, and how the Swift compiler
was invoked into `WhereConfiguration` / `WhereSwiftOptimizationLevel` /
`WhereSwiftCompilationMode`. All of it is read back by `WhereCore.BuildInfo`,
for Settings > About and for the attributes on every Periscope logging session
(the optimization level is what says whether a recorded span duration means
anything). Only the app is stamped. Tripwires: it must stay a **post** script
(before signing seals the bundle), keep `basedOnDependencyAnalysis: false` (or
an unchanged tree ships the previous commit's SHA), needs
`ENABLE_USER_SCRIPT_SANDBOXING` unset (it reads `.git`), and every key it
writes must fall back to `unknown` rather than let `set -u` abort the build
over a build setting Xcode didn't export.

## Formatting

- **SwiftFormat** uses [`.swiftformat`](.swiftformat). Run `./swiftformat` to
  format the tree, or `./swiftformat --lint` to check only (as in CI).
- The pre-commit hook (enabled by `./ide` via `core.hooksPath`) formats staged
  `*.swift` files in place and re-stages them.
- **String Catalogs are stored exactly as Xcode serializes them**, and
  `./xcstrings` (`--lint` in CI) enforces it. A catalog written by anything
  else parses fine but turns the next IDE build into thousands of lines of
  whitespace churn — write catalogs through Xcode or normalize with the
  script afterwards (it touches formatting only, never content).

## Attribution

An app ships an **attribution report** — every third-party work it is built
with, license notices inline. **Re-run `./attribution` and commit the result
whenever you add or bump a package, an agent skill, or a development tool**;
`./attribution --check` fails CI if you forget (offline, sub-second — an app's
own tests can't do this job, since a test bundle can't read `Package.swift`).

- [`Shared/CreditKit`](Shared/CreditKit/AGENTS.md) owns the types and the
  reporting tool and holds **no credits of its own**; each app declares its
  sources in an `attribution-sources.json` and ships the report in its own
  resources (for Where, `Where/Where/Resources/attribution.json`).
- The report derives from `.product(name:package:)` links (pinned by
  `Package.resolved`), `.agents/external-skills.json`, and
  `.agents/development-tools.json`, notices read at the pinned revision — so
  tooling-only packages correctly aren't credited.
- **Kind is derived, not declared**: anything reachable from `shippedFrom`'s
  target closure is a library, any other linked package a development tool —
  linking is not shipping, and a UI must keep the two apart.
- Data-source provenance for bundled geometry stays with its data, in
  [`RegionKit`](Where/RegionKit/AGENTS.md).

## Architecture lint

Bumper Bowling enforces the production Where module graph and selected
source-level invariants. The entry point is
[`BumperBowling.swift`](BumperBowling.swift), repository-owned shapes and rules
live in [`.bumper/Sources`](.bumper/Sources), and
[`.bumper/RULES.md`](.bumper/RULES.md) is the rule catalog.

Run `swift run bumper config .`, `swift run bumper test .`, and
`swift run bumper lint . --timings` after changing a Where dependency,
composition root, or documented concurrency boundary. Keep the relevant
`AGENTS.md`, the executable rule, its catalog entry, and its mutation test in
the same change.

## Agent instructions sync

`AGENTS.md` is the source of truth for AI agent instructions. Cursor reads
`AGENTS.md` natively; Claude Code uses `CLAUDE.md` and `.claude/skills/`.
Generated files (`CLAUDE.md`, `.claude/skills/`) are gitignored and produced
by `./sync-agents`.

- `./sync-agents` — generate `CLAUDE.md` next to each `AGENTS.md` and mirror
  `.agents/skills/` into `.claude/skills/`.
- `./sync-agents --install` — fetch external skills listed in
  `.agents/external-skills.json`. Rarely run by hand: `mise install` calls it
  from a `postinstall` hook, so installing tools also installs skills, on a dev
  machine and a cloud agent alike.
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills to the latest commit.

`.agents/external-skills.json` pins the **external** skills to a commit;
`.agents/skills/.gitignore` excludes those fetched copies, so anything else
under `.agents/skills/` is **repo-owned** and committed. External skills are
also an **attribution** input — after adding or updating one, re-run
`./attribution` (see [Attribution](#attribution)). The same applies to
`.agents/development-tools.json` when pinned verification or other non-SPM
tooling changes.

**`.agents/skills/` is the real home; edit the source, never the
`.claude/skills/` mirror**, and run `./sync-agents` after adding or editing a
skill (Cursor loads both directories, and the winning copy is undocumented —
don't let them drift). A fresh clone carries only the repo-owned skills; the
external ones arrive with the first `mise install`.

A skill carries **procedure** — the steps of an occasional job, **including
rules that apply only while that job runs** (GitHub, running tests, backlog
triage). **Always-on** rules every edit must honor stay in `AGENTS.md` or
`TODOs.md`.

## Targets

- For the current list of library products, apps, extensions, and test
  bundles, read [`Package.swift`](Package.swift) and
  [`Project.swift`](Project.swift); each module's own `README.md` /
  `AGENTS.md` says what it is and how it may be used.
- Add SPM library targets in `Package.swift` and wire apps/tests in `Project.swift` (see existing `unitTests` helper; native-macOS test bundles are declared directly, like `LedgerCoreTests`, since that helper hosts iOS bundles in StuffTestHost). A new module also ships a root `README.md` and `AGENTS.md` — see [Per-module docs](#per-module-docs).
- **CI schemes**: CI runs explicit shared schemes rather than the autogenerated `Stuff-Workspace` scheme. **Stuff-iOS-Tests** covers the iOS bundles, and **Ledger-macOS-Tests** (the Ledger app + `LedgerCoreTests`) runs in its own `test-macos` job — the workspace mixes iOS targets with the native-macOS **Ledger** ones, and no single xcodebuild destination can build both. A new test bundle must be added to the matching scheme in `Project.swift` or CI won't run it.
- **Image snapshots are the exception: one bundle per module, one shared scheme.** Each module owning image references has its own `*SnapshotTests` target over its `SnapshotTests/` folder, all listed in the single shared **StuffSnapshotTests** scheme and its dedicated CI `snapshot` job — slow and LFS-backed, so deliberately **out of** `Stuff-iOS-Tests`. References under any `__Snapshots__/` directory are Git LFS (`.gitattributes`; the CI job checks out with `lfs: true`). Framework halves: `Shared/SnapshotKit` (shippable matrix + previews) and `Shared/SnapshotKitTesting` (test-only pipeline, whose own regression bundle **SnapshotKitTestingTests** pixel-probes without LFS and runs in `Stuff-iOS-Tests`).
- **A new image suite gets a target, not a scheme.** Add the `*SnapshotTests` target, list only `SnapshotKitTesting` in `extraPackageProducts`, and add it to the `StuffSnapshotTests` scheme's build and test lists — never a scheme or CI job of its own. An image bundle links only what its module needs (the Periscope and Inspector suites don't build against WhereUI at all); references follow the sources automatically via `#filePath`.
- **Separate snapshot bundles are safe because each `.xctest` gets its own `StuffTestHost` process** (measured on Xcode 27 — `ProcessInfo.processIdentifier` probes; details in the snapshot-bundle comment in [`Project.swift`](Project.swift)). Each bundle statically embeds its own copy of `SnapshotKitTesting`'s capture state, and two copies in one process would corrupt each other. Tripwire: if a toolchain ever shares one host process across bundles, re-measure before adding another image bundle.
- **Snapshots containing scrolling content use full-content intrinsic height.** Any image snapshot whose rendered subject contains a `ScrollView`, `List`, `Form`, or equivalent UIKit-backed scrolling container uses SnapshotKit's full-content device presets, which keep the normal device viewport as their minimum height and grow to fit taller content; fixed-height device frames are reserved for subjects without scrolling content. Preserve production navigation, tab, sheet, search, and toolbar chrome when intrinsic measurement converges; an intentionally bounded/greedy container instead snapshots its shared scrolling child directly, never snapshot-only production layout (see `SnapshotConfiguration.Frame.fullContent`).

### Never double-link a product WhereUI already carries

A target that depends on **WhereUI** must not also list one of WhereUI's own
statically absorbed dependencies (WhereCore, Broadway, LifecycleKitUI,
Periscope, SnapshotKit, Inspector, …) in `extraPackageProducts` — reach it
transitively. A second copy splits the module's type metadata across the WhereUI
boundary and every type-keyed lookup (SwiftUI `EnvironmentKey`s,
`UITraitBridgedEnvironmentKey` bridging such as SnapshotKit's
`\.isCapturingSnapshot`, Broadway's
`BTraits`/`BThemes`/`BStylesheets`) silently resolves against the wrong one.

It reproduces only in the full multi-bundle scheme (`./test --all`), never in an
isolated `./test WhereUITests` run. Guard:
`WhereStylesheetTests.resolvesTraitAwareTokensFromTheBroadwayRoot` fails if a
duplicate copy answers.

**Exception:** `WhereUITests` names `LifecycleKit` because its test sources use
those public types directly and Xcode 27 beta 4 emits that product as a shared
package framework in this graph; copying it transitively through `WhereUI` does
not put it on the test bundle's link command. This links the same generated
framework rather than another static copy. Re-measure on a toolchain change.

The guard test is the authority on whether a given duplication is harmful —
measured symbol-coalescing detail and the correction history: PR #145.

## Deployment

Platforms and minimum OS live in [`Project.swift`](Project.swift) — the iOS
targets and the native-macOS **Ledger** app, which is why the package declares
both platforms. To get the app onto a connected iPhone without the Xcode UI, use
[`./Where/install`](Where/install) — macOS-only, and it needs a signing team
configured once via `./ide --team-id` (see
[`Where/AGENTS.md`](Where/AGENTS.md#installing-to-a-device)).
[`./Ledger/install`](Ledger/install) is the equivalent for Ledger: it builds a
Release and installs it to `/Applications` (ad-hoc signed, no team needed).

## Per-module docs

Shared modules live under `Shared/`, feature modules under a top-level folder
per feature (`Where/`, `Ledger/`). **Every module is a folder containing `Sources/`,
`Tests/`, `README.md`, and `AGENTS.md`** (apps additionally carry `Resources/`),
and a new module must add both docs:

- `README.md` — the human-facing overview: what the module is, install, a quick
  start, the public API, how it works, and any contracts/limitations.
- `AGENTS.md` — the agent-facing module shape, kept **deliberately short**: one
  paragraph on what the module is (pointing at the `README.md`), scope &
  dependency rules (what it may/may not import, where it's wired), the
  architecture/layering rules, any invariants an agent could not re-derive from
  the code (a line or two each), and a brief testing pointer. It complements
  this root file (which owns build/format/global rules) and should link back to
  it; it does **not** repeat global rules, catalog the module's types, or
  restate behavior the source already documents — agents read code for that.

A module group that spans several targets (`Shared/Broadway/`,
`Shared/Periscope/`) carries the same pair one level up, covering only what the
group shares — the dependency graph between its modules and the invariants no
single module owns.

Keep both **current as the code changes** — treat stale docs as a bug. When you
change a module's architecture, public API, conventions, or a documented
behavior, update that module's `README.md` and `AGENTS.md` in the *same* change;
if you change a global rule, a target, or the build/test flow, update this root
`AGENTS.md` too. After adding or renaming an `AGENTS.md`, run `./sync-agents` so
the generated (gitignored) `CLAUDE.md` is produced next to it.

**Point at the source instead of copying it.** The lists that rot fastest are
the ones the code already owns — every style group on a stylesheet, every
collaborator on a service, a pinned tool version. Name the one or two worth
learning from and say where the live list is. An exhaustive copy reads
authoritative long after it stops being true, which is worse than no list.

**Rules state what, not why.** A rule is an imperative sentence, at most one
clause of consequence (only when the rule would otherwise look wrong enough to
"fix"), and a pointer to the proof — the guard test, the PR number or commit
SHA (squash merges keep PR bodies reachable via `git log`), or a `TODOs.md`
entry. Keep, at one line each: **tripwires** (conditions that invalidate a
rule — "re-measure if X"), **diagnostic signatures** (the literal error text
of a failure mode), and **decision rules**. History narration, mechanism
walkthroughs, and persuasion belong in the PR that proved them — point, don't
restate.

## Repo-level docs

A few files outside the module pair carry *state* rather than rules:

- **`TODOs.md`** — the durable backlog, and the **only** place an actionable item
  lives. One per area, at that area's root, plus the root
  [`TODOs.md`](TODOs.md), which additionally owns the **item format** and the
  **placement rule**: an item goes in the *lowest* `TODOs.md` spanning every area
  it touches, up to root. Read that file before adding an item, and have a new
  area's file link to it rather than copying the header. Anything deliberately
  deferred is filed rather than dropped (see the
  [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill), and a completed
  item moves to "Completed issues" — never deleted.
- **`INBOX.md`** — the root drop-box for raw, unverified human notes. Agents
  **read from it and promote out of it**; they never file new items there
  (agent-found work goes straight to the right `TODOs.md`). The `todo-triage`
  skill drains it, recording a verdict for anything it declines.
- **`FLAKY_TESTS.md`** — generated by `./flaky`. Never hand-edit it; re-run the
  script.
- **`MODULE_AUDIT.md`** — a dated, **derived** snapshot across every module:
  the source/test inventory, what each module verified clean, and the
  cross-cutting themes behind the current backlog. It carries **no actionable
  items** — those are in the `TODOs.md` files — so read it to understand shape
  and drift, not as a work list. A weekly automation refreshes it and the
  `TODOs.md` files together through the `todo-triage` skill, so it is current to
  its **header date**, not to `HEAD`: anything that landed since is invisible to
  it. Verify against current source before acting on what it says.

## Conventions

Global rules for all Swift in this repo. A module's own `AGENTS.md` layers its
scope and invariants on top rather than restating these.

### Testing

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- **Test files are 1:1 with implementation files.** A type in `Foo.swift` is
  tested in `FooTests.swift`; when a source file is split (e.g. one detector per
  file), split its tests to match rather than keeping one omnibus file. Shared
  fixtures/helpers live in their own support file (e.g.
  `WhereCoreTestSupport.swift`, `DataIssueDetectorTestSupport.swift`), not bundled
  into a test file — so a single test clock or input builder isn't copy-pasted
  across suites.
- **Wait for conditions, not timing.** Prefer polling a predicate (`waitUntil`,
  `waitFor`, `waitForResolution`) over fixed run-loop counts or `sleep` — fixed
  delays flake under load.
- **Test-only API is `@_spi(Testing)`, not a production parameter.** Hooks that
  exist for tests or previews — direct store mutation, failure injection, queue
  introspection, a capacity or clock override — are marked `@_spi(Testing)`, in
  `#if DEBUG` when release must not ship them, and imported as
  `@_spi(Testing) import <Module>`. Tests inject small values (a retry-queue
  size of 20) rather than hardcoding the production limit.
- **Test doubles conform to the production protocol.** Model a seam as a
  protocol the real and fake both conform to (`LocationSource` /
  `ScriptedLocationSource`) — never an enum switch inside a production type
  that branches to fake behavior.
- State machines with many branches (launch runners, lifecycle drives) benefit
  from **seeded fuzz/adversarial tests** that replay failures exactly.

### Types, state, and API design

- Prefer small named structs over tuples for any value with more than
  one field or that escapes a single function — tuples are fine as
  ad-hoc inline returns but should not appear in property types,
  collection element types, or public API.
- **Group large flat types into sub-structs and child types.** When a type
  grows a long flat property list (e.g. a config with a cluster of watchdog
  knobs) or a file accretes several behavioral areas, group related properties
  into nested structs and split responsibilities into focused child types —
  don't let one god-type keep growing.
- Identifiers/keys are `Hashable` — a typed enum, or a dedicated struct when
  the identity has structure (Where's `StoreURL` composite keys) — or
  `AnyHashable`, never raw `String`s: a typed token can't silently typo into
  a new, untracked id. Prefer carrying the *concrete* type where a generic
  can (`LaunchPlan` is generic over its step `ID`); reach for `AnyHashable`
  only where a generic can't reach (a non-generic environment value, a
  heterogeneous container). Examples: `LaunchStepID`,
  `WherePreferences.Keys`, `StoreURL`.
- **Keep domain values typed through API and helper boundaries.** Accept the
  strongest existing domain type (`Region`, `CalendarDay`, a nested `ID`) and
  unwrap its `rawValue` / storage key only at the persistence, wire, or system
  boundary that requires the primitive. When no domain type exists and a raw
  scalar is unavoidable, give it a role-specific label (`sampleID`,
  `evidenceID`), never an ambiguous `id`.
- **Avoid parameter defaults on Core/store APIs.** Prefer explicit call-site
  arguments so new behavior isn't silently opted into. Reserve defaults for
  SwiftUI convenience inits and obvious zero values (`[]`, `.zero`) where
  omission can't change semantics. Test overrides use `@_spi(Testing)` hooks or
  dedicated test factories — not production parameter defaults.
- **`didSet` must skip work when the value is unchanged.** When the stored
  type is `Equatable`, guard `oldValue != newValue` before invalidation,
  logging, or other side effects — reassigning the same value should be a no-op.
- Don't use a bare `default:` in a `switch` over an enum — enumerate every case
  so adding one is a compile error, not a silent fall-through. For non-frozen
  enums from other modules (e.g. `UNAuthorizationStatus`), handle known cases
  explicitly plus `@unknown default:`, which still flags newly added cases.
- **Non-obvious types get a brief doc comment** on the type — detectors,
  geometry/algorithm helpers, and the like state what they do and their key
  invariants.

### Errors and failure

- **Never silently swallow errors.** Core APIs surface failure by `throw`ing
  (or returning a `Result`/typed error) — never absorb it into a benign-looking
  default like `[]`, `nil`, or `false`. Don't discard errors with `try?` or an
  empty `catch {}` that hides the failure: at minimum a `catch` must log
  (a `warning`/`error` on the relevant `WhereLog` scope, ideally a typed
  `LogEvent` carrying a `LogAttachment.error`) *and* leave observable state honest (preserve the
  last good value or move to a `failed` state — not a default that reads as
  success, e.g. an empty list rendering as "all clear"). Callers decide *how* to
  react (rethrow, log + keep state, set a `failed` case), but the failure must
  always be observable — in logs, in state, or both.
- **Distinguish user failures from programmer errors.** User/recoverable failures
  must throw (or surface honest UI state) and log. Impossible/misconfigured
  states — corrupt bundled resources, duplicate step IDs, invalid invariants —
  use `precondition` / `assertionFailure` in debug with a minimal safe fallback
  in release; don't paper over them with silent `??` defaults that read as
  success. "Degraded but handled" recovery belongs at `warning`, not hidden.

### Persistence and wire formats

- **Prefer compiler-synthesized `Codable`.** A hand-written conformance needs a
  load-bearing reason, documented on the conformance itself (see
  `LogJournalEntry`); a simple struct of primitives just uses the synthesized
  one (see `CalendarDay`). Two reasons qualify: **(a) a single-value wire
  shape** — a bare id string or UUID rather than a wrapped object (`Region`
  encodes as `"us-CA"`, not `{"rawValue":…}`); and **(b) a composite identity
  key**, which should be a `store://` URL via Where's `WhereStoreURLCodable`
  (parsed/built with `StoreURL`), never an ad-hoc joined `type:value` string.
- **Keep persisted formats rename-safe.** Anything persisted (journals,
  backups, stored preferences) must survive Swift-side renames — synthesized
  coding of an enum with associated values freezes the *case names* into the
  wire format, so renaming a case silently breaks old data. And don't hand-roll
  a keyed `Codable` to paper over missing fields from an older shape; reshape
  the data instead (see the no-in-app-migration rule in
  [`Where/WhereCore/AGENTS.md`](Where/WhereCore/AGENTS.md)).

### UI construction

Load the [`building-ui`](.agents/skills/building-ui/SKILL.md) skill when
creating, changing, or reviewing a SwiftUI/UIKit surface. It owns the general
view/model boundary, reuse, binding, Broadway stylesheet, layout,
accessibility, localization, UIKit-bridge, preview, and image-snapshot
procedures; module `AGENTS.md` files add only their local seams and invariants.

### Repo hygiene

- Generated `.xcodeproj` and `Derived/` are git-ignored; never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

### Modeling state

**Make invalid states unrepresentable.** When a set of values is only
meaningful in certain combinations, model it as a *single* type — usually an
`enum` with associated values — instead of parallel properties that can drift
into nonsensical combinations. Separate stored properties are the exception
to justify, not the reflex.

Worked examples, smallest to largest:

- `YearReportModel.LoadState` (`idle`/`loading`/`loaded`/`failed`) instead of
  `isLoading` + `error` + `data`, and `CalendarContentView`'s single
  `Result<[CalendarMonth], Error>?` — success and failure can't both be set,
  and "not loaded yet" is the `nil`.
- **LifecycleKit's typed `LaunchPlan`** applies it to *wiring*: steps are
  types whose `Input`/`Output` must chain through the plan's combinators, so
  a mis-ordered launch or a consumer without its producer is a compile error
  — and value-producing steps can't be skipped, so a hole in the data flow
  can't be spelled either (PR #116).
- **`WhereScope`** applies it to *ownership*: the logged-in world is one
  value — the open store's services, the preferences driving it, and the log
  store they record into, created whole and never reconfigured — so a
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

**A shared resource is created exactly once, at the composition root, and
reaches every consumer by injection** — init parameters, explicit arguments,
or a composition hook — never by re-resolving a global. Template: the Where
app's SwiftData store (the launch's `resolve-scope` step is the process's only
open; the resulting `WhereScope` carries it; the App Intents stack derives from
it via the `onServicesReady` hook). Two subsystems independently "opening the
same store" once raced a fresh install into a launch failure.

**Create it when it's needed, not before.** That step runs *behind* the
onboarding gate, so an install whose user never onboards opens nothing, and a
second world (demo mode) is another scope rather than a flag threaded through
the first. See [`Where/AGENTS.md`](Where/AGENTS.md#scopes-and-the-launch).

- **An alternate boot stack is a runtime implementation, not a mode switch.**
  Select one class-bound application runtime at process initialization and
  forward lifecycle/root calls through it; never thread a launch-mode enum or
  repeated `if` checks through app code. Where's DEBUG Inspector runtime is the
  reference.
- **No singletons or static get-or-create registries** for anything that can
  be injected — a global invites the double-create race and forces tests to
  share process-wide state. Needing `@Suite(.serialized)` plus a reset hook
  is the smell; injected dependencies get hermetic per-test instances.
- **When the platform instantiates the consumer** (App Intents, extension
  principal classes), use the platform's DI seam, and keep it a **handoff,
  not a factory**: the root installs what it created
  (`IntentServices.install(_:)`), early callers await installation
  (`current()` parks, cancellation-aware), and the seam never creates the
  resource itself — a "create it myself" fallback quietly reintroduces the
  duplicate the design exists to prevent.
- **Derive, don't re-derive.** A stack built from an existing layer reuses
  what that layer computed (the store, the live attributor, the clock) —
  derivation stays synchronous and non-throwing, and can't drift from its
  base.
- **Re-fire composition hooks wherever the lifecycle re-creates the thing.**
  `onServicesReady` fires on every session (re)start, so consumers always
  hold the current instance, never the first one.

This is [Modeling state](#modeling-state) applied to ownership and lifetime:
one owner, created in one place, the illegal wirings unrepresentable.

## Generating the Xcode project

Agents must never open Xcode on the user's machine — it steals focus and
disrupts the user's session. Always pass `--no-open` when regenerating:

- `./ide --no-open` instead of `./ide`
- `mise exec -- tuist generate --no-open` instead of `tuist generate`

`tuist test` / `tuist build` are CLI-only and do not open Xcode, so no
flag is needed there.

## Running tests

**Use [`./test`](test)** — the only way to run tests. Never hand-roll `tuist
test` or `xcodebuild`. It runs the host-side backup-upgrader regression before
selecting an iOS bundle, so tool-only changes remain covered by the same entry
point. **Validate in proportion to risk:** run
`./swiftformat --lint` when the changed files are in its scope, and run the
narrowest applicable `./test` tier for code, build, tooling, or behavior
changes. Pure documentation or comment-only changes may skip checks that
cannot exercise them; record skipped checks in the commit or PR validation.
Semantic changes to configuration, scripts, generator inputs, executable
examples, or app-rendered copy are not documentation-only.

Load the [`running-tests`](.agents/skills/running-tests/SKILL.md) skill for
test tiers, snapshot opt-in, why not `tuist test`, and per-checkout simulator
management (`./simulator` resolves a UDID — never pass a device name to
`simctl`).

## Working in this repo

- **Never commit on `main`.** Branch first (`git checkout -b <name>`) and keep
  every commit for one piece of work on that one branch.
- **Validate in proportion to risk.** Follow [Running tests](#running-tests),
  never commit a known-red tree, and load the
  [`running-tests`](.agents/skills/running-tests/SKILL.md) skill to choose
  the applicable checks.
- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit completed work eagerly.** Once a coherent change is verified, commit
  it without waiting for a separate request; never hand back a finished task
  with task-related changes left local, unpushed, or uncommitted. Honor an
  explicit request to keep work uncommitted.

### GitHub

Load the [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill
for PRs, pushes, review feedback, CI, and posting as the user. Always-on: use
`gh`; open PRs ready-for-review; mark AI-posted comments. **Plan-driven work
ends with push + PR** before handing back. **Addressing review feedback
includes GitHub replies** on the threads you touch — not code-only fixes.

## Codex worktree specific instructions

[`.codex/environments/environment.toml`](.codex/environments/environment.toml)
owns setup, cleanup, and toolbar actions for Codex-managed worktrees. Keep it
idempotent and regenerate it through the ChatGPT desktop app's local environment
editor when changing its schema.

- macOS setup runs `./ide --bootstrap --no-open`; bootstrap trusts the new
  checkout's `.mise.toml`, installs pinned tools, syncs agent files, and
  generates without opening Xcode.
- Linux setup delegates to [`.cursor/install.sh`](.cursor/install.sh), with the
  same platform limits documented below.
- Setup first runs `./worktree --check-main`, which refreshes `origin/main` and
  warns without moving `HEAD` when the selected checkout does not contain it;
  an unavailable remote warns without blocking setup.
- The **Update to latest main** action runs `./worktree --update-main`; it only
  fast-forwards a checkout directly behind `origin/main` and refuses divergent
  history.
- [`.worktreeinclude`](.worktreeinclude) copies only ignored machine-local files
  required by a new managed worktree. `AGENTS.override.md` is copied by Codex
  automatically and must not be listed there.
- Cleanup uses `./simulator --delete`, which deletes only that checkout's
  device and is safe when no device was created.

## Cursor Cloud specific instructions

Cloud agent VMs run **Linux**, not macOS. This repo targets **iOS 26** with
**Xcode 27+** and **Tuist** (macOS-only). Treat Linux as a partial dev
environment: formatting and agent sync work; builds, tests, and running the
**Where** app require macOS (as in CI on the `xcode-27` runner image).

### Setup is committed, not configured in a dashboard

[`.cursor/environment.json`](.cursor/environment.json) runs
[`.cursor/install.sh`](.cursor/install.sh) after checkout: it installs `mise`,
trusts the config, runs `mise install`, installs `git-lfs`, and points Git at
`.githooks/`. Nothing about a cloud agent's setup lives in a dashboard.

`git-lfs` is not optional on either platform — the `.githooks/` LFS hooks
exit non-zero when the binary is missing, breaking checkout/merge/push even
for work that never touches snapshots. Both bootstraps install it before
setting `core.hooksPath`. The repo-defined environment follows branches,
**takes precedence over any dashboard-managed environment**, and must stay
idempotent (Cursor may re-run it against cached state).

### What works on Linux

**Tuist is scoped to `os = ["macos"]`** in `.mise.toml`, and mise skips an
OS-restricted tool entirely rather than failing on it — so `mise install` and
every `mise exec --` now succeed here instead of dying on `unsupported env:
linux/amd64`. `mise install` also fires the `postinstall` hook that fetches the
external agent skills, which are gitignored and so absent from a bare checkout.

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

These are limits of the **VM**, not of cloud agents generally: a remote-control
session runs iOS, so anything that needs the app actually running — reproducing
a bug, checking a screen, exercising a flow by hand — goes there rather than
being written off as untestable from a cloud agent.

### Full build & test (macOS only)

Matches CI `.github/workflows/ci.yml` — see the
[`running-tests`](.agents/skills/running-tests/SKILL.md) skill for simulator
setup and the full validation recipe.
