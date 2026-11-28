# Whole buttons

[Plan overview](README.md) · [Inline builder locations](audit.md#inline-review-locations) · [Audited source](https://github.com/kyleve/Stuff/tree/5b1747d01ddb5a3392d5b0499d6f5e3784613f01)

Use the complete interactive control as the child. Its action or intent, label, style, hit target, accessibility and disabled state travel together. Keep the presentation state and domain behavior with their existing owners and pass the child the values or action it needs. Preserve the placement of modifiers whose behavior depends on hierarchy, such as a confirmation dialog attached to a toolbar button or a matched transition source attached to a card.

## Scope and measurements

SwiftSyntax parsed all 1,615 tracked Swift files at `5b1747d01`. The pass found 217 explicit `Button` constructions. Each measurement starts at the constructor and ends at the last directly attached modifier. It counts nonblank, non-comment token lines across the full expression, including initializer arguments, action, label and branches. This includes title-, symbol-, role-, action- and intent-based overloads, including buttons whose individual closures fall below five lines. All observed call sites import SwiftUI.

| Complete expression | Buttons | Review |
| --- | ---: | --- |
| 1–4 lines | 106 | Below the extraction threshold. |
| 5–19 lines | 97 | A qualifying child belongs in the parent’s file. |
| 20+ lines | 14 | A qualifying child belongs in its own file. |

The 111 threshold hits span 72 files. Ten are the complete rendering expression of an existing named `View.body`, sometimes following local value declarations. Those rows identify the owning type. Review placement using that type’s whole formatted body. Other rows require source review for existing boundaries and framework contracts. The inline, helper and named-view indexes can refer to one constructor. Link its label, layouts and modifiers to the same complete control. Give every distinct constructor its own disposition, including nested buttons. In [EntityTableView.swift](../../Shared/Inspector/Sources/EntityTableView.swift#L66), the 26-line presenter at line 66 and the eight-line delete action at line 79 are separate controls. Verify the choices, roles and actions in the actual alert, dialog or menu host. If the host requires a native action at that site, record the contract and verification in the owning batch.

Two sites illustrate the intended change.

- `RegionPickerRegionRow` already renders the complete region-selection button. The control spans lines 221–254 (34 lines) and the full named body measures 39. Move `RegionPickerRegionRow` intact to its own source file. Retain its animated draft toggle, label, selectable hit area, accessibility state and disabled rule. The label at line 225 points inside the same extraction. [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift#L221)
- The inline Other Builds button spans lines 57–65 (9 lines). Give the entire button a named view in the page’s final file. Pass the existing sheet-opening action from `UpdatePage`, which owns its presentation state. [AppUpdatesView.swift](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L57)

The scan recognizes explicit constructors by syntax and follows directly chained member calls. It does not resolve inferred initializers or calls to custom controls. Review those controls through their implementations, callers and the [existing named view inventory](small-named-views.md). Use the actual formatted child body to decide its destination during implementation.

## Source index

Each link gives the constructor line and the measured size in parentheses. An owner beside the link marks an existing named body rendering the entire control.

### Shared/Flyover

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| FlyoverCanvasView.swift | [117 (7)](../../Shared/Flyover/Sources/FlyoverCanvasView.swift#L117) | — |
| FlyoverCompactControlBar.swift | [21 (6)](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift#L21) | — |
| FlyoverControlBar.swift | [19 (5)](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L19) | — |
| FlyoverScreenFrame.swift | [57 (5)](../../Shared/Flyover/Sources/FlyoverScreenFrame.swift#L57) | — |

### Shared/Inspector

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| EntityTableView.swift | [79 (8)](../../Shared/Inspector/Sources/EntityTableView.swift#L79), [200 (17)](../../Shared/Inspector/Sources/EntityTableView.swift#L200) | [66 (26)](../../Shared/Inspector/Sources/EntityTableView.swift#L66) |
| InspectorDefaultsView.swift | [115 (14)](../../Shared/Inspector/Sources/InspectorDefaultsView.swift#L115), [123 (5)](../../Shared/Inspector/Sources/InspectorDefaultsView.swift#L123) | — |
| InspectorSwiftDataView.swift | [52 (18)](../../Shared/Inspector/Sources/InspectorSwiftDataView.swift#L52) | — |
| InspectorUnavailableSwiftDataView.swift | — | [21 (22)](../../Shared/Inspector/Sources/InspectorUnavailableSwiftDataView.swift#L21) |
| InspectorView.swift | [72 (6)](../../Shared/Inspector/Sources/InspectorView.swift#L72), [85 (6)](../../Shared/Inspector/Sources/InspectorView.swift#L85) | — |
| RelationshipView.swift | [56 (6)](../../Shared/Inspector/Sources/RelationshipView.swift#L56) | — |
| RowDetailView.swift | [34 (13)](../../Shared/Inspector/Sources/RowDetailView.swift#L34), [71 (7)](../../Shared/Inspector/Sources/RowDetailView.swift#L71) | [63 (20)](../../Shared/Inspector/Sources/RowDetailView.swift#L63) |

### Shared/InstallerKitUI

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| AppUpdatesView.swift | [57 (9)](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L57) | — |
| UpdateCheckButton.swift | [10 (11)](../../Shared/InstallerKitUI/Sources/UpdateCheckButton.swift#L10) · `UpdateCheckButton` | — |

### Shared/Periscope/PeriscopeTools

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| LogInspectable.swift | [37 (14)](../../Shared/Periscope/PeriscopeTools/Sources/InspectMode/LogInspectable.swift#L37) | — |
| PeriscopeViewer.swift | [240 (5)](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L240), [245 (5)](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L245), [256 (14)](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L256) | — |

### Shared/SnapshotKitTesting

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| AccessibilitySnapshotViewControllerTests.swift | [173 (7)](../../Shared/SnapshotKitTesting/Tests/AccessibilitySnapshotViewControllerTests.swift#L173) | — |

### Where/WhereIntents

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| DaysInRegionSnippetIntent.swift | [89 (10)](../../Where/WhereIntents/Sources/DaysInRegionSnippetIntent.swift#L89) | — |

### Where/WhereShareExtension

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| ShareEvidenceView.swift | [46 (8)](../../Where/WhereShareExtension/Sources/ShareEvidenceView.swift#L46) | — |

### Where/WhereUI/Sources/Compatibility

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| DataCompatibilityView.swift | [84 (10)](../../Where/WhereUI/Sources/Compatibility/DataCompatibilityView.swift#L84), [95 (5)](../../Where/WhereUI/Sources/Compatibility/DataCompatibilityView.swift#L95), [118 (13)](../../Where/WhereUI/Sources/Compatibility/DataCompatibilityView.swift#L118) · `CompatibilityAppUpdatesButton` | — |

### Where/WhereUI/Sources/Developer

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| CardDesignerExportSection.swift | [26 (10)](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerExportSection.swift#L26), [50 (10)](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerExportSection.swift#L50) | — |
| CardDesignerPreview.swift | [20 (12)](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerPreview.swift#L20) | — |
| DeveloperCrashButton.swift | [29 (5)](../../Where/WhereUI/Sources/Developer/DeveloperCrashButton.swift#L29) | [12 (26)](../../Where/WhereUI/Sources/Developer/DeveloperCrashButton.swift#L12) · `DeveloperCrashButton` |
| DeveloperDemoLaunchSheet.swift | [89 (7)](../../Where/WhereUI/Sources/Developer/DeveloperDemoLaunchSheet.swift#L89) | — |
| DeveloperDemoModeRow.swift | — | [15 (26)](../../Where/WhereUI/Sources/Developer/DeveloperDemoModeRow.swift#L15) · `DeveloperDemoModeRow` |
| DeveloperInspectorModeRow.swift | — | [17 (26)](../../Where/WhereUI/Sources/Developer/DeveloperInspectorModeRow.swift#L17) · `DeveloperInspectorModeRow` |
| DeveloperOverlay.swift | [83 (6)](../../Where/WhereUI/Sources/Developer/DeveloperOverlay.swift#L83) | — |
| DeveloperOverlayButton.swift | [21 (16)](../../Where/WhereUI/Sources/Developer/DeveloperOverlayButton.swift#L21) · `DeveloperOverlayButton` | — |
| DeveloperSurface.swift | [27 (7)](../../Where/WhereUI/Sources/Developer/DeveloperSurface.swift#L27), [61 (10)](../../Where/WhereUI/Sources/Developer/DeveloperSurface.swift#L61) | — |
| DeveloperToolMenuButton.swift | [13 (14)](../../Where/WhereUI/Sources/Developer/DeveloperToolMenuButton.swift#L13) · `DeveloperToolMenuButton` | — |
| WhereFlyoverPresentationView.swift | [12 (9)](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverPresentationView.swift#L12) | — |
| RankingAnimationLabView.swift | [29 (6)](../../Where/WhereUI/Sources/Developer/RankingAnimation/RankingAnimationLabView.swift#L29) | — |
| RegionMapLegend.swift | [23 (6)](../../Where/WhereUI/Sources/Developer/RegionMapLegend.swift#L23) | — |

### Where/WhereUI/Sources/Devices

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| RemovedDeviceView.swift | [27 (10)](../../Where/WhereUI/Sources/Devices/RemovedDeviceView.swift#L27) | — |

### Where/WhereUI/Sources/Evidence

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| AddEvidenceView.swift | [50 (8)](../../Where/WhereUI/Sources/Evidence/AddEvidenceView.swift#L50), [94 (6)](../../Where/WhereUI/Sources/Evidence/AddEvidenceView.swift#L94), [101 (5)](../../Where/WhereUI/Sources/Evidence/AddEvidenceView.swift#L101) | — |
| EvidenceListView.swift | [46 (6)](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift#L46) | — |

### Where/WhereUI/Sources/Forecasting

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| LocationForecastControls.swift | [10 (11)](../../Where/WhereUI/Sources/Forecasting/LocationForecastControls.swift#L10) · `LocationForecastControls` | — |
| LocationForecastHeader.swift | [13 (16)](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeader.swift#L13) | — |
| PlannedStayEditor.swift | [92 (7)](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift#L92), [120 (8)](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift#L120) | — |
| PlannedStaysView.swift | [54 (5)](../../Where/WhereUI/Sources/Forecasting/PlannedStaysView.swift#L54), [100 (18)](../../Where/WhereUI/Sources/Forecasting/PlannedStaysView.swift#L100), [152 (12)](../../Where/WhereUI/Sources/Forecasting/PlannedStaysView.swift#L152) | — |
| PlanningRegionPickerView.swift | — | [57 (22)](../../Where/WhereUI/Sources/Forecasting/PlanningRegionPickerView.swift#L57) |

### Where/WhereUI/Sources/Manual

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| LoggedDaysView.swift | [59 (6)](../../Where/WhereUI/Sources/Manual/LoggedDaysView.swift#L59), [165 (6)](../../Where/WhereUI/Sources/Manual/LoggedDaysView.swift#L165) | — |
| ManualDayView.swift | [169 (6)](../../Where/WhereUI/Sources/Manual/ManualDayView.swift#L169) | — |

### Where/WhereUI/Sources/Onboarding

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| OnboardingThemeSelectionView.swift | [37 (6)](../../Where/WhereUI/Sources/Onboarding/OnboardingThemeSelectionView.swift#L37) | — |
| OnboardingView.swift | [207 (8)](../../Where/WhereUI/Sources/Onboarding/OnboardingView.swift#L207), [304 (8)](../../Where/WhereUI/Sources/Onboarding/OnboardingView.swift#L304) | — |

### Where/WhereUI/Sources/Primary

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| CalendarContentView.swift | [166 (12)](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L166), [182 (6)](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L182), [508 (13)](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L508), [525 (12)](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L525) | — |
| LocationWelcomeStatusAccessory.swift | — | [32 (20)](../../Where/WhereUI/Sources/Primary/LocationWelcomeStatusAccessory.swift#L32) |
| LocationsCardsView.swift | — | [75 (59)](../../Where/WhereUI/Sources/Primary/LocationsCardsView.swift#L75) |
| LocationsView.swift | [710 (6)](../../Where/WhereUI/Sources/Primary/LocationsView.swift#L710), [719 (7)](../../Where/WhereUI/Sources/Primary/LocationsView.swift#L719) | — |
| PresenceTimelineList.swift | [198 (6)](../../Where/WhereUI/Sources/Primary/PresenceTimelineList.swift#L198) | — |
| PresenceTimelineRows.swift | [136 (9)](../../Where/WhereUI/Sources/Primary/PresenceTimelineRows.swift#L136) · `EditableTimelinePlan`, [139 (5)](../../Where/WhereUI/Sources/Primary/PresenceTimelineRows.swift#L139) | — |
| RegionWelcomeCard.swift | [66 (11)](../../Where/WhereUI/Sources/Primary/RegionWelcomeCard.swift#L66) | [140 (28)](../../Where/WhereUI/Sources/Primary/RegionWelcomeCard.swift#L140) |

### Where/WhereUI/Sources/Regions

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| RegionCustomizeView.swift | [114 (10)](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift#L114), [132 (12)](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift#L132) | [78 (24)](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift#L78) |
| RegionPickerView.swift | — | [221 (34)](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift#L221) · `RegionPickerRegionRow` |

### Where/WhereUI/Sources/Resolution

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| AbruptChangeDetailView.swift | [52 (6)](../../Where/WhereUI/Sources/Resolution/AbruptChangeDetailView.swift#L52) | — |
| FlightDayDetailView.swift | [162 (10)](../../Where/WhereUI/Sources/Resolution/FlightDayDetailView.swift#L162) | — |
| FlightReviewPointRow.swift | [12 (12)](../../Where/WhereUI/Sources/Resolution/FlightReviewPointRow.swift#L12) | — |
| ResolutionView.swift | [192 (5)](../../Where/WhereUI/Sources/Resolution/ResolutionView.swift#L192) | — |

### Where/WhereUI/Sources/Settings

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| AlertsSettingsView.swift | [68 (8)](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L68), [111 (8)](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L111), [147 (8)](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L147), [192 (11)](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L192) | — |
| AppIconView.swift | [161 (13)](../../Where/WhereUI/Sources/Settings/AppIconView.swift#L161), [184 (9)](../../Where/WhereUI/Sources/Settings/AppIconView.swift#L184) | [113 (24)](../../Where/WhereUI/Sources/Settings/AppIconView.swift#L113) |
| AppearanceSettingsView.swift | [66 (8)](../../Where/WhereUI/Sources/Settings/AppearanceSettingsView.swift#L66), [106 (7)](../../Where/WhereUI/Sources/Settings/AppearanceSettingsView.swift#L106) | — |
| BackupSettingsSection.swift | [19 (15)](../../Where/WhereUI/Sources/Settings/BackupSettingsSection.swift#L19) | — |
| DataSettingsView.swift | [92 (18)](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift#L92), [123 (18)](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift#L123) | — |
| DeviceSettingsSection.swift | [25 (5)](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift#L25), [75 (8)](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift#L75), [86 (8)](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift#L86) | [96 (21)](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift#L96) |
| DiagnosticPersonalDataSection.swift | [20 (6)](../../Where/WhereUI/Sources/Settings/DiagnosticPersonalDataSection.swift#L20) | — |
| EstimatedTimeFeaturesView.swift | [107 (10)](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L107) | — |
| InsightsAccuracyFeaturesContent.swift | [35 (7)](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesContent.swift#L35) | — |
| PersonalizationFeaturesContent.swift | [39 (7)](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesContent.swift#L39), [60 (7)](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesContent.swift#L60) | — |
| SettingsContent.swift | [139 (8)](../../Where/WhereUI/Sources/Settings/SettingsContent.swift#L139) | — |

### Where/WhereUI/Sources/Shared

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| CardSurfaceButtonStyle.swift | [14 (5)](../../Where/WhereUI/Sources/Shared/CardSurfaceButtonStyle.swift#L14) | — |
| WhereThemePicker.swift | [37 (14)](../../Where/WhereUI/Sources/Shared/WhereThemePicker.swift#L37) | — |
| YearSelector.swift | [13 (9)](../../Where/WhereUI/Sources/Shared/YearSelector.swift#L13) | — |

### Where/WhereUI/Sources/Year

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| YearView.swift | [131 (16)](../../Where/WhereUI/Sources/Year/YearView.swift#L131) | — |
