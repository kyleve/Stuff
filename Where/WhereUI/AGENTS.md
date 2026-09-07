# WhereUI – Module Shape

WhereUI is the SwiftUI layer of the Where feature. It owns the screens, the
shared components and widget views, and the `@Observable` view models that
orchestrate `WhereCore` for them (`WhereModel`, the `WhereSession`
coordinator, and the scoped `YearReportModel` / `ResolveModel` /
`BackupModel` / `RemindersSettingsModel` / `DevicesSettingsModel` /
`OnboardingFlowModel` / `OnboardingImportRecoveryModel` /
`LocationForecastModel` / `DiagnosticReportingSettingsModel`).
Layering, localization, preview, and testing conventions live in the feature
[`Where/AGENTS.md`](../AGENTS.md). Read that and the root
[`AGENTS.md`](../../AGENTS.md) first.

## Scope & dependencies

- Presentation layer only. No domain rules, persistence, or store I/O here
  ([Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
- WhereUI maps Core's persisted `RegionSymbol` values to SFSafeSymbols'
  `SFSymbol` and re-exports SFSafeSymbols for its presentation API consumers.
- Composition is the one exception. `WhereScope` and `WhereModel` decide which
  world the app is logged in to and assemble it. That is launch wiring, not
  domain logic. See [Scopes and the launch](../AGENTS.md#scopes-and-the-launch).
- Keep `FileInstallationRecordingContextStore` as the UIKit/FileManager
  adapter for Core's installation-context protocol. Resolve one instance at
  the app root. Inject it into both `WhereModel` and `WhereBootstrap`.
- Persist the installation identity, recording choice with its current-On
  timestamp, stable profile/policy IDs and timestamps, two-phase backup-import
  recovery, and the independent terminal onboarding-import tombstone together
  in the excluded-from-backup sidecar. Never infer confirmation from
  backed-up preferences or migrate it from `UserDefaults`. Persist an explicit
  changed choice when onboarding retries after a later failure.
- Retire the installation sidecar with an atomic directory rename before
  cleanup. Retain the proposed replacement behind `ResetCleanupError` until
  tombstone deletion succeeds (`InstallationRecordingContextStoreTests`).
- Reconcile every pending import after scope resolution but before session
  handoff or recording. Reconcile onboarding imports before offering Restore.
  Acknowledge their preference independently of cleanup. Retain the marker
  through any failure (`WhereLaunchTests`).
- Keep backup import onboarding-only. Settings exports archives but never
  starts or resumes an import (`BackupModelTests`).
- Keep diagnostic reporting's saved, process-effective, applying, and failed
  states distinct. Crash and replay choices stay pending until relaunch.
  Remote-log revisions apply live. A runtime failure invalidates in-flight
  applies. An older completion must never win.
- The DEBUG developer accordion may only update
  `WhereDeveloperLaunchController` for the next launch. Inspector and demo are
  mutually exclusive. It must not switch the current runtime. A demo request
  is consumed once before the onboarding gate and must never open a real store.
  Keep its synthetic clock scoped to the in-memory demo session.
- Keep the DEBUG Logs destination visible for every
  `WhereModel.logStoreState`. Opening, unavailable, and failed stores are
  diagnostics to render, not reasons to hide the tool.
- Keep the DEBUG card designer's draft in one root-owned `CardDesignerModel`.
  Persist the draft. Leave its app-wide override disabled at every launch.
- Flyover infrastructure stays under `#if DEBUG` in
  [`Sources/Developer/Flyover`](Sources/Developer/Flyover). Each represented
  screen declares a DEBUG-only `WhereFlyoverProviding` extension in its own
  source file. The integration may import the app-agnostic `Flyover` module
  and build one unactivated in-memory `WhereScope`. The shared module must
  never import WhereUI.
- Derive `WhereFlyoverScreenID` from the represented view type. Keep that
  screen's variants, viewport/navigation settings, and outgoing routes in its
  colocated registration. Never restore a centralized screen enum or catalog
  factory methods.
- Construct and retain the Where Flyover catalog once after its world loads.
  Never rebuild fixture state from a SwiftUI `body`.
- Present Where Flyover from the developer accordion with `fullScreenCover`.
  Place it outside the selected-tool `NavigationStack`.
- Register leaf screens against Flyover's default navigation container. Use
  `.none` only for views that own their root stack and for widgets/snippets.
- Consumers (`WhereWidgets`, `WhereIntents`) get Broadway *through* WhereUI.
  They must **not** link `BroadwayUI`/`BroadwayCore` themselves (root
  [double-link rule](../../AGENTS.md#never-double-link-a-product-whereui-already-carries)).
  That is why `whereBroadwayRoot()` lives here rather than being called as
  `broadwayRoot` at each site.
- Keep render-ready region geometry in the root-injected
  `RegionOutlinePathCache`. RegionKit owns the cached source outlines and its
  stateless simplifier. WhereUI chooses full/medium/small/micro tolerances and
  caches the resulting SwiftUI `Path`s. Use the small path for the stamp. Use
  the micro path for repeated borders on location cards and estimate panels.
  Project Locations-card GPS points through the cache's shared
  `RegionArtworkProjection`. Never project, simplify, or spatially reduce
  artwork in a card's `body`.
- Keep Locations-card points on `YearReportModel`'s loaded
  `YearReportDetails`.
- Keep `RootView` passing LifecycleKitUI the stylesheet's positive splash
  minimum and active-scene visibility: the first foreground-visible `MainTabs`
  reveal stays covered when headless promotion coalesces or the first hold is
  interrupted, while warm resumes never replay it.
- Keep planned-stay persistence, forecast math, and location verification in WhereCore.
  `LocationForecastModel` mirrors the register and the advisory check for the Locations, calendar,
  and timeline surfaces.
- Hide every forecast and planned-stay visualization behind
  `YearReportModel.showsEstimatedTimeAndPlanning`; persist Off only after clearing the synced plan.
- Continuous/looping motion (repeat-forever pulses, `TimelineView(.animation)`,
  typewriter reveals) must consult the shared `@MotionIsStatic` helper
  ([`Sources/Shared/MotionIsStatic.swift`](Sources/Shared/MotionIsStatic.swift))
  for its static end-state. Never hand-roll the
  `\.accessibilityReduceMotion` + `\.isCapturingSnapshot` pair.
- A step joins `WhereLaunch`'s plan through `.measured()`. It must declare a
  `budget` (`BudgetedLaunchStep`). See [Spans](../AGENTS.md#spans). WhereUI also
  owns log retention. `LogHistoryPruner` bounds the store by age *and* event
  count. Both bounds are load-bearing. An age window alone leaves a
  heavy-logging device unbounded inside it.
- A compact form `DatePicker` goes through `WhereDatePicker`
  ([`Sources/Shared/WhereDatePicker.swift`](Sources/Shared/WhereDatePicker.swift)).
  It substitutes a deterministic stand-in under capture. The live control
  renders relative to *today*. No reference containing one is stable across
  days. Views do not read `\.isCapturingSnapshot` to branch themselves. Capture
  handling stays inside the shared component.
- Reconcile `LocationCardsPresentationModel` only from the visible primary
  card surface after its stylesheet-owned reveal delay. If another tab, covering
  sheet, or pushed destination is visible, cancel the delay. Leave its persisted
  baseline untouched so returning can animate and haptically signal the change.
- Release Location-card counts and rank motion through the same delayed
  reconciliation. Flourish only when the same two primary regions reverse
  during one visible, same-year session. Synchronize initial, hidden, year,
  and membership changes quietly.
- Keep settled Location cards in displayed rank source order. Use each card's
  `Region` for the `ForEach` and ranking-layout identity.
- Use only `RegionRanking.primary` silhouettes in the estimate-panel microprint,
  even when the panel shows a third forecast or a focused secondary region.
- Give each ranked card an independent `GlassEffectContainer`. Apply ranking
  and overtake motion outside the complete link and card surface.
- Keep the source hierarchy stable while the cards cross. Commit the real
  displayed order without animation after the ranking keyframes finish.
- Keep the explicit ranking layout as the only reorder animation. Use the
  identity glass transition. Do not add `matchedGeometryEffect` or
  `glassEffectID`.
- Keep the ranking layout separate from the calendar zoom namespace. Preserve
  exactly one calendar transition source for each visible region.
- Play at least two overtakes in the lab after each ranking-motion change.
  Inspect Reduce Motion and VoiceOver order because settled snapshots do not
  prove the transition. See PR #289.

## Design system — `WhereStylesheet`

Follow the repo [`building-ui`](../../.agents/skills/building-ui/SKILL.md)
skill for token ownership, variants, trait derivation, layout, accessibility,
and rendering coverage. Where's sheet is
[`WhereStylesheet`](Sources/Shared/WhereStylesheet.swift), read through
`@Environment(\.stylesheet)` and defaulted to `WhereStylesheet.default` off the
view tree. [`README.md`](README.md#design-system) documents its live API and
worked examples.

- The `motion` group keeps full-motion values a view picks between
  (`motion.reducedReveal` over `motion.reveal`). The launch reveal's fallback
  swaps an `AnyTransition`, which is not `Equatable` and cannot be a token.
- **Per-region tints stay in `RegionStyle`.** Resolve via
  `@Environment(\.regionStyles)` and seed by
  `whereBroadwayRoot(theme:regionStyles:)`. Use no global accessor or hardcoded
  per-region look in a view.
- **Seed `WhereTheme` through `whereBroadwayRoot(theme:regionStyles:)`.** Standard
  and Alternate remain distinct persisted identities even while their tokens match.
- The DEBUG card designer may override only presentation values already owned
  by `CardStyles`. It must not add a second production styling system or alter
  count animation and outline-cache behavior.
- Keep the DEBUG Ranking Animation Lab session-only. It tunes the containing
  Location-card stack, never Card Designer persistence, exports, or app overrides.
- Keep the Appearance welcome reset under `#if DEBUG`. Clear only the saved welcome region through `YearReportModel.resetLocationWelcome()`.

## Testing

`WhereStylesheetTests` pins every token default and trait-aware derivation.
`WhereStylesheetEnvironmentTests` covers the `@Environment(\.stylesheet)`
glue and `whereBroadwayRoot()` seeding, including the WhereWidgets path.
When you add, rename, or retune a token, update those assertions in the
same change.

`WhereFlyoverCatalogTests` pins the catalog against the colocated registrations
assembled by `WhereFlyoverCatalog`. Add a registration beside every new
top-level screen. List its type in the appropriate catalog group. Flyover
frames share one `WhereFlyoverWorld`. Synthetic preview models are reserved for
states the seeded demo cannot express.

Screens, widgets, and app-flow surfaces are pinned as matrixed image
snapshots under [`SnapshotTests/`](SnapshotTests). Those build as this module's
`WhereUISnapshotTests` bundle in the shared `StuffSnapshotTests` scheme and CI
job, deliberately outside `Stuff-iOS-Tests` (root
[`AGENTS.md`](../../AGENTS.md#targets)). Declarations use the helpers in
[`Sources/Preview/WhereSnapshot.swift`](Sources/Preview/WhereSnapshot.swift).
Follow `building-ui` for authoring and the repo `running-tests` skill for
recording/reviewing references.
