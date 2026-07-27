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
  `test`, `docs`, `design`.
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
- fix(Bumper) [quick-win]: `where.gregorian_calendar` matches only an explicit `Calendar` base, so it enforces nothing. It filters `MemberAccessExprSyntax` on `base?.trimmedDescription == "Calendar"` (`.bumper/Sources/WhereProjectRules.swift:121`), which catches a spelled-out `Calendar.current` but not the implicit-member form (`calendar: Calendar = .current`, `startOfDay(in: .current)`) — and after the Gregorian call-site pass (`fe99dde`) the implicit form is the only one left in the tree. CI hard-gates `bumper lint` at `severity: .error` and is green, which confirms it: the rule reports nothing while production sites drift. Also match a no-base `MemberAccessExprSyntax` whose contextual type is `Calendar`, or add a lexical `.current` check scoped to calendar parameters and arguments. A rule that reads as enforced but enforces nothing is worse than a documented convention, because it stops anyone from looking. Pairs with the `CalendarDay.displayDate` P1 in [`Where/TODOs.md`](Where/TODOs.md). (audit 2026-07-26)
	- docs(Bumper) [quick-win]: Correct `.bumper/RULES.md:101` and `:143`, which claim three calendar violations and some preview-coverage violations are "left visible during this bootstrap". Neither exists — the lint gate is green, and `52f0136` closed the preview ones. Delete both paragraphs, and re-add the calendar one only if the widened rule genuinely finds drift. (audit 2026-07-26)

## P1s (Should do)

## P2s (Nice to have)
- refactor(SnapshotKitTesting) [needs-design]: Dynamically link `SnapshotKitTesting` so its capture state is genuinely one copy per process, lifting the "never add a second image-snapshot bundle" rule in [`AGENTS.md`](AGENTS.md#targets). **Spiked; it works, and was deliberately not landed** — recorded here so a next attempt starts from the findings rather than the dead ends. Only worth picking up if a second snapshot bundle becomes genuinely desirable: today the one-bundle rule costs nothing, and this costs a resource-copying build phase. (spike 2026-07-26)
	- What works: `.library(name: "SnapshotKitTesting", type: .dynamic, …)` in [`Package.swift`](Package.swift) produces a real framework; the `.xctest` then links `@rpath/SnapshotKitTesting.framework` and its private `_swizzleDepth` count drops from one-per-bundle to **zero**. The whole goal, in one line.
	- The blocker: a dynamic product that *statically absorbs* a resource-bearing dependency orphans that dependency's resources. `AccessibilitySnapshotParser`'s code moves into the framework while its `.bundle` stays in the `.xctest`, and SwiftPM's generated accessor searches only `Bundle.main.resourceURL`, `Bundle(for: BundleFinder.self).resourceURL`, `Bundle.main.bundleURL` — so `Bundle.module` hits its `fatalError` and **every VoiceOver-annotated capture traps** (`AccessibilitySnapshotBaseView.parseAccessibility()` → `StringLocalization.preferredBundle(for:)`). Verified fix: copy the resource bundles into `PackageFrameworks/SnapshotKitTesting.framework/`, after which the accessibility suites pass with no pixel drift. Automating it needs a build phase against a framework Xcode's SPM integration generates — the same `Bundle.module` placement fragility the StuffTestHost WhereCore embed was, which is the main argument against landing it.
	- Dead end: Tuist's `PackageSettings(productTypes:)` does nothing here. The local package is wired as an `XCLocalSwiftPackageReference` and resolved by Xcode's own SPM integration, so Tuist's product-type machinery never applies — only SwiftPM's `type:`. Relatedly, `type: .dynamic` takes effect only for a product an Xcode target consumes *as a product*: WhereUI depends on the SnapshotKit *target*, so SnapshotKit stayed static despite the annotation.
	- Trap: **a shared DerivedData reports false negatives here.** Two separate runs reported "no frameworks produced" from an incremental build that had not re-resolved the package graph. Spike this into a fresh `-derivedDataPath` or it will lie to you.
- perf(StuffTestHost) [needs-design]: Two loose ends in the shared test host, both reaching the root Tuist manifest, which is why they sit here rather than in a StuffTestHost file. The WhereCore-always-embedded build trade-off is documented and verified load-bearing at `Project.swift:256` — decide whether to keep documenting it or split the host so unrelated bundles don't pay for it. Separately, the scene configuration name is spelled twice, in `Shared/StuffTestHost/Sources/AppDelegate.swift:11` and `Project.swift:244`, so the two can drift silently. (audit 2026-07-26)

# Completed issues

## P2s (Nice to have)
- test(WhereUI) [needs-design]: broken-snapshots — two snapshot suites pinned views WhereUI doesn't own (`PeriscopeViewer` and `SwiftDataInspector`), flagged `[Fix later]` on PR #101. (Resolved: both suites, and their reference images, now live under the module they cover. The prerequisite this item assumed — a snapshot *bundle* per module, each with its own scheme and CI job — turned out to be the wrong shape and was **not** built. Per-module bundles are actively unsafe: each `.xctest` statically embeds what it links, so a second one would carry a second copy of `SnapshotKitTesting`, whose "process-global" capture state is module-global and therefore per copy — two copies co-loaded into one `StuffTestHost` would flip the safe-area swizzle's parity against each other and neither capture lock would see the other's captures (verified with `nm`: each built bundle defines its own private `_swizzleDepth`). And per-module bundles were never needed for ownership: swift-snapshot-testing derives the `__Snapshots__` directory from the calling file's `#filePath`, so a suite records beside itself wherever it lives. So the single bundle was renamed `WhereUISnapshotTests` → `StuffSnapshotTests` and gained a `sources` directory per module, keeping one scheme and one CI job. The one-bundle rule is now recorded in the root `AGENTS.md` "Targets" section and in `SnapshotKitTesting/AGENTS.md`. Moving `PeriscopeViewer` changed no pixels — it seeds its own `periscopeBroadwayRoot()`, so the `whereBroadwayRoot()` wrapper the old suite credited for "app styling" was contributing nothing; `SwiftDataInspector` did re-record, since it moved off Where's store onto a local fixture schema.)
