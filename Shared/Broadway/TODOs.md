# Broadway todos

The backlog for the Broadway module group — BroadwayCore, BroadwayUI, and the
BroadwayCatalog showcase app.

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P1s (Should do)
- test(BroadwayCatalog) [quick-win]: Host `BroadwayCatalogTests` in `StuffTestHost` like every other hosted bundle. Today it is a hand-rolled target hosted by the BroadwayCatalog app itself (`Project.swift:665-675` — deps `[BroadwayCatalog, TestHostSupport]`, no `StuffTestHost`), a deviation from the convention that hosted tests run in the shared host. Rewire it through the `unitTests` helper (keeping the `BroadwayCatalog` code dependency) and confirm `tuist test BroadwayCatalogTests` stays green. (pr#149 review 2026-07-28)
- fix(BroadwayCatalog) [quick-win]: `BroadwayApp.swift:6-7` never seeds `.broadwayRoot()`, so the showcase renders with no `BContext` and every `@Environment(\.bContext)` read falls back to defaults — the one app whose job is to show Broadway is the one not using it. (audit 2026-07-26)
- test(BroadwayCatalog) [quick-win]: `Tests/BroadwayCatalogTests.swift:4` is an empty `struct BroadwayCatalogTests {}` wired into the `Stuff-iOS-Tests` scheme (`Project.swift:755`), so CI runs it and it asserts nothing. Replace it with a launch smoke test. (audit 2026-07-26; re-verified 2026-08-16)
- fix(BroadwayUI) [needs-design]: A nested `BRootViewController` registers duplicate trait observers (source `TODO` at `BRootViewController.swift:92-93`; the observer is still created unconditionally at `:95-103`). Latent today — Where reaches Broadway only through `whereBroadwayRoot()` / `BRootView`, neither of which nests — but it fires the moment something does. (audit 2026-07-26)

## P2s (Nice to have)
- convention(BroadwayCore) [quick-win]: Guard the `didSet` work in `BContext.swift:34-36`, `:45-47`, `:52-54` and `BRootViewController.swift:37-41` on an unchanged `Equatable` value, so reassigning the same context isn't a full invalidation. (audit 2026-07-26)
- perf(BroadwayCore) [needs-design]: Evict the stylesheet cache under memory pressure (`BStylesheets.swift:90`, documented in a source `TODO`); it currently only grows. (audit 2026-07-26)
- test(BroadwayCore) [quick-win]: Add the missing 1:1 tests for `UIViewControllerTraitObserver`, `EquatableIgnored`, and `BTraitOverrides+SwiftUI`. (audit 2026-07-26)
- docs(BroadwayCatalog) [quick-win]: `README.md:3-4` promises a "living catalog" of components that the placeholder `ContentView` (`ContentView.swift:6-17`, an icon and a title) doesn't provide. Build the gallery or narrow the README to what ships. (audit 2026-07-26; re-verified 2026-08-16)

# Completed issues
