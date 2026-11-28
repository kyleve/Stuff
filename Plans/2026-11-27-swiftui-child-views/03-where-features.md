# 03 — Extract WhereUI feature views

Status: `outline`

Depends on [01 — InstallerKitUI pilot](01-installer-pilot.md). The [shared modules](02-shared-modules.md) can proceed independently.

## Outcome and scope

Apply the [audited rule](audit.md) to Settings, Developer, Shared, Regions, Devices, Elsewhere, Evidence, Manual, Forecasting, Resolution, Intents and Widgets under `Where/WhereUI/Sources/`. Include Model, Logging, Preview and the feature-owned helpers and fixtures in WhereUI’s unit and snapshot suites. The next plan owns Primary, Year, RootView, MainTabs, Launch, Onboarding and Compatibility, including their fixtures.

The [overview](README.md) defines R-01 for named child placement, R-02 for behavior and ownership, and R-03 for audit dispositions and verification. X-01 excludes product and public API changes. X-02 excludes permanent lint. The source change introduces view types inside WhereUI and preserves the existing data flow, so a separate architecture diagram or interface proposal would add no detail.

## Proposed batches

Each batch should cover one independently testable surface. The examples locate the work at `5b1747d01`. Use the full index to select the rest.

| Start with | Evidence and behavior to preserve |
| --- | --- |
| Widgets, snippets and Settings galleries | `YearTotalsWidgetView.emptyContent` is 9 lines. `FeatureShareSheetPreview.shareSource` is exactly 20. Its inline `Group` at line 19 spans 37 lines with its frame. Recount enclosing views after extracting leaves. Preserve widget accessibility values and the gallery’s focus and reveal boundaries. |
| Settings navigation, data and device controls | `SettingsDestinationView` already has a name and shares a file with its parent. Its body is 72 lines. `SettingsContent.groupNavigationRow` is 6. Preserve typed destinations, search focus, sheet presenters, and the screen-owned export task and alert in `DataSettingsView`. |
| Region pickers, forecasting and editing | `RegionPickerView.swift` already contains `RegionPickerContent` (35 lines), `RegionPickerMessageRow` (26) and `RegionPickerRegionRow` (39). Process nested children first, recount each formatted body and place it accordingly. Preserve typed `Row.Message`, draft ownership and row identities. Split Manual, Evidence, Elsewhere and Resolution by editor or list, keeping stay IDs, confirmation state and accessible row actions with their current owners. |
| Shared controls and developer tools | Keep `WhereScreen.content` and modifier APIs callable. Inspect their rendered children. Keep drawing callbacks inside their canvases and screen registrations beside their represented types. `DeviceLayoutLabView.screen` and `preview` measure 25 and 46 lines. Preserve its model identity across layout changes and reset behavior. Tag capture fixtures such as `CoastMaps` separately from the live map. |

## Refinement and acceptance

Use the [small named view inventory](small-named-views.md) to identify existing single-parent children in separate files. Verify their current callers and entry points before choosing the owning file.

After the InstallerKitUI pilot lands, compare its final placements with the initial counts. Refresh the [audit index](audit.md) for the first feature batch at the implementation base. Inspect parent–child overlaps and current callers before choosing filenames or widening file-private access. Record the owning screen and suite for every remaining batch. Specific child names and batch order can follow the source at refinement.

Acceptance for each batch requires an outcome for every indexed site in its scope, including qualified inline children, existing named views and fixtures. Record the final body line count and file for extractions, or the reason a site already complies, is a protocol requirement or was absorbed by another extraction. Run the owning `WhereUITests` and `WhereUISnapshotTests` suites through `./test`, including gallery body-size guards, Settings search and the hosted device-layout reset case where affected. Exercise the touched presentation or editing path and its return. Investigate changed reference images against the existing design.

## Resume point

On November 27, 2026, source review identified the examples above and their guards. Implementation awaits authorization. At refinement, use the pilot’s verification record to select the first feature batch and expand this file into executable steps.
