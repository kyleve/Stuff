# WhereUI – Module Shape

WhereUI is the SwiftUI layer of the Where feature: the screens, the shared
components and widget views, and the `@Observable` view models that
orchestrate `WhereCore` for them (`WhereModel`, the `WhereSession`
coordinator, and the scoped `YearReportModel` / `ResolveModel` /
`BackupModel` / `RemindersSettingsModel`). Layering, localization, preview,
and testing conventions live in the feature [`Where/AGENTS.md`](../AGENTS.md)
— read that and the root [`AGENTS.md`](../../AGENTS.md) first.

## Scope & dependencies

- Presentation layer only — no domain rules, persistence, or store I/O here
  ([Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
- Composition is the one exception: `WhereScope` and `WhereModel` decide which
  world the app is logged in to and assemble it. That's launch wiring, not
  domain logic — see [Scopes and the launch](../AGENTS.md#scopes-and-the-launch).
- The DEBUG developer accordion may only latch or clear
  `InspectorModeController` for the next launch. It must not host a live
  SwiftData inspector or switch the current runtime.
- Keep the DEBUG Logs destination visible for every
  `WhereModel.logStoreState`; opening, unavailable, and failed stores are
  diagnostics to render, not reasons to hide the tool.
- Flyover infrastructure stays under `#if DEBUG` in
  [`Sources/Developer/Flyover`](Sources/Developer/Flyover), while each
  represented screen declares a DEBUG-only `WhereFlyoverProviding` extension
  in its own source file. The integration may import the app-agnostic
  `Flyover` module and build one unactivated in-memory `WhereScope`; the shared
  module must never import WhereUI.
- Derive `WhereFlyoverScreenID` from the represented view type, and keep that
  screen's variants, viewport/navigation settings, and outgoing routes in its
  colocated registration; never restore a centralized screen enum or catalog
  factory methods.
- Construct and retain the Where Flyover catalog once after its world loads;
  never rebuild fixture state from a SwiftUI `body`.
- Present Where Flyover from the developer accordion with `fullScreenCover`,
  outside the selected-tool `NavigationStack`.
- Register leaf screens against Flyover's default navigation container; use
  `.none` only for views that own their root stack and for widgets/snippets.
- Consumers (`WhereWidgets`, `WhereIntents`) get Broadway *through* WhereUI
  and must **not** link `BroadwayUI`/`BroadwayCore` themselves (root
  [double-link rule](../../AGENTS.md#never-double-link-a-product-whereui-already-carries));
  that's why `whereBroadwayRoot()` lives here rather than being called as
  `broadwayRoot` at each site.
- Keep render-ready region geometry in the root-injected
  `RegionOutlinePathCache`: RegionKit owns the cached source outlines and its
  stateless simplifier, while WhereUI chooses full/medium/small tolerances and
  caches the resulting SwiftUI `Path`s; reuse the small path for the stamp and
  microprint border, and never project or simplify a boundary in a card's
  `body`.
- Continuous/looping motion (repeat-forever pulses, `TimelineView(.animation)`,
  typewriter reveals) must consult the shared `@MotionIsStatic` helper
  ([`Sources/Shared/MotionIsStatic.swift`](Sources/Shared/MotionIsStatic.swift))
  for its static end-state — never hand-roll the
  `\.accessibilityReduceMotion` + `\.isCapturingSnapshot` pair.
- A step joins `WhereLaunch`'s plan through `.measured()` and so must declare a
  `budget` (`BudgetedLaunchStep`) — see [Spans](../AGENTS.md#spans). WhereUI also
  owns log retention: `LogHistoryPruner` bounds the store by age *and* event
  count, and both bounds are load-bearing (an age window alone leaves a
  heavy-logging device unbounded inside it).
- A compact form `DatePicker` goes through `WhereDatePicker`
  ([`Sources/Shared/WhereDatePicker.swift`](Sources/Shared/WhereDatePicker.swift)),
  which substitutes a deterministic stand-in under capture — the live control
  renders relative to *today*, so no reference containing one is stable across
  days. Views don't read `\.isCapturingSnapshot` to branch themselves; capture
  handling stays inside the shared component.

## Design system — `WhereStylesheet`

All appearance tokens — geometry, fonts, colors, motion — live in
`WhereStylesheet`
([`Sources/Shared/WhereStylesheet.swift`](Sources/Shared/WhereStylesheet.swift)),
a Broadway `BStylesheet` read via `@Environment(\.stylesheet)`; off the
`View` tree (layout helpers, tests) use `WhereStylesheet.default`. How to
consume and extend it — per-component style groups, variant subscripts, the
`RegionStyle` resolver — is in [`README.md`](README.md#design-system). The
rules:

- **Never hardcode appearance in a view** or collect constants into a flat
  grab-bag; a new value lands on the owning component's style group, or on a
  shared scale (`Spacing`, `Size`, `Palette`, `Typography`, `Motion`) only
  when genuinely cross-component.
- **Never borrow another component's style** — a component defines its own
  group rather than reading a value off someone else's.
- **Resolve a variant once** (a `Variant` enum + `subscript`, see
  `CardStyles`) — don't branch `compact ? … : …` through a body.
- **Don't bake trait-derived values into the defaults** — `.standard` /
  property defaults hold the fixed set; the reactive slice applies only in
  `init(context:)`, so a default/system context reproduces
  `WhereStylesheet.default`.
- **Derive accessibility settings in the sheet, not the view** — vend one
  resolved token, and a *single* token when a setting changes more than one
  value (`CardStyles.DayCountStyle` pairs the morph with its animation).
  Exception: the `motion` group keeps full-motion values a view picks between
  (`motion.reducedReveal` over `motion.reveal`), because the launch reveal's
  fallback swaps an `AnyTransition`, which isn't `Equatable` and can't be a
  token.
- **Per-region tints stay in `RegionStyle`**, resolved via
  `@Environment(\.regionStyles)` and seeded by
  `whereBroadwayRoot(regionStyles:)` — no global accessor or hardcoded
  per-region look in a view. Adaptive system roles (`.secondary`) and
  `.accentColor` stay inline.
- `WhereThemes` is deliberately empty — the seam a future app-wide theme
  plugs into.

## Testing

`WhereStylesheetTests` pins every token default and trait-aware derivation;
`WhereStylesheetEnvironmentTests` covers the `@Environment(\.stylesheet)`
glue and `whereBroadwayRoot()` seeding, including the WhereWidgets path.
Adding, renaming, or retuning a token means updating those assertions in the
same change.

`WhereFlyoverCatalogTests` pins the catalog against the colocated registrations
assembled by `WhereFlyoverCatalog`; add a registration beside every new
top-level screen and list its type in the appropriate catalog group. Flyover
frames share one `WhereFlyoverWorld`; synthetic preview models are reserved for
states the seeded demo cannot express.

Screens, widgets, and app-flow surfaces are pinned as matrixed image
snapshots under [`SnapshotTests/`](SnapshotTests) — those, not hosting smoke
tests, own "does this screen render". They build as this module's
`WhereUISnapshotTests` bundle, run from the shared `StuffSnapshotTests`
scheme and its CI job, deliberately outside `Stuff-iOS-Tests` (root
[`AGENTS.md`](../../AGENTS.md#targets)). **Each view declares its matrix
once, in its own source file**, via a `SnapshotProviding` conformance under
`#if DEBUG` whose `#Preview` renders `Self.snapshotPreviews` — one
declaration drives both the Xcode cutsheet and the image tests (helpers in
[`Sources/Preview/WhereSnapshot.swift`](Sources/Preview/WhereSnapshot.swift));
suites are one `FooSnapshotTests` per view. To re-record a reference, delete
the PNG under `SnapshotTests/__Snapshots__/` (LFS-tracked) and run the scheme
— the suites record `.missing`, and a recording run fails by design. Bulk
re-records forward `TEST_RUNNER_SNAPSHOT_RECORD=failed` (see the
[SnapshotKitTesting README](../../Shared/SnapshotKitTesting/README.md#recording)).
