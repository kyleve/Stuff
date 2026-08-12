# Repo todos

The cross-cutting backlog: items that span more than one area, plus the ones that
belong to the repo itself — dev scripts, CI, the Bumper Bowling rules, repo-level
docs. Anything scoped to a single area lives in that area's own `TODOs.md`.

This file also owns the **item format** and the **placement rule** every
`TODOs.md` in the repo follows; the others point here rather than restating them.

## Format

One item per bullet:

```
- <type>(<Scope>) [<effort>]: <title> — <body, citing file:line>. (<origin> <date|ref>)
```

- **`<type>`** — a conventional-commit type: `feat`, `fix`, `refactor`, `perf`,
  `test`, `docs`, `design`. Two repo additions are also in use and allowed:
  `convention` (the code disagrees with a rule this repo has written down) and
  `localization`. Documented here rather than renamed away, because both were
  already load-bearing in filed items when this list was audited (2026-08-09).
- **`(<Scope>)`** — the module the work lands in (`WhereUI`, `PeriscopeTools`,
  `Bumper`, …). One `TODOs.md` usually covers several modules, so the scope says
  which; omit it in a file that covers exactly one.
- **`[<effort>]`** — `quick-win` (localized, lands in a small PR) or
  `needs-design` (broader refactor, policy choice, or cross-module contract).
  Grep either to pick up work. Omitted under `PX`, where the shape isn't known
  yet.
- **`<title> — <body>`** — what's wrong, then the evidence: the `File.swift:123`
  sites, why it matters, and the suggested fix. Always cite locations; a claim
  with nothing behind it can't be re-verified once the code moves.
- **`(<origin> <date|ref>)`** — where the item came from: `(human 2026-07-24)`,
  `(audit 2026-07-26)`, `(pr#107 review)`. This is the human/agent split, and it
  survives the rewrite an agent gives a promoted inbox note — so you can always
  see which items started as your own. Drop the date when it genuinely isn't
  known, as on items that predate this format: a bare `(human)` or `(agent)` is
  honest, a guessed date isn't.

Buckets carry priority. There is deliberately **no separate severity field**:
two priority axes can disagree, and then neither is trusted.

| Bucket | Meaning |
|--------|---------|
| `PX` | Exploratory — a direction worth thinking about, not yet a task |
| `P0s` | Must do |
| `P1s` | Should do |
| `P2s` | Nice to have |

Two more rules:

- **Nest a dependent task** under the item it depends on.
- **Never delete a completed item.** Move it to "Completed issues" at the bottom
  with a note on how it was closed.

Example:

```
- fix(WhereUI) [quick-win]: `CalendarDay.displayDate` resolves through
  `Calendar.current` (`DateRangeFormatting.swift:33`), so every day label renders
  ~543 years off on a Buddhist-era device. Take an explicit Gregorian calendar and
  thread `report.calendar` from the call sites. (audit 2026-07-26)
	- fix(Bumper) [quick-win]: Widen `where.gregorian_calendar` to the
	  implicit-member form — it filters on `base == "Calendar"`
	  (`.bumper/Sources/WhereProjectRules.swift:121`), so it enforces nothing.
	  (audit 2026-07-26)
```

## Where an item lives

An item goes in the **lowest** `TODOs.md` that spans every area it touches, up to
this one:

| File | Covers |
|------|--------|
| `TODOs.md` (this file) | Cross-area items, dev scripts, CI, Bumper Bowling, repo-level docs |
| `Where/TODOs.md` | The Where app and every module under `Where/` |
| `Shared/<Area>/TODOs.md` | That shared module or module group |

A WhereUI-only item belongs in `Where/TODOs.md`; one that spans WhereUI *and* the
repo-owned Bumper rules belongs here. An area gets its own file the first time it
has an item, and links back here for the format instead of copying it.

## How items get here

Raw, unverified notes go in [`INBOX.md`](INBOX.md) — one bullet, no tags, no
research. The `todo-triage` skill drains it: it verifies each entry against
current source, expands it into the format above, and files it in the right area.
Everything below has already been through that, so write new thoughts in the
inbox rather than here.

# Open issues

## PX (Exploratory)
- feat: Update the deployment target to iOS 27 — this lets us use `HistoryObserver` for CloudKit/SwiftData instead of the notification. Spans every target's minimum OS (`Package.swift`, `Project.swift`), so it sits here rather than in `Where/TODOs.md`. (human)

