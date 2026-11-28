# 03 — Extract WhereUI feature views

**Status** · executing

Depends on [01 — InstallerKitUI pilot](01-installer-pilot.md). The [shared modules](02-shared-modules.md) can proceed independently.

## Outcome and scope

Apply the [audited rule](audit.md) to Settings, Developer, Shared, Regions, Devices, Elsewhere, Evidence, Manual, Forecasting, Resolution, Intents and Widgets under `Where/WhereUI/Sources/`. Include Model, Logging, Preview and the feature-owned helpers and fixtures in WhereUI’s unit and snapshot suites. The next plan owns Primary, Year, RootView, MainTabs, Launch, Onboarding and Compatibility, including their fixtures.

The [overview](README.md) defines R-01 for named child placement, R-02 for behavior and ownership, and R-03 for audit dispositions and verification. X-01 excludes product and public API changes. X-02 excludes permanent lint. The source change introduces view types inside WhereUI and preserves the existing data flow, so a separate architecture diagram or interface proposal would add no detail.

## Proposed batches

Each batch should cover one independently testable surface. The examples locate the work at `5b1747d01`. Use the full index to select the rest.

| Start with | Evidence and behavior to preserve |
| --- | --- |
| Widgets, snippets and Settings galleries | `YearTotalsWidgetView.emptyContent` is 9 lines. `FeatureShareSheetPreview.shareSource` is exactly 20. Its inline `Group` at line 19 spans 37 lines with its frame. Measure each complete rendered component with its attached modifiers. Preserve widget accessibility values and the gallery’s focus and reveal boundaries. |
| Settings navigation, data and device controls | `SettingsDestinationView` already has a name and shares a file with its parent. Its body is 72 lines. `SettingsContent.groupNavigationRow` is 6. Preserve typed destinations, search focus, sheet presenters, and the screen-owned export task and alert in `DataSettingsView`. |
| Region pickers, forecasting and editing | Move the existing 39-line `RegionPickerRegionRow` into `RegionPickerRegionRow.swift`. Its body prepares the display values and renders one button. Keep the animated draft toggle, full label, hit shape, selected trait, accessibility label/value/hint and capacity-based disabled state together. Review `RegionPickerContent` (35 lines) and `RegionPickerMessageRow` (26) separately. Keep typed `Row.Message`, draft ownership and row identities. [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift#L215) |
| Manual, Evidence, Elsewhere and Resolution | Split the work by editor or list. Keep stay IDs, confirmation state and presentation effects with their existing owners. A named row button should invoke the owner’s existing intent and include its label, role and button-specific modifiers. |
| Shared controls and developer tools | Keep `WhereScreen.content` and modifier APIs callable. Inspect their rendered children. Keep drawing callbacks inside their canvases and screen registrations beside their represented types. `DeviceLayoutLabView.screen` and `preview` measure 25 and 46 lines. Preserve its model identity across layout changes and reset behavior. Tag capture fixtures such as `CoastMaps` separately from the live map. |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the InstallerKitUI pilot lands, compare its final placements with the initial counts. Refresh the [audit index](audit.md) for the first feature batch at the implementation base. Inspect parent–child overlaps and current callers before choosing filenames or widening file-private access. Record the owning screen and suite for every remaining batch. Specific child names and batch order can follow the source at refinement.

Resolve every indexed site and every additional qualifying child found in the batch. Fix each confirmed extraction or placement issue and record the final type, file and body size. For overlapping hits, point the label and modifier locations to the named whole button that contains them. For other candidates, record the existing compliant view or the source contract that makes the site inapplicable.

Run the owning `WhereUITests` and `WhereUISnapshotTests` suites through `./test`. For the picker, use `PrimaryRegionSelectionModelTests` for tapping, search and selection persistence, and `RegionPickerViewSnapshotTests` for rendering. Check gallery body-size guards, Settings search and the hosted device-layout reset case where affected. Exercise the touched presentation or editing path and its return. Investigate changed reference images against the existing design.

## Execution and verification

Start under `Where/WhereUI/Sources`. Pair the listed behavior suites in `WhereUITests` with rendering suites in `WhereUISnapshotTests`.

| Slice | Source and acceptance |
| --- | --- |
| Primary region picker | In `Regions/RegionPickerView.swift`, existing `RegionPickerContent` (35), `RegionPickerMessageRow` (26) and `RegionPickerRegionRow` (39) start above the own-file threshold. Move qualifying types after measuring complete children, preserving the entire region selection button, disabled state and accessibility. The picker root mounts `RegionPickerModel`; content keeps row identities, the binding and native disclosure behavior. Inspect the country row's current 5-line body together with its 13-line label. Measure its assembled disclosure in context. Preserve the typed message model and root preview mounts. Exercise `PrimaryRegionSelectionModelTests.hostedPickerSelectsAndReopensTwoProvinces`, `hostedPickerKeepsSelectionsAndCountryExpansionThroughSearch` and `RegionPickerViewSnapshotTests`. Follow with the rest of `Regions/` including customization. |
| Editing, browsing and resolving | Give `Evidence/` and `Manual/` separate editor/detail/list slices. Preserve draft, save/cancel, presentation and deletion ownership. Check `AddEvidenceModelTests`, affected evidence list/detail suites, `ManualDayViewSnapshotTests` and `LoggedDaysViewSnapshotTests`. Split `Forecasting/`, `Elsewhere/` and `Resolution/` by native navigation flow. Use `PlannedStaysModelTests`, `PlanningRegionPickerViewSnapshotTests`, `LocationForecastPanelSnapshotTests`, `ElsewhereViewSnapshotTests` and `RegionDaysViewSnapshotTests` as applicable. Exercise return and editing in the mounted screen when model suites cover data alone. |
| Settings and developer UI | Split `Settings/FeaturePreviews/` galleries from navigation, About/Privacy, data/export, appearance and devices. Preserve gallery reveal/focus; Settings owns search, export task and presenters. Select `ShareEvidenceFeaturesViewTests`, `FeatureGuidePageTests` and the named snapshot suites for the affected gallery or Settings destination. In `Developer/`, separate CardDesigner from device/fold layout and tooling. Retain model identity across layout changes and explicit resets. Use `DeviceLayoutLabViewTests` and the affected developer fixtures. |
| Reusable components and fixtures | Assign `Shared/`, `Devices/`, `Widgets/`, `Intents/`, `Model/`, `Logging/` and `Preview/` by component or host. Preserve `WhereScreen.content`, style/modifier witnesses, Canvas and typed map builders. Use `WhereFormRootTests`, `WhereScreenRootTests` or the matching Today/YearTotals widget snapshot suite. Track test-only hosts with their rendered subject, including cross-feature fixtures. |

Apply each slice against its recorded parent. Format and remeasure its complete children, then exercise the named behavior and image suites through `./test --record never --only <bundle>/<suite>`. Compare any failure against the parent before publication. Resume with the first unverified slice and reconcile its paths against the original inventories.

### Primary region picker

The picker retains its typed rows, native list and per-visit model. The complete region-selection row has a 39-line body, including its 34-line button, in `RegionPickerRegionRow.swift`. The 35-line list lives in `RegionPickerContent.swift` beside its country disclosure (17), message row (19) and selection message (11). Search and empty previews stay with the public screen. At the pilot revision `d1f20b068`, the source review compared the selection control and row IDs with the originals. The focused run passed all 19 primary-region behavior tests, including select, commit, reopen, search and country expansion. The region picker snapshot suite passed with recording disabled.
