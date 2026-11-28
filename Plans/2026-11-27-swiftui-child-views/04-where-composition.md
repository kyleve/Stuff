# 04 — Where screen composition and extension hosts

**Status** · executing

Depends on [01 — Installer pilot](01-installer-pilot.md). See the [overview](README.md) for requirements and the [audit](audit.md) for source locations.

## Outcome and scope

Apply R-01 to WhereUI’s Primary, Year, Onboarding, Launch and Compatibility views, `MainTabs`, `RootView` and their previews, tests and fixtures. This plan also covers SwiftUI candidates in every Where module outside WhereUI, including the app, widgets, intents, share extension and RegionViewer. R-02 preserves observable lifetimes and host contracts. R-03 records the disposition and verification evidence for each reviewed surface. X-01 excludes product and public API changes. X-02 excludes permanent lint.

## Boundaries to review

| Area | Existing ownership and proposed extraction |
| --- | --- |
| Locations and Your Year | Extract the whole mode button returned by the 17-line `YearModePicker.segment(_:)` into a named view in the picker’s file. Keep the animated mode change, label and hit shape, plain button style, matched-geometry source and selected accessibility trait together. Pass the picker’s existing mode binding and namespace to the child. [YearView.swift](../../Where/WhereUI/Sources/Year/YearView.swift#L129) |
| Calendar and adaptive panes | Review the 166-line `CalendarContentView.calendarContent(months:)`. Keep typed scroll targets, focus and the zoom namespace with their present owners. Keep pane navigation and presented sheets mounted across folds. `LocationsView.browsePane`, `expandedBrowseContent` and `detailContent(arrangement:)` already construct named types. Review those types’ bodies and placement before adding a wrapper. |
| Main tabs, launch and onboarding | Keep selection, the scene report, welcome model and planning destination on `MainTabs`. Review `RootView.rootContent(stylesheet:)` and `OnboardingView.introPages` by branch. Keep the outer compatibility lockout and the onboarding flow owner stable. The gate registry, tab-content builder and app runtime’s `makeRootView()` have their own contracts. Inspect the visual children they host. |
| App and system hosts | Extract the ten-line `Button(intent:)` expression in `DaysInRegionInteractiveSnippet.content` into a named child in its parent’s WhereIntents file. Keep `LogDayIntent(regions: [region])`, the label, style and region tint together. The snippet decides when logging is available. Keep widget family and compatibility branches on `YearTotalsWidgetContent`, and share completion on the extension controller. Review `ShareEvidenceView.attachmentRow(_:)` and the view inside RegionViewer’s `WindowGroup`. [DaysInRegionSnippetIntent.swift](../../Where/WhereIntents/Sources/DaysInRegionSnippetIntent.swift#L89) |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the pilot, reconcile every candidate with the current checkout and detail one mounted flow or host per batch. Use the pilot’s ownership sketch to identify inputs, actions and the owner of each effect. Measure the complete button through its last attached modifier, including buttons with short labels. A batch is complete when every confirmed issue is fixed and verified. Record the resulting type, file and size, and link any overlapping label or modifier entries to the same control. For each remaining review location, identify the compliant view or applicable host contract.

Use `./test` to select the relevant hosted and image suites. `YearViewTests.bottomSelectorAndSelectedModeSurviveEveryFoldLayout` activates both segments and reads the selected accessibility trait across folds. `CalendarContentViewTests`, `LocationsViewTestsDuo` and `MainTabsTests` exercise navigation and remounts. Pair them with the corresponding image suites. For launch and onboarding, include the compatibility and onboarding suites for the changed branches.

For host changes, exercise the widget family in its host, the snippet via Siri or Shortcuts on device, and share save/cancel from the system share sheet. WhereUI widget snapshots cover shared rendering. The share extension and RegionViewer have no hosted test bundle. Validate a changed RegionViewer shell with its documented Catalyst build. Record which host paths were actually exercised and any remaining limits alongside the final placements.

## Execution and verification

| Slice | Source and acceptance |
| --- | --- |
| Year mode | `Where/WhereUI/Sources/Year/YearView.swift` has a 17-line `YearModePicker.segment` helper. Extract the complete button into a private named segment next to the picker with the current binding, namespace, animation, hit shape and selected trait. Verify `YearViewTests.bottomSelectorAndSelectedModeSurviveEveryFoldLayout` and `YearViewSnapshotTests`. See [Year source contract](../../Where/WhereUI/Sources/Year/AGENTS.md). |
| Calendar, Locations and timeline | Take MonthGrid/DayCell before the 166-line calendar content helper. Preserve typed scroll targets, focus and geometry namespace. Then take the Locations browse/detail panes and timeline rows. Reuse the types already constructed by `browsePane`, `expandedBrowseContent` and `detailContent`. Preserve pane identity and sheet mounting across folds. Select `CalendarContentViewTests`, `CalendarMonthAccessibilityTests`, `CalendarZoomTransitionStateTests`, `LocationsViewTests`, `PresenceTimelineListTests` and their affected owning snapshots. See [Primary source contract](../../Where/WhereUI/Sources/Primary/AGENTS.md). |
| Tabs, launch and onboarding | Reconcile `RootView.swift`, `MainTabs.swift`, `Launch/`, `Compatibility/` and `Onboarding/` under WhereUI. Root owns compatibility gating and launch identity; MainTabs owns selection, destination and scene reporting. Review each branch of the 82-line `rootContent` and each Onboarding page with its mounted model. Use `MainTabsTests`, `WhereCompatibilityModelTests`, `RootViewSnapshotTests`, `DataCompatibilityViewSnapshotTests` and `OnboardingViewSnapshotTests` as applicable. |
| System hosts and remaining Where files | Assign source and fixtures outside WhereUI by app/extension. Keep the snippet's 10-line `Button(intent:)` whole and the availability decision in the snippet. Validate a changed snippet via Siri/Shortcuts under [WhereIntents guidance](../../Where/WhereIntents/AGENTS.md). Widget entry/family ownership remains at the host; pair shared image coverage with the [widget host](../../Where/WhereWidgets/AGENTS.md). Confirm share save and cancel via the system sheet under [share extension guidance](../../Where/WhereShareExtension/AGENTS.md). Check the RegionViewer window in its [documented Catalyst build](../../Where/RegionViewer/README.md#running-it). Record actual host evidence and any unavailable hardware. |

Apply each slice against its recorded parent. Format and remeasure its complete children, then exercise the named behavior and image suites through `./test --record never --only <bundle>/<suite>`. Compare any failure against the parent before publication. Resume with the first unverified slice and reconcile its paths against the original inventories.

### Year mode picker

The 17-line `YearModeButton` lives beside the 19-line picker and retains the complete button, hit shape, animation and selected trait. The screen owns the mode and the picker owns the namespace. The hosted Year test activated both modes across all supported fold layouts and confirmed selection and navigation-stack identity. Both Year snapshot tests passed with recording disabled. The next batch covers the eager calendar grid and scroll/zoom owner.

### Calendar grid and zoom

The month and day renderers retain their eager grid rows and stable scroll IDs. The calendar screen keeps both scroll positions, accessibility focus, the zoom transition and planning presentation. The shared calendar scroll view measures 113 lines in its own file. The complete overview month button is 20 lines in its own file. The zoom and planning toolbar controls stay beside their parent. The focused calendar content, month accessibility, snapshot readiness, zoom overlay and zoom transition suites passed, as did the calendar reference images with recording disabled.

### Locations

The Locations screen retains navigation, its selection, tilt provider, calendar namespace and mounted sheet bindings. Its complete 61-line region card button owns the transition, ranking geometry, tap target and accessibility. The compact navigator (20), content (22) and screen (31) have separate files. Both small state views share the screen file. The pane container kept module visibility because its preview and hosted test also construct it. The nine Locations and pane behavior suites passed, including selecting and clearing a pane, restoring scroll and keeping a flight review sheet mounted across folds. Locations snapshots passed with recording disabled.
