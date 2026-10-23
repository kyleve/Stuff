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

- Keep InstallerKit’s `UpdateModel` process-owned and inject it at `RootView`.
  Poll only from a foreground, non-demo app surface. Keep the last successful
  result visible on failure. Keep App Updates first in Settings for eligible builds,
  including local and current builds. Show the update badge only when an update needs attention.
  Guard: `SettingsSearchTests.updatesRequireAnEligibleBuildAndStayOutOfDemo`.
  Install actions use InstallerKit's validated
  system-installer URL for the displayed build.
  Render the detail with InstallerKitUI's shared `AppUpdatesView`. Supply Where branding
  and Settings search modifiers through its section-decoration seam.
  Keep refresh and supersession policy in InstallerKit.
  Guard: `InstallerKitTests/UpdateModelTests`.

- Presentation layer only. No domain rules, persistence, or store I/O here
  ([Layering](../AGENTS.md#layering)). Dependencies live in the root
  [`Package.swift`](../../Package.swift).
- WhereUI maps Core's persisted `RegionSymbol` values to SFSafeSymbols'
  `SFSymbol` and re-exports SFSafeSymbols for its presentation API consumers.
- Composition is the one exception: `WhereScope` and `WhereModel` decide which
  world the app is logged in to and assemble it. That's launch wiring, not
  domain logic — see [Scopes and the launch](../AGENTS.md#scopes-and-the-launch).
- The app injects its configured primary icon name at `RootView`; icon-picker
  code treats every manifest entry as an asset and derives primary versus
  alternate status from that injected name.
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
  Attach export sheets and error alerts to `DataSettingsView` outside its `Form` sections.
- Keep diagnostic reporting's saved, process-effective, applying, and failed
  states distinct. Crash and replay choices stay pending until relaunch.
  Remote-log revisions apply live. A runtime failure invalidates in-flight
  applies. An older completion must never win.
- Keep the combined personal-data switch scoped to its named controls. Preserve consumer-defined grants and use effective policy for privacy disclosures.
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
- Build one `WhereFlyoverWorld` for each hosted web export. Reuse it for every
  capture. Never activate its scope or read user data.
- Export stable screen IDs from reflected screen and context type names. Use
  snapshot case names for snapshot-backed variant IDs.
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
  Share the region artwork treatment across regular and compact cards. Keep
  compact dimensions in the compact style. Resolve Elsewhere's paper surface
  from that geometry, without a progress bar, using the shared matte renderer.
  Keep primary specimens on the selected theme's surface. Preserve Elsewhere's
  white/neutral-dark fill when Flat overrides its outline and shadow.
  Use the original region color for Elsewhere artwork and borders. Apply its
  contrast adjustment only to text.
  Project Locations-card GPS points through the cache's shared
  `RegionArtworkProjection`. Never project, simplify, or spatially reduce
  artwork in a card's `body`.
- Publish flight notices, historical indicators, correction reviews, and actionable counts from one
  `YearReportModel` scan result. Inject that scene as the Resolve model's `ResolutionSource`. Re-key on raw evidence changes; never gate refresh
  on aggregate-report equality. Schedule presentation deadlines only in the foreground.
- Expose each calendar month as one accessibility element: regional totals in the label, chronological stay spans and dated badges in the value. Preserve planning qualifiers. Guard: `CalendarMonthAccessibilityTests`.
- Keep overview availability derived from the full-size calendar visibility rule in `CalendarPresentationModel`. Gray months remain actionable for rejection feedback. Guard: `CalendarPresentationModelTests`.
- Keep calendar flight days and timeline flight events independent of review dismissal.
  Show uncertain arrival timing explicitly. Render supported travel periods separately from later ground observations.
  Split timeline stays only for presentation; preserve every region-day exactly once.
- Keep the raw GPS path visible in correction reviews after samples lose attribution.
  Bound display geometry without changing the evidence or edits. Never join separate recording devices into one route.
- Route automatic GPS fixes through Core's sample-correction coordinator. Keep
  stale Apply results open for review and preserve manual editing while arrival is pending.
  Show each flight's own progress when a daily review mixes completed and pending flights.
  Retain pending information through Core's `dismissingProposal()` when dismissing completed-flight edits.
- Resolve historical device labels through `DeviceRecordingController.displayNames()`, not the active device list.
- Render point decisions from Core's reviewed corrections. Keep the review open after inclusion or restoration.
  Clear a pending confirmation when its evidence changes. Guard: `FlightReviewModelTests`.
- Keep each actionable flight point row as one accessible button, including its evidence and coordinate label.
  Use the recorded coordinate for its map preview, including excluded points. Keep the preview noninteractive.
- Use this installation's assessment for a live flight notice. Identify each
  recording device in shared reviews and retain historical pending review access.
- Use `regionArtworkTask` and `RegionArtworkModel` for cached artwork loading.
  Keep request identity complete; use a broader display key only when retaining
  compatible artwork during refresh is intentional.
- Keep Locations state payloads, flight notices, estimates, and ranked cards behind
  named view boundaries. Preserve presentation state and the calendar namespace
  at the screen root. Guard their body sizes with the colocated view tests.
- Keep the Locations background on the selected year’s complete visited-region set,
  and reuse that renderer in Elsewhere with its resolved visited-region set.
  Keep both in catalog order independent of card rank. Omit the catch-all Other
  entry from the print. Use the injected outline cache.
- Split Locations and Elsewhere by the configured primary set, not `RegionRanking`'s
  top two. Exclude zero-day cards and sort ties in catalog order.
- Keep Elsewhere cards, day lists, and map pins on the same resolved snapshot.
  Refresh from complete evidence identity. Reject cancelled or superseded results,
  retain successful same-year content on failure, and provide retry. Day actions
  pass the original calendar day into the existing correction flow.
- Keep Locations-card points on `YearReportModel`'s loaded
  `YearReportDetails`. Elsewhere cards use their resolved report's locations through
  the shared `RegionCardLocations` identity and constellation renderer. Both tabs
  honor the recorded-location-dot preference.
- Keep `RootView` passing LifecycleKitUI the stylesheet's positive splash
  minimum and active-scene visibility: the first foreground-visible `MainTabs`
  reveal stays covered when headless promotion coalesces or the first hold is
  interrupted, while warm resumes never replay it.
- Keep itinerary persistence, forecast bounds, overlaps, and Home projections in WhereCore.
  `LocationForecastModel` mirrors one planning snapshot through store-change refreshes.
  Complete the latest started read when its requesting sheet disappears; keep older results from replacing it.
- Keep each planned stay independently editable by its stable ID. Keep Home separate from tracked regions.
- Gate forecast visualizations with `YearReportModel.showsEstimatedTimeAndPlanning`.
  Hiding estimates must preserve every stay and the Home setting. Settings can still open the planner.
- Keep calendar and timeline projections separate from recorded history. Label possible dates and Home assumptions.
  Guard: `LocationForecastModelTests` and `EstimatedTimeAndPlanningSettingsModelTests`.
- Keep future itinerary years selectable while annual estimates remain current-year-only.
  Guard: `YearReportModelTests.futureItineraryYearsRemainReachableWithoutEnablingAnnualEstimates`.
  The read-only Estimated Time gallery keeps explanatory forecast examples
  visible in grayscale when Off; it must not activate planning.
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

- Resolve component layout and motion in `WhereStylesheet.init(context:)`.
  Keep launch style consumers beneath `whereBroadwayRoot()`. The launch slice
  selects an `Equatable` reveal policy whose computed property builds the transition.
- Keep scoped SwiftUI appearance overrides consistent with Broadway traits.
  Pair `.dynamicTypeSize` limits with the corresponding content-size override.
  Pair explicit `.colorScheme` overrides with `.bMode` for styled subtrees.
- Keep live Card Designer and ranking-lab drafts outside the cached slice.
  These runtime inputs compose over the resolved base style. Document their
  direct system-trait reads at the declaration.
- **Per-region tints stay in `RegionStyle`.** Resolve via
  `@Environment(\.regionStyles)` and seed by
  `whereBroadwayRoot(theme:regionStyles:)`. Use no global accessor or hardcoded
  per-region look in a view.
  Derive automatic colors from the permanent region ID with a fixed hash.
  Never use localized names, card order, or Swift's randomized `Hasher`.
  Keep the catalog's palette order and hash stable across launches.
  Guard: `RegionAppearanceCatalogTests.idDerivedDefaultsHaveStableAssignments`.
- **Seed `WhereTheme` through `whereBroadwayRoot(theme:regionStyles:)`.** Standard
  and Flat use the stable `standard` and `alternate` identities.
- Keep Standard as the base stylesheet. Resolve shared traits before applying `WhereThemeOverrides`.
  Put theme values and theme-specific trait decisions in their definition, such as `WhereFlatTheme`.
  Keep override application independent of theme selection and trait resolution.
  Omitted overrides inherit the adjusted base. Explicit zero values disable effects.
  Use `BModeVarying` for paired light/dark values. Keep runtime region colors outside theme definitions.
  Guards: `WhereThemeOverridesTests`, `WhereFlatThemeTests`.
- **Design new and changed custom components for every supported theme.**
  Resolve theme and accessibility choices in the owning `WhereStylesheet`
  component style. Views consume that style without checking the selected theme.
  Reuse `matteSurface` for Flat's opaque fills, visible strokes, and restrained
  shadows. Use a subtle tint for pressed feedback. Exclude glass, reflections,
  and luminous glows from Flat's view hierarchy. Observe tilt only while a
  visible surface needs sheen. Preserve artwork and informational gradients.
  Keep system chrome native and widget/snippet surfaces lightweight.
  Guard: `WhereStylesheetSurfaceTreatmentTests`.
- The DEBUG card designer may override only presentation values already owned
  by `CardStyles`. It must not add a second production styling system or alter
  count animation and outline-cache behavior.
- Keep the DEBUG Ranking Animation Lab session-only. It tunes the containing
  Location-card stack, never Card Designer persistence, exports, or app overrides.
- Keep the Appearance welcome reset under `#if DEBUG`. Clear only the saved welcome region through `YearReportModel.resetLocationWelcome()`.
- Keep welcome-card arrival, departure, and scrim timing in `locationWelcome.motion`. Apply spatial transitions only to the card layer.
- Keep `LocationWelcomeModel`, its overlay, and its bottom accessory owned by
  `MainTabs`. Resolve once per active-scene entry regardless of tab. Only denied
  or restricted access and disabled Precise Location stay visible as recovery
  actions; transient and confidence failures return to idle.
- Establish the first successful live-region baseline without a welcome, including after backup import.
  Preserve explicit DEBUG reset requests and commit no history from cancelled or superseded lookups. Guard: `LocationWelcomeModelTests`.

## Feature discovery

Keep gallery rows and Forms behind small named views inside focus and reveal scopes. Guard: `FeatureGuidePageTests` and the gallery view-size tests.
Keep Explore Features browsing read-only. Use production presentation components and explicit actions into existing editors.
Use `PresenceTimelineList` with `.excerpt` for embedded Timeline galleries; keep row layout and planned-stay joins in that view.
Use process-effective diagnostics for privacy claims. Hide gallery links whose destinations are unavailable in demo mode.
Use the [`update-explore-features`](../../.agents/skills/update-explore-features/SKILL.md) skill for periodic coverage updates.

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
When registrations, routes, or default variants change, run
`WhereFlyoverViewSnapshotTests` alongside the affected screen suites.

Screens, widgets, and app-flow surfaces are pinned as matrixed image
snapshots under [`SnapshotTests/`](SnapshotTests). Those build as this module's
`WhereUISnapshotTests` bundle in the shared `StuffSnapshotTests` scheme and CI
job, deliberately outside `Stuff-iOS-Tests` (root
[`AGENTS.md`](../../AGENTS.md#targets)). Declarations use the helpers in
[`Sources/Preview/WhereSnapshot.swift`](Sources/Preview/WhereSnapshot.swift).
Follow `building-ui` for authoring and the repo `running-tests` skill for
recording/reviewing references.

For new or changed themed components, use `whereThemeSnapshot` for one comparison
sheet containing every supported theme. Use representative states across light/dark
and relevant accessibility configurations; keep each configuration in a separate
sheet. Use narrower matrices for additional states. Keep production component
width and behavior, including artwork readiness and informational gradients.

Keep per-theme full-screen coverage for critical integration screens such as
Locations, or screens whose composition changes materially with the theme.
Do not duplicate entire screen matrices to exercise a child component's surface.
Keep appearance-picker selection-state coverage. Native chrome and unchanged
lightweight widget/snippet surfaces do not need duplicate theme cases.

`whereSnapshot` defaults to Standard and preserves its existing reference paths.
Other themes use stable consumer-owned groups (`flat/` for `.alternate`). Mixed-theme
sheets use `themes/`. Special trait images use `other/` inside the selected group.
Never derive the folder from a localized label or rename a persisted theme identity.
