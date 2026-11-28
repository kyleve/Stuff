# 04 — Where screen composition and extension hosts

Status: outline

Depends on [01 — Installer pilot](01-installer-pilot.md). See the [overview](README.md) for requirements and the [audit](audit.md) for source locations.

## Outcome and scope

Apply R-01 to WhereUI’s Primary, Year, Onboarding, Launch and Compatibility views, `MainTabs`, `RootView` and their previews, tests and fixtures. This plan also covers SwiftUI candidates in every Where module outside WhereUI, including the app, widgets, intents, share extension and RegionViewer. R-02 preserves observable lifetimes and host contracts. R-03 records the disposition and verification evidence for each reviewed surface. X-01 excludes product and public API changes. X-02 excludes permanent lint.

## Boundaries to review

| Area | Existing ownership and proposed extraction |
| --- | --- |
| Locations and Your Year | Start with the 166-line `CalendarContentView.calendarContent(months:)` and the 17-line `YearModePicker.segment(_:)`. Keep typed scroll targets, focus and the zoom namespace with their present owners. Keep pane navigation and presented sheets mounted across folds. `LocationsView.browsePane`, `expandedBrowseContent` and `detailContent(arrangement:)` already construct named types. Review those types’ bodies and placement before adding a wrapper. |
| Main tabs, launch and onboarding | Keep selection, the scene report, welcome model and planning destination on `MainTabs`. Review `RootView.rootContent(stylesheet:)` and `OnboardingView.introPages` by branch. Keep the outer compatibility lockout and the onboarding flow owner stable. The gate registry, tab-content builder and app runtime’s `makeRootView()` have their own contracts. Inspect the visual children they host. |
| App and system hosts | Review `YearTotalsWidgetContent`, `DaysInRegionInteractiveSnippet.content` and `ShareEvidenceView.attachmentRow(_:)`. Preserve widget family and compatibility branches, the intent-backed button, and share completion through the extension controller. Check the view inside RegionViewer’s `WindowGroup` against the threshold. Its `Scene` conformance belongs to the host. |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the pilot, reconcile these rows against the current checkout. Detail one mounted flow or host per batch. Use the pilot’s ownership sketch to identify each child’s inputs and actions, then remeasure enclosing views after formatting. At refinement, record which overlapping candidates collapse and which require their own file.

Use `./test` to select the relevant hosted and image suites. `CalendarContentViewTests`, `LocationsViewTestsDuo`, `YearViewTests` and `MainTabsTests` exercise navigation, selection and remounts. Pair them with the corresponding image suites. For launch and onboarding, include the compatibility and onboarding suites for the changed branches.

For host changes, exercise the widget family in its host, the snippet via Siri or Shortcuts on device, and share save/cancel from the system share sheet. WhereUI widget snapshots cover shared rendering. The share extension and RegionViewer have no hosted test bundle. Validate a changed RegionViewer shell with its documented Catalyst build. Record which host paths were actually exercised and any remaining limits alongside the final placements.

**Resume point.** When the pilot’s measured placements and verification are available, use the audit to select and detail the first Where composition batch.
