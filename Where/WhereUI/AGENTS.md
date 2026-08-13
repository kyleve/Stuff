# WhereUI – Module Shape

WhereUI is the SwiftUI layer of the Where feature: the screens, the shared
components and widget views, and the `@Observable` view models that
orchestrate `WhereCore` for them (`WhereModel`, the `WhereSession`
coordinator, and the scoped `YearReportModel` / `ResolveModel` /
`BackupModel` / `RemindersSettingsModel` / `DevicesSettingsModel` / `OnboardingFlowModel` /
`OnboardingImportRecoveryModel` / `LocationForecastModel` /
`DiagnosticReportingSettingsModel`).
Layering, localization, preview, and testing conventions live in the feature
[`Where/AGENTS.md`](../AGENTS.md)
— read that and the root [`AGENTS.md`](../../AGENTS.md) first.

## Scope & dependencies

- Presentation layer only — no domain rules, persistence, or store I/O here
  ([Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
- WhereUI maps Core's persisted `RegionSymbol` values to SFSafeSymbols'
  `SFSymbol` and re-exports SFSafeSymbols for its presentation API consumers.
- Composition is the one exception: `WhereScope` and `WhereModel` decide which
  world the app is logged in to and assemble it. That's launch wiring, not
  domain logic — see [Scopes and the launch](../AGENTS.md#scopes-and-the-launch).
- Keep `FileInstallationRecordingContextStore` as the UIKit/FileManager
  adapter for Core's installation-context protocol; resolve one instance at
  the app root and inject it into both `WhereModel` and `WhereBootstrap`.
- Persist the installation identity, recording choice with its current-On timestamp, stable
  profile/policy IDs and timestamps, two-phase backup-import recovery, and the independent
  terminal onboarding-import tombstone together in the excluded-from-backup sidecar; never infer
  confirmation from backed-up preferences or migrate it from `UserDefaults`. Persist an explicit
  changed choice when onboarding retries after a later failure.
- Retire the installation sidecar with an atomic directory rename before
  cleanup; retain the proposed replacement behind `ResetCleanupError` until
  tombstone deletion succeeds (`InstallationRecordingContextStoreTests`).
- Reconcile every pending import after scope resolution but before session handoff or recording;
  reconcile onboarding imports before offering Restore, acknowledge their preference independently
  of cleanup, and retain the marker through any failure (`WhereLaunchTests`).
- Keep backup import onboarding-only; Settings exports archives but never starts or resumes an
  import (`BackupModelTests`).
- Keep diagnostic reporting's saved, process-effective, applying, and failed
  states distinct. Crash/replay choices stay pending until relaunch; remote-log
  revisions apply live, a runtime failure invalidates in-flight applies, and an
  older completion must never win.
- The DEBUG developer accordion may only latch or clear
  `InspectorModeController` for the next launch. It must not host a live
  SwiftData inspector or switch the current runtime.
- Keep the DEBUG Logs destination visible for every
  `WhereModel.logStoreState`; opening, unavailable, and failed stores are
  diagnostics to render, not reasons to hide the tool.
- Keep the DEBUG card designer's draft in one root-owned `CardDesignerModel`;
  persist the draft, but leave its app-wide override disabled at every launch.
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
  stateless simplifier, while WhereUI chooses full/medium/small/micro
  tolerances and caches the resulting SwiftUI `Path`s; use the small path for
  the stamp and the micro path for the repeated border. Project Locations-card
  GPS points through the cache's shared `RegionArtworkProjection`, and never
  project, simplify, or spatially reduce artwork in a card's `body`.
- Keep Locations-card points on `YearReportModel`'s loaded
  `YearReportDetails`.
- Keep `RootView` opted into LifecycleKitUI's first-ready splash policy: the
  first foreground-visible `MainTabs` reveal gets the stylesheet minimum even
  when headless promotion coalesces or the first hold is interrupted, while
  warm resumes never replay it.
- Keep planned-stay persistence and forecast math in WhereCore; `LocationForecastModel` only mirrors
  the active register and orchestrates intents for the Locations, calendar, and timeline surfaces.
- Hide every forecast and planned-stay visualization behind
  `YearReportModel.showsEstimatedTimeAndPlanning`; persist Off only after clearing the synced plan.
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
- Reconcile `LocationDayCountPresentationModel` only from the visible primary
  card surface after its stylesheet-owned reveal delay; another tab, covering
  sheet, or pushed destination must cancel the delay and leave its persisted
  baseline untouched so returning can animate and haptically signal the change.

## Design system — `WhereStylesheet`

Follow the repo [`building-ui`](../../.agents/skills/building-ui/SKILL.md)
skill for token ownership, variants, trait derivation, layout, accessibility,
and rendering coverage. Where's sheet is
[`WhereStylesheet`](Sources/Shared/WhereStylesheet.swift), read through
`@Environment(\.stylesheet)` and defaulted to `WhereStylesheet.default` off the
view tree; [`README.md`](README.md#design-system) documents its live API and
worked examples.

- The `motion` group keeps full-motion values a view picks between
  (`motion.reducedReveal` over `motion.reveal`), because the launch reveal's
  fallback swaps an `AnyTransition`, which isn't `Equatable` and can't be a
  token.
- **Per-region tints stay in `RegionStyle`**, resolved via
  `@Environment(\.regionStyles)` and seeded by
  `whereBroadwayRoot(theme:regionStyles:)` — no global accessor or hardcoded
  per-region look in a view.
- Seed `WhereTheme` through `whereBroadwayRoot(theme:regionStyles:)`; Standard
  and Alternate remain distinct persisted identities even while their tokens match.
- The DEBUG card designer may override only presentation values already owned
  by `CardStyles`; it must not add a second production styling system or alter
  count animation and outline-cache behavior.

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
snapshots under [`SnapshotTests/`](SnapshotTests), built as this module's
`WhereUISnapshotTests` bundle in the shared `StuffSnapshotTests` scheme and CI
job, deliberately outside `Stuff-iOS-Tests` (root
[`AGENTS.md`](../../AGENTS.md#targets)). Declarations use the helpers in
[`Sources/Preview/WhereSnapshot.swift`](Sources/Preview/WhereSnapshot.swift);
follow `building-ui` for authoring and the repo `running-tests` skill for
recording/reviewing references.