## P0s (Must do)
- fix(Bumper) [quick-win]: `where.gregorian_calendar` matches only an explicit `Calendar` base, so it enforces nothing. It filters `MemberAccessExprSyntax` on `base?.trimmedDescription == "Calendar"` (`.bumper/Sources/WhereProjectRules.swift:122-124`, rule at `:116-135`, `severity: .error` at `:118`), which catches a spelled-out `Calendar.current` but not the implicit-member form (`calendar: Calendar = .current`, `startOfDay(in: .current)`) — and after the Gregorian call-site pass (`fe99dde`) the implicit form is the only one left in the tree: **12 sites today**, four of them shipped production paths and eight in DEBUG snapshot/preview fixtures (enumerated in the `CalendarDay.displayDate` P1 in [`Where/TODOs.md`](Where/TODOs.md)). CI hard-gates `bumper lint` (`.github/workflows/ci.yml:67-68`) and is green, which confirms the rule reports none of them. **Why it has survived three audits:** the rule's own mutation test only ever feeds it a spelled-out `Calendar.current` (`.bumper/Tests/WhereProjectRulesTests.swift:164-171`), so the test passes for the same reason the rule fails — fix both together, and add an implicit-member case to the test first. Also match a no-base `MemberAccessExprSyntax` whose contextual type is `Calendar`, or add a lexical `.current` check scoped to calendar parameters and arguments. A rule that reads as enforced but enforces nothing is worse than a documented convention, because it stops anyone from looking. (audit 2026-07-26; re-verified 2026-08-09)

