# 04 — Where screen composition and extension hosts

Status: outline

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

**Resume point.** When the pilot’s measured placements and verification are available, use the audit to select and detail the first Where composition batch.
