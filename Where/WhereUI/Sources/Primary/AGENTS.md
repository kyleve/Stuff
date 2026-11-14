# Locations and adaptive-pane contracts

Read the [module contract](../../AGENTS.md) and the [repository contract](../../../../AGENTS.md) first.

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
- Hide the Locations calendar estimate only when browsing and calendar panes are displayed together. Keep it in the compact calendar push, without disabling planned-day content or other calendars. Guard: `LocationsViewTestsDuo.estimateCardFollowsVisibleLocationsPanes`.
- Show Locations selection indicators only when browsing and calendar panes are displayed together. Guard: `LocationsViewTestsDuo.selectedRegionIsIndicatedOnlyBesideItsCalendar`.
- Keep navigation paths, search, sheets, and drafts in stable owning views above adaptive branches. Keep presented editors mounted while folding. Present Locations flight reviews in a sheet.
- Read system reserved regions only in `AdaptivePaneGeometry`. Keep authored pane limits in the stylesheet and measured geometry in the adapter. Guard: `where.reserved_region_layout_ownership`.
- Keep Locations in native browse/detail columns across folds when both panes fit; use compact navigation otherwise. Guard: `AdaptivePaneArrangementTests.portraitTabletopRetainsBrowseAndDetailColumns`.
- Use BroadwayUI scroll restoration for current-context anchors with caller-owned typed roles; scrolling must not select or move another pane.
- Keep rendered calendar anchors typed as `CalendarPresentationState.Target`, preserving month and estimate destinations. Detail owns the retained native scroll position; overview must not overwrite it.
- Show one initial loading or failure surface before Locations has a report. Remove the sidebar toggle through SwiftUI and leave split gestures to the system. Put shared toolbar actions only in the trailing pane when expanded. Guard: `LocationsViewSnapshotTests`.
- Keep reusable pane content outside native navigation shells. Present planning sheets above changing branches. Embedded demo tools use `demoExitPresentation = .embedded`.
- Keep synthetic-region injection under `#if DEBUG` and expose it through the Testing SPI. Transition tests retain one mounted container.
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
- Keep the collapsible Locations estimate on its summary surface in both expansion states.
  `LocationForecastSummary` owns expansion; share its expanded rows and planning controls through
  `LocationForecastContent`. `LocationForecastPanel` always shows that content without collapse state.
  Calendar, Timeline, and discovery panels retain the detailed passport surface.
- Use only `RegionRanking.primary` silhouettes in the estimate-panel microprint and summary watermarks,
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