## P1s (Should do)
- docs [quick-win]: Delete the temporary `kve-stuff` CI benchmark organization after its paid plan ends — the [`Stuff-CI-Benchmark`](https://github.com/kve-stuff/Stuff-CI-Benchmark) repository exists only to retain the runner experiment, and GitHub Team is scheduled to downgrade to Free on September 9, 2026. After the downgrade, preserve [the final benchmark report](https://github.com/kve-stuff/Stuff-CI-Benchmark/pull/3) in this repo if it is still useful, verify that the organization has no billable usage or installed integrations, then delete the organization. (human 2026-08-09)
- test(Bumper) [quick-win]: Two of the four architecture-graph assertions have no mutation test. `.bumper/Tests/` covers `component_boundary` (`WhereArchitectureTests.swift:28-46`) and `forbidden_import` (`:49-67`, `:70-91`), and each of the ten source-level `where.*` rules has one in `WhereProjectRulesTests.swift` — but nothing exercises `duplicate_ownership` or `declared_dependency_cycle`, so neither has been shown to fail on a tree that violates it. That is a gap against this repo's own discipline, which requires the rule, its catalog entry, and its mutation test to land together (root [`AGENTS.md`](AGENTS.md#architecture-lint)). Note `.bumper/RULES.md:40-41` is *not* wrong here — its "the mutation tests prove…" sentence is scoped to imports, which are genuinely covered — so this is missing coverage, not a false claim. Add a mutation per rule: assign one source path to two components, and declare a cycle between two Where layers. An untested assertion is indistinguishable from one that silently passes everything, which is exactly how `where.gregorian_calendar` came to enforce nothing. (audit 2026-08-09)
- docs [quick-win]: Two feature-group folders are missing the doc pair the root [`AGENTS.md`](AGENTS.md#per-module-docs) requires of a module group spanning several targets. `Where/` has an `AGENTS.md` but **no `README.md`** — so the app with 11 modules and by far the most surface has no human-facing entry point at its root, while `Shared/Broadway/` and `Shared/Periscope/` both carry the pair. `Ledger/` has **neither**, though it groups the app target and `LedgerCore` (each of which has its own complete pair). Write the group-level `README.md` for `Where/` and both files for `Ledger/`, covering only what the group shares — the module graph and the invariants no single module owns — per the group rule, and without restating what the leaf docs already say. (audit 2026-08-09)

## P2s (Nice to have)
- perf(CI) [needs-design]: Re-evaluate caching Git LFS snapshot objects without
  fighting CircleCI's checkout hydration — the built-in checkout already
  downloaded all 377 current objects (358.58 MiB) before
  [`.circleci/config.yml:20-32`](.circleci/config.yml), while PR #245's first
  cache attempt encountered a cold miss and then made `git lfs prune
  --no-verify-remote` fail because the blobless clone lacked historical objects
  named by recent refs (`Prune error: missing object`). Before retrying, prove
  that checkout can skip smudging into a stable cache path, avoid pruning
  incomplete history, and benchmark Circle cache restore against the native
  checkout; land it only if both cold and warm snapshot jobs stay correct and
  get faster. (pr#245 review)
- feat(Scripts) [needs-design]: Teach [`test`](test) the native-macOS tier, or stop stating that it is the only entry point. The root [`AGENTS.md`](AGENTS.md#running-tests) says "**Use `./test`** — the only way to run tests. Never hand-roll `tuist test` or `xcodebuild`", but `./test` contains no reference to Ledger or a macOS destination anywhere in its 869 lines, so `LedgerCoreTests` — a real bundle with its own CI job — simply cannot be run through it. The [`running-tests`](.agents/skills/running-tests/SKILL.md) skill already documents the exception with the raw command (`SKILL.md:114-116`, `tuist test Ledger-macOS-Tests -- -destination 'platform=macOS'`), and `LedgerCore/AGENTS.md` gives its own variant, so the truth lives in two places while the always-applied root rule contradicts both. An agent that reads only the root file — which is the one guaranteed to be loaded — concludes Ledger's tests go through `./test`, and nothing tells it otherwise until the command fails. Either add a macOS tier to `./test` (it already resolves destinations through [`simulator`](simulator) for iOS, and a macOS run needs no device at all, so this is the smaller change than it looks) or make the root rule name the carve-out explicitly. **The doc half is done** — root `AGENTS.md` now points at the skill for the macOS bundle — so what remains is deciding whether the script should absorb the tier. (audit 2026-08-09)
- refactor(Scripts) [needs-design]: The root dev scripts want an overhaul — there are **15** now (re-counted 2026-08-12; `ten` when this was filed, with `tla-check`, `codex-watchdog`, and `circleci-artifacts` added since), and three of them duplicate the same xcodebuild plumbing. `./test`, [`profile`](profile), and [`flaky`](flaky) each resolve a destination, invoke `xcodebuild`, and parse an `.xcresult` with their own inline Python. Deliberately **not** consolidated when `./test` landed: the three genuinely want different things from a run (`profile` avoids formatters for timing fidelity and passes `-showBuildTimingSummary`; `flaky` needs `-test-iterations` and per-test re-runs; only `./test` wants a progress filter), so folding them into `./test` would bend a front door into a library, and extracting a shared helper introduces a sourced-library pattern none of the scripts use today. The duplication that actually caused harm was the *documented* invocation drifting between the docs, CI, and agent sessions, and `./test` now owns that; `profile` and `flaky` are report-only tools nobody copies commands from. Worth revisiting as part of a broader pass over the scripts rather than on its own, at which point the shared pieces are: destination resolution (already funnelled through [`simulator`](simulator)), the `xcresulttool get test-results tests` walk, and the `==>` / `error:` output conventions. (human 2026-07-28)
- refactor(Scripts) [needs-design]: Evaluate `tuist xcodebuild test-without-building` as a way to retire `./test`'s affected-bundle parser. `affected_bundles` ([`test`](test):196-359, in an 869-line script) is ~164 lines of Python that regex-parses `Project.swift` to work out which bundles a diff touches, and it is the most fragile thing in the script: it infers declaration boundaries from indent level (its own comment explains why the two obvious alternatives silently under-select, and `verify_parse` exits non-zero rather than degrade to "no bundle covers these changes"). It is also **local convenience only** — CI runs `--all` / `--snapshots`, so nothing in the pipeline depends on it. Tuist 4.200.5 ships `tuist xcodebuild test-without-building`, advertised as adding selective testing to an otherwise plain xcodebuild invocation, which is the only known way to get both that and the raw output `./test` needs. **Verify the output first:** if it pipes through xcbeautify like `tuist test` does, it is a non-starter for the two reasons in `./test`'s header comment, and the parser stays. Also confirm what it does with an empty hash cache on a fresh checkout, since that is the case CI is in. (agent 2026-07-28)
- refactor [needs-design]: Vendor the local package through Tuist instead of Xcode's SPM integration, so package products become real Tuist targets. Today [`Project.swift`](Project.swift) uses `Package.local(path: .relativeToRoot("."))`, which emits an `XCLocalSwiftPackageReference` and hands the whole package to **Xcode's** SPM integration: every product links statically into each consumer, Tuist never sees the targets, and `PackageSettings` is inert. The alternative — the arrangement Tuist actually intends, and which other projects using it don't hit these duplication problems with — declares the local package as a dependency of a `Tuist/Package.swift` and consumes products with `.external(name:)`, so Tuist generates the targets and their product types and settings become ours to set. What it would buy: `PackageSettings` (per-product `.framework`/`.staticFramework`, per-target build settings), `Config(generationOptions: .options(enforceExplicitDependencies: true))` to catch the transitive-import looseness the test bundles lean on, resource bundles that stop being copied into every consumer (the full GeoJSON set is currently embedded per bundle), and retirement of the double-linking rule as a discipline. **Prototyped — blocked on a repo-layout prerequisite, not on the mechanism.** (spike 2026-07-26)
	- The blocker: Tuist cannot vendor a local package whose directory *is* the project directory. `tuist generate` dies with `Fatal error: Duplicate values for key: '/Users/kve/Development/Stuff4'`. Confirmed this is specifically the root collision rather than something else about this repo: pointing `Tuist/Package.swift` at a throwaway probe package elsewhere vendored fine and advanced to graph construction (failing only with `` `LifecycleKit` is not a valid configured external dependency ``, the correct next error). Projects that use this arrangement successfully avoid the collision purely by layout — the package at the repo root with the Tuist manifests in a subdirectory — where Stuff has both at the root.
	- Only one escape route exists. Moving the *package* into a subdirectory is not possible: SwiftPM rejects target paths outside the package root (`target 'Outside' in package 'pkg' is outside the package root`, verified with a minimal repro), and every target here points at `Where/…` / `Shared/…`. So the **Tuist manifests** would have to move into a subdirectory, rewriting every source glob in `Project.swift` plus `./ide`, `profile`, `.github/workflows/ci.yml`, and the docs. The vendored mode also adds a `tuist install` step before generate.
	- The app can stay static. `PackageSettings(baseProductType: .staticFramework)` keeps every product statically linked exactly as today, with `productTypes` opting in only the products that need one shared copy per process — so this does not force dynamic frameworks into the Where app. Worth stating because "move to Tuist-vendored packages" reads as "ship ten dylibs", and it doesn't have to.
- refactor(SnapshotKitTesting) [needs-design]: Dynamically link `SnapshotKitTesting` so its capture state is one copy per *process image* rather than one per bundle. **Spiked; it works, was deliberately not landed, and its original motivation has since evaporated** — kept only so a future attempt starts from the findings rather than the dead ends. The spike existed to make a second image-snapshot bundle safe; measuring afterwards showed xcodebuild already gives each `.xctest` its own `StuffTestHost` process (different `ProcessInfo.processIdentifier` from two bundles in one scheme, on both filtered and full runs), so separate bundles were never unsafe and the repo now ships one per module. Only revisit this if bundles ever start sharing a host process — which is the assumption recorded in [`AGENTS.md`](AGENTS.md#targets) and in `SnapshotKitTesting/AGENTS.md`. (spike 2026-07-26)
	- What works: `.library(name: "SnapshotKitTesting", type: .dynamic, …)` in [`Package.swift`](Package.swift) produces a real framework; the `.xctest` then links `@rpath/SnapshotKitTesting.framework` and its private `_swizzleDepth` count drops from one-per-bundle to **zero**. The whole goal, in one line.
	- The blocker: a dynamic product that *statically absorbs* a resource-bearing dependency orphans that dependency's resources. `AccessibilitySnapshotParser`'s code moves into the framework while its `.bundle` stays in the `.xctest`, and SwiftPM's generated accessor searches only `Bundle.main.resourceURL`, `Bundle(for: BundleFinder.self).resourceURL`, `Bundle.main.bundleURL` — so `Bundle.module` hits its `fatalError` and **every VoiceOver-annotated capture traps** (`AccessibilitySnapshotBaseView.parseAccessibility()` → `StringLocalization.preferredBundle(for:)`). Verified fix: copy the resource bundles into `PackageFrameworks/SnapshotKitTesting.framework/`, after which the accessibility suites pass with no pixel drift. Automating it needs a build phase against a framework Xcode's SPM integration generates — the same `Bundle.module` placement fragility the StuffTestHost WhereCore embed was, which is the main argument against landing it.
	- Dead end: Tuist's `PackageSettings(productTypes:)` does nothing here. The local package is wired as an `XCLocalSwiftPackageReference` and resolved by Xcode's own SPM integration, so Tuist's product-type machinery never applies — only SwiftPM's `type:`. Relatedly, `type: .dynamic` takes effect only for a product an Xcode target consumes *as a product*: WhereUI depends on the SnapshotKit *target*, so SnapshotKit stayed static despite the annotation.
	- Trap: **a shared DerivedData reports false negatives here.** Two separate runs reported "no frameworks produced" from an incremental build that had not re-resolved the package graph. Spike this into a fresh `-derivedDataPath` or it will lie to you.
# Completed issues

## P0s (Must do)
- docs(Bumper) [quick-win]: Correct `.bumper/RULES.md:101` and `:143`, which claimed three calendar violations and some preview-coverage violations were "left visible during this bootstrap". Neither existed — the lint gate was green, and `52f0136` closed the preview ones. Closed by deleting both paragraphs after re-confirming a clean `swift run bumper lint .` ("No architecture violations found") and a green `swift run bumper test .`; re-add the calendar paragraph only if the widened rule genuinely finds drift. (audit 2026-07-26, closed 2026-07-27)

## P1s (Should do)
- test(CreditKit) [needs-design]: The attribution drift guard didn't detect a stale report, so the app could ship notices that don't govern the code in it. **Closed by `./attribution --check`**, a network-free mode that re-derives the expected report from `Package.swift`, `Package.resolved`, and the skills manifest and diffs it against the committed one, gated in CI beside the other lints (`.github/workflows/ci.yml`). The literal name lists in `AppAttributionTests` are gone — a test bundle can't read the manifests, so all it could compare against was a literal — and that suite now asserts only what the shipping bundle can answer. **As originally filed this item was wrong on a detail worth recording:** it claimed the old guard caught an added dependency but not a bumped one. It caught neither. Comparing the report to a hardcoded list means a dependency added without regenerating leaves report and list still agreeing, which is exactly what happened — the guard passed on a report missing the two snapshot packages that merging `main` had added. (pr#140 review, closed 2026-07-26)

## P2s (Nice to have)
- refactor(StuffTestHost) [quick-win]: The scene configuration name was spelled
  twice in `AppDelegate` and `Project.swift`, so the two could drift silently.
  Closed by having `AppDelegate` modify and return the session's plist-derived
  configuration, leaving the Tuist manifest as the sole owner of the name.
  (audit 2026-07-26, closed 2026-08-02)
- feat(PeriscopeCore) [needs-design]: A `LogSession` couldn't name the build it came from, so every developer build read `v1.0 (1)` and weeks-old logs couldn't be tied to the code that produced them. **Closed by the attributes seam** the item asked for: `LogSession.attributes`, a `[LogSessionAttributeKey: String]` the host app fills at bootstrap, keeping Periscope below the Where modules (it never reads a build stamp itself). Where's `stamp-build-info.sh` now writes `WhereConfiguration` / `WhereSwiftOptimizationLevel` / `WhereSwiftCompilationMode` beside the commit keys, `BuildInfo.logSessionAttributes` maps what the bundle can actually name (an unstamped bundle contributes nothing rather than a build called `unknown`), and `WhereLaunch.bootstrapLogging` passes them to `LogSession.current(attributes:)`. **Scope grew past the original ask on purpose:** the optimization level, not the commit, is what decides whether a recorded span duration says anything about the shipping app — and the configuration alone can't answer it, since a `Debug` configuration can be compiled `-O`. So the viewer's session picker shows commit + level, and `SpanHistoryView` gained a build scope so a p95 can't silently pool an `-Onone` build with an `-O` one. (agent 2026-07-26, closed 2026-07-28)
- perf(StuffTestHost) [needs-design]: The WhereCore-always-embedded build trade-off in the shared test host — every bundle in the scheme paid for it, so the item was whether to keep documenting it or split the host. (Resolved by deleting it instead: on Xcode 27 the dependency is simply unnecessary. Each `.xctest` now carries its own copies of the resource bundles for the code it links, so SwiftPM's `Bundle.module` resolves via `Bundle(for:)` — the test bundle — and never falls back to `Bundle.main`, which was the only thing the host embed provided. Verified by removing it and running both `Stuff-iOS-Tests` and the image-snapshot scheme green, with the built host confirmed to hold no WhereCore symbols and no resource bundles. It also removes duplicate payload — the full GeoJSON set was embedded in both the host and every bundle that needed it. Independently, one of the two canaries the old note cited as proof, `WhereUITests.StringsTests`, no longer existed: it went with the String Catalog symbol migration.)
	- **Correction (2026-07-29):** "on Xcode 27" was really "on Xcode 27 *beta 3*". Beta 4 (27A5228h, rolled out to CI's `xcode-27` image on 2026-07-28) broke the arrangement — not by dropping the per-`.xctest` bundle copies (those still happen), but by deduping a statically-absorbed product's *code* into one image (WhereCore's classes now live only inside `WhereUI.framework`), so `Bundle(for: BundleFinder.self)` resolves to a framework that doesn't carry the bundle and the accessor's fatalError kills the host (CI run 30484782772, `RegionCatalog.shared` during trait scoping). Neither old remedy was available: pinning CI to beta 3 is impossible (the `xcode-27` image line ships exactly one Xcode, and the new image replaced beta 3's bits), and re-embedding WhereCore in the host fails the *build* under beta 4 — a package product consumed by both the host and the bundles loses its String Catalog generate-symbols step (verified with WhereCore directly and via WhereUI/LifecycleKitUI). The fix is the accessors' own escape hatch: `PACKAGE_RESOURCE_BUNDLE_PATH` pointed at the built-products directory, set by every test scheme and delivered concretely by `./test` (xcodebuild doesn't expand scheme-env macros). See `packageResourceEnvironment` in `Project.swift` for how to retire it.
- test(WhereUI) [needs-design]: broken-snapshots — two snapshot suites pinned views WhereUI doesn't own (`PeriscopeViewer` and `SwiftDataInspector`), flagged `[Fix later]` on PR #101. (Resolved: both suites, and their reference images, now live under the module they cover. The prerequisite this item assumed — a snapshot *bundle* per module, each with its own scheme and CI job — turned out to be the wrong shape and was **not** built. Per-module bundles are actively unsafe: each `.xctest` statically embeds what it links, so a second one would carry a second copy of `SnapshotKitTesting`, whose "process-global" capture state is module-global and therefore per copy — two copies co-loaded into one `StuffTestHost` would flip the safe-area swizzle's parity against each other and neither capture lock would see the other's captures (verified with `nm`: each built bundle defines its own private `_swizzleDepth`). And per-module bundles were never needed for ownership: swift-snapshot-testing derives the `__Snapshots__` directory from the calling file's `#filePath`, so a suite records beside itself wherever it lives. So the single bundle was renamed `WhereUISnapshotTests` → `StuffSnapshotTests` and gained a `sources` directory per module, keeping one scheme and one CI job. The one-bundle rule is now recorded in the root `AGENTS.md` "Targets" section and in `SnapshotKitTesting/AGENTS.md`. Moving `PeriscopeViewer` changed no pixels — it seeds its own `periscopeBroadwayRoot()`, so the `whereBroadwayRoot()` wrapper the old suite credited for "app styling" was contributing nothing; `SwiftDataInspector` did re-record, since it moved off Where's store onto a local fixture schema.)
	- **Correction (2026-07-26, same day):** the "per-module bundles are actively unsafe" reasoning above was wrong, and the single-bundle shape it produced has been undone. It assumed several `.xctest` bundles in one scheme load into one `StuffTestHost` process — inherited from the root `AGENTS.md` double-linking note rather than measured. They don't: probing `ProcessInfo.processIdentifier` from two bundles in one scheme reports different PIDs, on both a filtered and a full unfiltered run (Xcode 27). Each bundle gets its own host process, so its own copy of `SnapshotKitTesting`'s capture state is genuinely process-wide and cannot collide with another bundle's. The repo now has one image bundle per module (`WhereUISnapshotTests`, `PeriscopeToolsSnapshotTests`, `SwiftDataInspectorSnapshotTests`) gathered into the one `StuffSnapshotTests` scheme — which also lets the Periscope and SwiftDataInspector suites stop linking WhereUI. Left here rather than edited away because the wrong reasoning is the useful part: two separate load-bearing claims in these docs turned out to be inherited rather than verified.
