# Targets and distribution

## Targets

- For the current list of library products, apps, extensions, and test
  bundles, read [`Package.swift`](../../Package.swift) and
  [`Project.swift`](../../Project.swift). Each module's own `README.md` /
  `AGENTS.md` says what it is and how it can be used.
- Add SPM library targets in `Package.swift` and wire apps/tests in `Project.swift` (see the existing `unitTests` helper, which hosts iOS bundles in StuffTestHost). A new module also ships a root `README.md` and `AGENTS.md` — see [Per-module docs](repository-docs.md#per-module-docs).
- **Ordinary iOS tests** run through two shared schemes. `Stuff-iOS-Tests` retains individual module bundles for focused runs. `Stuff-iOS-FullTests` runs the complete suite and compiles the selected libraries into a single serial test host. Add each ordinary bundle to the logical target list in `Project.swift`. Group a library only after verifying shared-state cleanup, resource lookup and module-level reporting. GitHub runs host-side tests through `./test --skip-architecture PeriscopeMacrosTests`.
- **Documentation-only PRs**: Both CI providers use [`Tools/ci_changes.py`](../../Tools/ci_changes.py) to classify the complete PR diff. Eligible Markdown changes skip expensive jobs while preserving required check names. A non-forced merge can reuse full PR validation on the same Git tree, or reuse the lightweight documentation checks when the pushed range also qualifies. Manual full runs execute all checks. See [the CI selection contract](../../Tools/AGENTS.md#ci-selection) and [tooling overview](../../Tools/README.md#documentation-only-ci).
- Bundle runtime test fixtures through `unitTests(resources:)` in `Project.swift`. Resolve them from the test bundle so CI workers need no source checkout.
- **CircleCI build handoff**: CircleCI builds both iOS test schemes sequentially on one `m4pro.large` builder. The unit worker and parallel snapshot workers attach its products and run without compilation. Each worker validates the build manifest before it starts a simulator. The [daily CircleCI schedule](../../Tools/README.md#daily-where-audience-builds) owns the **Where Beta** and **Where App Store** compile checks. `./snapshot-shards` assigns suites to the planned shards and reserves the last worker for intake. A new suite runs on the intake shard until rebalancing adds it to the plan. Each active snapshot worker must execute exactly its assigned suites. The default-off `manual_full_gate` pipeline parameter runs the CircleCI gate on an explicitly selected stacked branch tip. Pair it with a manual GitHub `CI` run on the same tip for helper, host, and architecture checks. Ordinary pushes and pull requests do not set `manual_full_gate`.
- **Image snapshots are the exception: one bundle per module, one shared scheme.** Each module owning image references has its own `*SnapshotTests` target over its `SnapshotTests/` folder. All are listed in the single shared **StuffSnapshotTests** scheme and its dedicated CI `snapshot` job. Snapshots are slow and LFS-backed. They run separately from ordinary iOS tests. References under any `__Snapshots__/` directory are Git LFS (`.gitattributes`. The CI job hydrates them explicitly). Framework halves: `Shared/SnapshotKit` (shippable matrix + previews) and `Shared/SnapshotKitTesting` (test-only pipeline, whose own regression bundle **SnapshotKitTestingTests** pixel-probes without LFS and runs in the ordinary iOS schemes).
- **A new image suite gets a target, not a scheme.** Add the `*SnapshotTests` target. List only `SnapshotKitTesting` in `extraPackageProducts`. Add it to the `StuffSnapshotTests` scheme's build and test lists. Never add a scheme or CI job of its own. An image bundle links only what its module needs (the Periscope and Inspector suites don't build against WhereUI at all). References follow the sources automatically via `#filePath`.
- **Generated websites use the same snapshot scheme.** `ToolsSnapshotTests` renders the install site's production Astro HTML in hosted WebKit through `SnapshotKitTesting`. Local builds run the fixture generator with installed site dependencies. The iOS test builder copies a verified fixture into the same test bundle; see [`Tools/AGENTS.md`](../../Tools/AGENTS.md#install-site-snapshots).
- **Separate snapshot bundles are safe because each `.xctest` gets its own `StuffTestHost` process** (measured on Xcode 27 — `ProcessInfo.processIdentifier` probes. Details in the snapshot-bundle comment in [`Project.swift`](../../Project.swift)). Each bundle statically embeds its own copy of `SnapshotKitTesting`'s capture state. Two copies in one process corrupt each other. Tripwire: if a toolchain ever shares one host process across bundles, re-measure before adding another image bundle.
- **Snapshots containing scrolling content use full-content sizing.** Use SnapshotKit's full-content device presets for ordinary `ScrollView`, `List`, `Form`, or equivalent UIKit-backed content. Those presets keep the normal device width and minimum viewport height while growing vertically. Use an explicit two-axis preset for a spatial canvas that intentionally scrolls in both dimensions. Its bounded capture grows from the normal viewport along both axes. Fixed device frames are for subjects without scrolling content. The explicit `Frame.viewport` API also covers bounded adaptive shells. Pair each shell with full-content captures of its scrolling panes; viewport coverage proves composition and chrome only. Preserve production navigation, tab, sheet, search, and toolbar chrome when measurement converges. Snapshot an intentionally bounded or greedy container's shared scrolling child directly. Never add snapshot-only production layout (see `SnapshotConfiguration.Frame.fullContent` and `.fullContent2D`).

### Never double-link a product WhereUI already carries

A target that depends on **WhereUI** must not also list one of WhereUI's own
statically absorbed dependencies (WhereCore, Broadway, LifecycleKitUI,
Periscope, SnapshotKit, Inspector, …) in `extraPackageProducts`. Reach them
transitively. A second copy splits the module's type metadata across the WhereUI
boundary. Every type-keyed lookup (SwiftUI `EnvironmentKey`s,
`UITraitBridgedEnvironmentKey` bridging such as SnapshotKit's
`\.isCapturingSnapshot`, Broadway's
`BTraits`/`BThemes`/`BStylesheets`) silently resolves against the wrong one.

It reproduces only in the full ordinary scheme (`./test --all`). It does not reproduce in an
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

App platforms and minimum OS live in [`Project.swift`](../../Project.swift).
The package also supports macOS for host-side tools and tests. To get the app onto a connected iPhone without the Xcode UI, use
[`./Where/install`](../../Where/install). That command is macOS-only. It needs a signing team
configured once via `./ide --team-id` (see
[`Where/AGENTS.md`](../../Where/Guidance/installation.md#installing-to-a-device)). Its `--dry-run`
resolves the exact physical device without generating, building, installing,
or launching.
For remote installs, [`./Where/archive`](../../Where/archive) exports a signed Where
Development IPA. The opt-in [GitHub distribution workflow](../../.github/workflows/installer-distribution.yml)
publishes enabled registered apps on `main` and PRs labeled `installable` through a controller from `main`.
The app registry selects identities; the signing registry selects schemes, products, and targets.
[`InstallerKit`](../../Shared/InstallerKit/README.md) owns the reusable update engine.
[`InstallerKitUI`](../../Shared/InstallerKitUI/README.md) owns its native update page.
Apps inject their model, branding, and optional section modifiers for host search.
Configured local Development builds can browse remote builds. Reinstall through Xcode or the app's local installer to return to Local.
All registered iOS apps share one catalog and install site. Main builds appear on
the homepage, and each app has its own PR pages. The site deploys from `main` independently of signed builds.
Read [the installer guide](../../Tools/InstallerKit/README.md)
when adding an app. `./signing setup --app <id>` prepares signing and enables a registered app after its configuration merges.
Add `--pr <number>` to prepare its PR source and request publication. Use `--dry-run` to preview setup.
`InstallerKitTests` and `InstallerKitUITests` run in `Stuff-iOS-Tests`.
`InstallerKitUISnapshotTests` runs in `StuffSnapshotTests`. Read
[`Where/DISTRIBUTION.md`](../../Where/DISTRIBUTION.md) for signing and account setup;
[`Where/AGENTS.md`](../../Where/Guidance/installation.md#installing-to-a-device) owns its invariants.
