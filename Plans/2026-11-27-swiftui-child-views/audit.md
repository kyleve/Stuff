# Audit at 5b1747d01

[Plan overview](README.md) · [Declaration recount](recount.md) · [Audited source revision](https://github.com/kyleve/Stuff/tree/5b1747d01ddb5a3392d5b0499d6f5e3784613f01)

The scan parsed all 1,615 files returned by `git ls-files '*.swift'` with Xcode's SwiftParser and SwiftSyntax. It walked declarations, getter bodies, local functions, call arguments, ordinary and labeled trailing closures, and conditional branches in source-accurate mode. All files parsed without syntax errors. For each body it counted distinct nonblank physical lines occupied by Swift tokens inside the declaration or closure braces. Comments are trivia. Interior braces, directives, branches and modifier lines count. New types use their final SwiftFormat layout.

[Helpers](#helpers) · [Preserved declarations](#preserved-declaration-boundaries) · [Concrete result types](#concrete-result-types) · [Already-named views](#already-named-views) · [Inline locations](#inline-review-locations)

## Helpers

There are 208 non-`body` methods or computed properties explicitly returning `some View` with five or more lines. Removing eight modifier APIs on `View`, three style witnesses named `makeBody` and three `WhereScreen.content` witnesses leaves **194 candidates in 88 files**. Entries give the declaration or attribute line followed by the baseline body size in parentheses. Inspect the accepted child inside any preserved witness. The two size columns guide placement after nested children have been addressed. Preview factories and test helpers are included.

### Shared/Flyover

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [FlyoverConnectorCanvas.swift](../../Shared/Flyover/Sources/FlyoverConnectorCanvas.swift) | — | `connector` 25 (39) |

### Shared/Inspector

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [EntityTableView.swift](../../Shared/Inspector/Sources/EntityTableView.swift) | `table` 166 (13), `headerRow` 182 (11), `cellRow` 199 (17), `footerBar` 223 (18) | `content` 139 (24) |
| [InspectorDefaultsView.swift](../../Shared/Inspector/Sources/InspectorDefaultsView.swift) | — | `editor` 146 (20) |
| [InspectorFileBrowserView.swift](../../Shared/Inspector/Sources/InspectorFileBrowserView.swift) | — | `content` 70 (29) |
| [InspectorSwiftDataView.swift](../../Shared/Inspector/Sources/InspectorSwiftDataView.swift) | `emptyState` 88 (9) | — |
| [InspectorView.swift](../../Shared/Inspector/Sources/InspectorView.swift) | — | `inspector` 37 (69), `detail` 115 (31) |
| [RelationshipView.swift](../../Shared/Inspector/Sources/RelationshipView.swift) | — | `content` 49 (27) |

### Shared/InstallerKitUI

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [AppUpdatesView.swift](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift) | `installAction` 84 (13) | `availability` 100 (34) |
| [InstallerBrowserPreview.swift](../../Shared/InstallerKitUI/Sources/InstallerBrowserPreview.swift) | `navigation` 144 (5) | — |
| [UpdateBrowserView.swift](../../Shared/InstallerKitUI/Sources/UpdateBrowserView.swift) | `destination` 11 (6) | — |
| [UpdateBuildRow.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildRow.swift) | `version` 59 (5) | — |
| [UpdateBuildSummary.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildSummary.swift) | `metric` 41 (12) | — |
| [UpdateHero.swift](../../Shared/InstallerKitUI/Sources/UpdateHero.swift) | `artwork` 37 (14) | — |
| [UpdateInstalledBuild.swift](../../Shared/InstallerKitUI/Sources/UpdateInstalledBuild.swift) | `commit` 51 (6) | — |

### Shared/LifecycleKitUI

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [LifecycleContainer.swift](../../Shared/LifecycleKitUI/Sources/LifecycleContainer.swift) | `phaseContent` 243 (11), `launchSurface` 307 (17), `gateView` 341 (13) | — |

### Shared/Periscope/PeriscopeTools

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [LogEventDetailView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Components/LogEventDetailView.swift) | `ambientContent` 144 (17), `attachmentsContent` 165 (13) | — |
| [LogHierarchyView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/LogHierarchyView.swift) | — | `content` 34 (32) |
| [ScopeEventsView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/ScopeEventsView.swift) | — | `content` 54 (24) |
| [LogInspectable.swift](../../Shared/Periscope/PeriscopeTools/Sources/InspectMode/LogInspectable.swift) | — | `content` 112 (23) |
| [OpenSpansView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/OpenSpansView.swift) | `content` 28 (12) | — |
| [SpanHistoryView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanHistoryView.swift) | `scopeMenu` 46 (9) | `content` 59 (36) |
| [SpanTreeView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanTreeView.swift) | `status` 107 (14) | `content` 37 (32) |
| [LogTraceView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Tracer/LogTraceView.swift) | — | `content` 58 (22) |
| [PeriscopeViewer.swift](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift) | `content` 138 (8), `spansMenu` 238 (14), `exportButton` 255 (14) | `logsList` 151 (38), `filterMenu` 192 (41) |

### Shared/SnapshotKit

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [SnapshotCase.swift](../../Shared/SnapshotKit/Sources/SnapshotCase.swift) | `framed` 195 (16) | — |

### Where/WhereIntents/Sources

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [DaysInRegionSnippetIntent.swift](../../Where/WhereIntents/Sources/DaysInRegionSnippetIntent.swift) | `content` 84 (16) | — |

### Where/WhereShareExtension/Sources

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [ShareEvidenceView.swift](../../Where/WhereShareExtension/Sources/ShareEvidenceView.swift) | `attachmentSection` 98 (13), `attachmentRow` 114 (13) | `form` 69 (25) |

### Where/WhereUI/Sources

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [RootView.swift](../../Where/WhereUI/Sources/RootView.swift) | — | `rootContent` 121 (82) |

### Where/WhereUI/Sources/Developer

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [DeveloperOverlay.swift](../../Where/WhereUI/Sources/Developer/DeveloperOverlay.swift) | — | `panel` 279 (33) |
| [DeveloperToolView.swift](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift) | — | `toolContent` 32 (38) |
| [DeviceLayoutLabView.swift](../../Where/WhereUI/Sources/Developer/DeviceLayout/DeviceLayoutLabView.swift) | `deviceOptions` 59 (10) | `screen` 75 (25), `preview` 103 (46) |
| [RegionMapLegend.swift](../../Where/WhereUI/Sources/Developer/RegionMapLegend.swift) | `row` 38 (18) | — |
| [RegionMapView.swift](../../Where/WhereUI/Sources/Developer/RegionMapView.swift) | `kindPicker` 45 (7), `map` 86 (9), `legend` 98 (8) | `stateContent` 56 (27) |

### Where/WhereUI/Sources/Elsewhere

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [DayRelabelView.swift](../../Where/WhereUI/Sources/Elsewhere/DayRelabelView.swift) | `reasonBanner` 154 (19), `banner` 176 (11) | `form` 100 (41) |
| [ElsewhereView.swift](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift) | `emptyState` 148 (5) | `screen` 75 (65) |
| [RegionDaysView.swift](../../Where/WhereUI/Sources/Elsewhere/RegionDaysView.swift) | — | `content` 63 (55) |

### Where/WhereUI/Sources/Evidence

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [AddEvidenceView.swift](../../Where/WhereUI/Sources/Evidence/AddEvidenceView.swift) | `attachmentSummary` 115 (13), `detailsSection` 131 (12), `noteSection` 146 (11) | `attachmentSection` 90 (22) |
| [EvidenceBlobPreview.swift](../../Where/WhereUI/Sources/Evidence/EvidenceBlobPreview.swift) | `imagePreview` 36 (10), `textPreview` 50 (8), `unavailable` 64 (5), `failedToDecode` 72 (5) | — |
| [EvidenceDetailView.swift](../../Where/WhereUI/Sources/Evidence/EvidenceDetailView.swift) | `noAttachment` 95 (5) | `header` 48 (20), `preview` 72 (20) |
| [EvidenceListView.swift](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift) | `content` 74 (17), `list` 94 (8), `emptyState` 107 (7) | — |

### Where/WhereUI/Sources/Forecasting

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [PlannedStayEditor.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift) | — | `destinationSection` 142 (35) |
| [PlannedStaysView.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStaysView.swift) | `stayRow` 151 (12) | `gapSection` 98 (48) |
| [PlanningRegionPickerView.swift](../../Where/WhereUI/Sources/Forecasting/PlanningRegionPickerView.swift) | — | `regionRow` 56 (22) |

### Where/WhereUI/Sources/Intents

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [IntentSnippets.swift](../../Where/WhereUI/Sources/Intents/IntentSnippets.swift) | `chips` 128 (13), `emptyState` 144 (8) | — |

### Where/WhereUI/Sources/Launch

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [LaunchSplashView.swift](../../Where/WhereUI/Sources/Launch/LaunchSplashView.swift) | `captionView` 153 (10), `background` 168 (7), `icon` 178 (16) | — |

### Where/WhereUI/Sources/Manual

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [LoggedDaysView.swift](../../Where/WhereUI/Sources/Manual/LoggedDaysView.swift) | `content` 105 (17), `loaded` 128 (18), `noMatchesState` 150 (9), `list` 162 (15), `emptyState` 180 (7) | — |
| [ManualDayView.swift](../../Where/WhereUI/Sources/Manual/ManualDayView.swift) | `regionsSection` 220 (18), `noteSection` 277 (13), `savingSection` 294 (5) | `addContent` 124 (21), `editContent` 154 (23), `datePickers` 190 (24) |

### Where/WhereUI/Sources/Onboarding

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [OnboardingView.swift](../../Where/WhereUI/Sources/Onboarding/OnboardingView.swift) | `introScreen` 107 (10), `pageView` 184 (17), `introFooter` 205 (15), `pickRegions` 231 (10), `customize` 246 (7) | `introPages` 127 (51), `location` 258 (65) |

### Where/WhereUI/Sources/Primary

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [CalendarContentView.swift](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift) | `calendarLayoutError` 197 (10), `zoomTile` 458 (18), `monthView` 492 (7), `overviewMonth` 506 (14), `overviewEstimate` 523 (13) | `calendarContent` 210 (166) |
| [CalendarSnapshotCases.swift](../../Where/WhereUI/Sources/Primary/CalendarSnapshotCases.swift) | `build` 74 (5) | — |
| [LocationsBackground.swift](../../Where/WhereUI/Sources/Primary/LocationsBackground.swift) | — | `silhouettes` 44 (21) |
| [LocationsStateContent.swift](../../Where/WhereUI/Sources/Primary/LocationsStateContent.swift) | `emptyState` 35 (14), `elsewhereOnlyState` 52 (19) | — |
| [LocationsView.swift](../../Where/WhereUI/Sources/Primary/LocationsView.swift) | — | `screen` 412 (31) |
| [MonthGridView.swift](../../Where/WhereUI/Sources/Primary/MonthGridView.swift) | `monthHeading` 80 (6), `planningSummaryRow` 165 (18) | `monthSummary` 90 (30), `dayGrid` 125 (36), `row` 334 (27), `dots` 479 (20), `stayPill` 508 (48) |
| [RegionSummaryCard.swift](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift) | `entryStamp` 183 (9) | `stampPaper` 199 (55), `content` 304 (95) |

### Where/WhereUI/Sources/Regions

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [RegionCustomizeView.swift](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift) | `preview` 42 (9), `section` 54 (6), `emojiGrid` 110 (15), `symbolGrid` 128 (17), `selectionBackground` 148 (11) | `colorGrid` 74 (29) |
| [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift) | `label` 190 (13) | — |
| [RegionsSettingsView.swift](../../Where/WhereUI/Sources/Regions/RegionsSettingsView.swift) | `regionRow` 117 (11), `destinationView` 134 (11) | `overview` 73 (40) |

### Where/WhereUI/Sources/Resolution

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [AbruptChangeDetailView.swift](../../Where/WhereUI/Sources/Resolution/AbruptChangeDetailView.swift) | `daySummary` 81 (6) | — |
| [ResolutionView.swift](../../Where/WhereUI/Sources/Resolution/ResolutionView.swift) | `reviewLink` 139 (12) | `screen` 49 (43), `issueList` 98 (38), `destination` 202 (20) |

### Where/WhereUI/Sources/Settings

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [AboutSettingsView.swift](../../Where/WhereUI/Sources/Settings/AboutSettingsView.swift) | `dependenciesSection` 100 (6), `developmentToolsSection` 111 (6), `dataSourcesSection` 166 (10) | `versionSection` 73 (20), `creditSection` 120 (22), `dataSourceRow` 179 (25) |
| [AlertsSettingsView.swift](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift) | `dataResolutionSection` 170 (17) | `remindersSection` 52 (28), `summarySection` 92 (31), `issueAlertsSection` 135 (24), `findIssuesSection` 190 (29) |
| [AppIconView.swift](../../Where/WhereUI/Sources/Settings/AppIconView.swift) | `grids` 84 (12), `scrim` 140 (8), `previewIcon` 221 (12) | `cell` 106 (26), `previewPanel` 151 (60) |
| [DataSettingsView.swift](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift) | — | `dataSection` 90 (24), `resetSection` 121 (22) |
| [EstimatedTimeFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift) | `preview` 132 (10), `explanation` 149 (9) | — |
| [FeatureEvidenceArchivePreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureEvidenceArchivePreview.swift) | `archiveRow` 51 (17), `archiveIcon` 71 (5), `archiveText` 79 (8) | — |
| [FeatureShareSheetPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureShareSheetPreview.swift) | — | `shareSource` 76 (20) |
| [InsightsAccuracyFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesContent.swift) | `actionLabel` 82 (7) | — |
| [FeatureRegionStylePreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/FeatureRegionStylePreview.swift) | `surface` 59 (16) | — |
| [PersonalizationFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesContent.swift) | `actionLabel` 104 (7) | — |
| [SiriChatBubble.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriChatBubble.swift) | `speakerIcon` 42 (11) | — |
| [LicenseView.swift](../../Where/WhereUI/Sources/Settings/LicenseView.swift) | `header` 23 (11), `notice` 38 (9) | — |
| [PrivacyDiagnosticsSettingsView.swift](../../Where/WhereUI/Sources/Settings/PrivacyDiagnosticsSettingsView.swift) | `pendingRow` 98 (6) | — |
| [PrivacyPassportCardSurface.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportCardSurface.swift) | — | `printedContent` 45 (23) |
| [SettingsContent.swift](../../Where/WhereUI/Sources/Settings/SettingsContent.swift) | `demoSection` 137 (14), `groupNavigationRow` 164 (6), `searchNavigationRow` 175 (6), `groupRow` 201 (12), `searchRow` 238 (13) | `recordingWarningSection` 108 (20) |
| [SettingsView.swift](../../Where/WhereUI/Sources/Settings/SettingsView.swift) | `snapshotList` 296 (6) | — |

### Where/WhereUI/Sources/Shared

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [RecordedPointsMap.swift](../../Where/WhereUI/Sources/Shared/RecordedPointsMap.swift) | — | `captureSurface` 93 (65) |
| [TiltSheen.swift](../../Where/WhereUI/Sources/Shared/TiltSheen.swift) | — | `sheen` 52 (26) |
| [WhereDatePicker.swift](../../Where/WhereUI/Sources/Shared/WhereDatePicker.swift) | `row` 131 (7) | `livePicker` 57 (24) |
| [WhereThemePicker.swift](../../Where/WhereUI/Sources/Shared/WhereThemePicker.swift) | `options` 35 (16) | — |

### Where/WhereUI/Sources/Widgets

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [TodayWidgetView.swift](../../Where/WhereUI/Sources/Widgets/TodayWidgetView.swift) | `heroRegion` 61 (13), `regionList` 78 (15), `emptyContent` 96 (9) | — |
| [WidgetCompatibilityView.swift](../../Where/WhereUI/Sources/Widgets/WidgetCompatibilityView.swift) | `homeContent` 57 (16) | `content` 34 (20) |
| [YearTotalsWidgetView.swift](../../Where/WhereUI/Sources/Widgets/YearTotalsWidgetView.swift) | `rows` 53 (18), `emptyContent` 74 (9) | — |

### Where/WhereUI/Sources/Year

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [YearView.swift](../../Where/WhereUI/Sources/Year/YearView.swift) | `segment` 129 (17) | — |

### Where/WhereUI/Tests

| Source | 5–19 lines | 20+ lines |
| --- | --- | --- |
| [CalendarZoomOverlayTests.swift](../../Where/WhereUI/Tests/CalendarZoomOverlayTests.swift) | `overlay` 31 (6) | — |
| [PresenceTimelineListTests.swift](../../Where/WhereUI/Tests/PresenceTimelineListTests.swift) | `timeline` 79 (12) | — |
| [RegionArtworkTaskTests.swift](../../Where/WhereUI/Tests/RegionArtworkTaskTests.swift) | `content` 105 (6) | — |
| [WhereFormRootTests.swift](../../Where/WhereUI/Tests/WhereFormRootTests.swift) | `rows` 132 (5) | — |

## Preserved declaration boundaries

These are the 14 threshold hits removed from the helper tally. Walk their rendered children with the same rule.

- [SnapshotLayoutTraits.swift](../../Shared/SnapshotKit/Sources/SnapshotLayoutTraits.swift) — `snapshotLayoutTraits` 74 (10)
- [SnapshotTraits.swift](../../Shared/SnapshotKit/Sources/SnapshotTraits.swift) — `snapshotTraits` 11 (10)
- [DeveloperLogInspection.swift](../../Where/WhereUI/Sources/Developer/DeveloperLogInspection.swift) — `debugLogInspectable` 16 (5)
- [DeveloperTabBarInset.swift](../../Where/WhereUI/Sources/Developer/DeveloperTabBarInset.swift) — `reportingDeveloperTabBarInset` 9 (5)
- [LocationForecastEndorsementButtonStyle.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastEndorsementButtonStyle.swift) — `makeBody` 11 (18)
- [LocationCardOvertakeModifier.swift](../../Where/WhereUI/Sources/Primary/LocationCardOvertakeModifier.swift) — `locationCardOvertakeEffect` 91 (5)
- [LocationCardsReconciliationModifier.swift](../../Where/WhereUI/Sources/Primary/LocationCardsReconciliationModifier.swift) — `reconcilesLocationCards` 123 (7)
- [RegionCustomizeView.swift](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift) — `content` 24 (14)
- [LicenseView.swift](../../Where/WhereUI/Sources/Settings/LicenseView.swift) — `content` 13 (7)
- [SettingsRow.swift](../../Where/WhereUI/Sources/Settings/SettingsRow.swift) — `settingsRow` 38 (5)
- [CardSurfaceButtonStyle.swift](../../Where/WhereUI/Sources/Shared/CardSurfaceButtonStyle.swift) — `makeBody` 9 (10), `makeBody` 27 (7)
- [TiltSheen.swift](../../Where/WhereUI/Sources/Shared/TiltSheen.swift) — `tiltSheen` 98 (8)
- [WhereScreenRootTests.swift](../../Where/WhereUI/Tests/WhereScreenRootTests.swift) — `content` 143 (12)

## Concrete result types

The scan also inspected results spelled with a concrete view type. In [LocationsView.swift](../../Where/WhereUI/Sources/Primary/LocationsView.swift), `browsePane` at 214 (8), `expandedBrowseContent` at 225 (11) and `detailContent` at 239 (6) construct existing named views. Keep the typed destinations and inspect their own bodies. [CalendarContentViewSnapshotTests.makeCalendar](../../Where/WhereUI/SnapshotTests/CalendarContentViewSnapshotTests.swift#L20) is a fixture factory returning an existing screen. [RegularApplicationRuntime.makeRootView](../../Where/Where/Sources/RegularApplicationRuntime.swift#L261) selects and erases an application root. Token colors, drawing paths and snapshot case factories have their own value semantics. A view conformance alone does not make a value a presentation child.

## Already-named views

These 34 bodies reach 20 lines in a file named for a different type. Call-site review identified 27 runtime children and seven preview, capture or test renderers. The latter are marked *fixture*. Inspect private dependencies and callers, extract inner children, then measure the named body again. Each line points to the body declaration. The [small named views](small-named-views.md) index examines the reverse placement question for independent files.

### Shared/Flyover

| Source | Named view · body line (size) |
| --- | --- |
| [FlyoverScreenFrame.swift](../../Shared/Flyover/Sources/FlyoverScreenFrame.swift) | `FlyoverScreenPlaceholder` 44 (21) |

### Shared/Inspector

| Source | Named view · body line (size) |
| --- | --- |
| [InspectorDefaultsView.swift](../../Shared/Inspector/Sources/InspectorDefaultsView.swift) | `InspectorDefaultEditorView` 104 (38) |
| [InspectorFileBrowserView.swift](../../Shared/Inspector/Sources/InspectorFileBrowserView.swift) | `FileItemView` 184 (42), `InspectorFileDetailView` 247 (23) |
| [InspectorPreviewData.swift](../../Shared/Inspector/Sources/InspectorPreviewData.swift) | `RowDetailPreviewHost` 154 (20) *fixture*, `RelationshipPreviewHost` 185 (26) *fixture* |

### Shared/InstallerKitUI

| Source | Named view · body line (size) |
| --- | --- |
| [AppUpdatesView.swift](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift) | `UpdatePage` 51 (30) |

### Shared/Periscope/PeriscopeTools

| Source | Named view · body line (size) |
| --- | --- |
| [LogInspectable.swift](../../Shared/Periscope/PeriscopeTools/Sources/InspectMode/LogInspectable.swift) | `LogInspectorView` 86 (22) |
| [OpenSpansView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/OpenSpansView.swift) | `OpenSpanRow` 59 (24) |
| [SpanHistoryView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanHistoryView.swift) | `SpanKindRow` 109 (28) |
| [SpanTreeView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanTreeView.swift) | `SpanTreeRow` 80 (21) |

### Shared/SnapshotKitTesting

| Source | Named view · body line (size) |
| --- | --- |
| [SnapshotImageRenderingTests.swift](../../Shared/SnapshotKitTesting/Tests/SnapshotImageRenderingTests.swift) | `NativeBarGeometryFixture` 322 (48) *fixture* |

### Where/WhereUI/Sources/Developer

| Source | Named view · body line (size) |
| --- | --- |
| [DeveloperToast.swift](../../Where/WhereUI/Sources/Developer/DeveloperToast.swift) | `DeveloperToastBanner` 99 (26) |
| [DuoLayoutSnapshotFixture.swift](../../Where/WhereUI/Sources/Developer/DuoLayout/DuoLayoutSnapshotFixture.swift) | `DuoLayoutSnapshotScene` 82 (28) *fixture* |
| [RegionMapView.swift](../../Where/WhereUI/Sources/Developer/RegionMapView.swift) | `CoastMaps` 350 (20) *fixture* |

### Where/WhereUI/Sources/Elsewhere

| Source | Named view · body line (size) |
| --- | --- |
| [RegionDaysView.swift](../../Where/WhereUI/Sources/Elsewhere/RegionDaysView.swift) | `DayRow` 137 (24) |

### Where/WhereUI/Sources/Evidence

| Source | Named view · body line (size) |
| --- | --- |
| [EvidenceListView.swift](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift) | `EvidenceRow` 146 (25) |

### Where/WhereUI/Sources/Intents

| Source | Named view · body line (size) |
| --- | --- |
| [IntentSnippets.swift](../../Where/WhereUI/Sources/Intents/IntentSnippets.swift) | `DaysInRegionSnippetView` 39 (20) |

### Where/WhereUI/Sources/Launch

| Source | Named view · body line (size) |
| --- | --- |
| [LaunchSplashView.swift](../../Where/WhereUI/Sources/Launch/LaunchSplashView.swift) | `RadarPingBackground` 220 (22) |

### Where/WhereUI/Sources/Manual

| Source | Named view · body line (size) |
| --- | --- |
| [LoggedDaysView.swift](../../Where/WhereUI/Sources/Manual/LoggedDaysView.swift) | `LoggedDayRow` 237 (32) |

### Where/WhereUI/Sources/Primary

| Source | Named view · body line (size) |
| --- | --- |
| [CalendarZoomOverlay.swift](../../Where/WhereUI/Sources/Primary/CalendarZoomOverlay.swift) | `CalendarZoomFlight` 43 (48) |
| [MonthGridView.swift](../../Where/WhereUI/Sources/Primary/MonthGridView.swift) | `DayCell` 383 (50) |
| [RegionOutlineSecurityBorder.swift](../../Where/WhereUI/Sources/Primary/RegionOutlineSecurityBorder.swift) | `RegionOutlineSecurityBorderPreview` 216 (20) *fixture* |
| [RegionSummaryCard.swift](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift) | `EntryStamp` 468 (51) |

### Where/WhereUI/Sources/Regions

| Source | Named view · body line (size) |
| --- | --- |
| [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift) | `RegionPickerContent` 30 (35), `RegionPickerMessageRow` 140 (26), `RegionPickerRegionRow` 215 (39) |

### Where/WhereUI/Sources/Resolution

| Source | Named view · body line (size) |
| --- | --- |
| [ResolutionView.swift](../../Where/WhereUI/Sources/Resolution/ResolutionView.swift) | `IssueRow` 175 (23) |

### Where/WhereUI/Sources/Settings

| Source | Named view · body line (size) |
| --- | --- |
| [EstimatedTimeFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift) | `EstimatedTimeFeaturesContent` 32 (89) |
| [SettingsView.swift](../../Where/WhereUI/Sources/Settings/SettingsView.swift) | `SettingsDestinationView` 143 (72) |

### Where/WhereUI/Sources/Shared

| Source | Named view · body line (size) |
| --- | --- |
| [RegionPolygonMap.swift](../../Where/WhereUI/Sources/Shared/RegionPolygonMap.swift) | `RegionMapCanvas` 256 (52) *fixture* |
| [WhereThemePicker.swift](../../Where/WhereUI/Sources/Shared/WhereThemePicker.swift) | `WhereThemeOption` 62 (40) |

### Where/WhereWidgets/Sources

| Source | Named view · body line (size) |
| --- | --- |
| [TodayWidget.swift](../../Where/WhereWidgets/Sources/TodayWidget.swift) | `TodayWidgetContent` 48 (22) |
| [YearTotalsWidget.swift](../../Where/WhereWidgets/Sources/YearTotalsWidget.swift) | `YearTotalsWidgetContent` 48 (34) |

## Local values and sibling expressions

A second pass inspected initializers of local bindings inside opaque view declarations and recognized view-building closures. Two decorated local values are direct extraction candidates. In [LocationCardEstimateSticker.swift](../../Where/WhereUI/Sources/Primary/LocationCardEstimateSticker.swift#L25), `sticker` measures 39 lines including its background and overlays. The adjacent `recorded` variable constructs the existing `LocationCardDayCount`. In [RegionSummaryCard.swift](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift#L305), `regionName` measures eight lines inside the larger `content` helper. Its typography, scaling and opacity belong with the proposed child. Local colors, paths, models and layout calculations retain their value roles.

The scan also found 30 qualifying direct sibling expressions in opaque view declarations outside the branch list. Each entry gives its start line and complete expression size. Some are multiline calls to already-named controls. Review the assembled sections and panels around those calls.

| Source | Sibling start line (size) |
| --- | --- |
| [CardDesignerEntryStampControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerEntryStampControls.swift) | 8 (6), 14 (6), 20 (14), 34 (32), 66 (34) |
| [CardDesignerMicroprintControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerMicroprintControls.swift) | 8 (6), 14 (6), 20 (6), 26 (6) |
| [CardDesignerVariantControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerVariantControls.swift) | 9 (46), 56 (25), 82 (8), 91 (11), 114 (31), 146 (28), 175 (47) |
| [ManualDayView.swift](../../Where/WhereUI/Sources/Manual/ManualDayView.swift) | 128 (17), 158 (6), 168 (10) |
| [PlacesYearFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PlacesYear/PlacesYearFeaturesContent.swift) | 11 (33), 44 (20), 64 (9), 73 (7) |
| [PrivacyBackupsFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PrivacyBackups/PrivacyBackupsFeaturesContent.swift) | 13 (7), 20 (8), 28 (7), 35 (7) |
| [RecordingFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Recording/RecordingFeaturesContent.swift) | 12 (9), 21 (7), 28 (7) |

## Inline review locations

The index below marks **1206 render-builder closures in 296 files** with at least five code lines between the braces, plus 335 qualifying expressions inside `if` or `switch` branches of identified builders or opaque view declarations. Each number is a source line. A single location may enclose several siblings, an already-named child, or preparation code. Choose a meaningful rendered expression and measure its complete body including attached modifiers. A closure count is a search aid. It cannot predict the number of files to create.

Names and argument roles were checked against call sites. For example, `Button(action:) { … }` supplies a label, `Button { … } label: { … }` supplies an action first, and `LifecycleContainer(gates:)` uses a separate builder. The map, toolbar and tab builders retain their result types. Individual labels, annotations, tab contents, toolbar-item contents and the view-based onboarding pager can still contain children. Preview and snapshot locations include their setup. Read the source before choosing a boundary.

SwiftSyntax supplies syntax without type checking. The closure table indexes known render APIs at this revision. Check concrete and inferred render values, local bindings, wrappers with a short closure and a long modifier chain, and unfamiliar builder overloads during the feature pass. For example, the closure in a test factory typed `() -> AnyView` at [RegionArtworkTaskTests.swift](../../Where/WhereUI/Tests/RegionArtworkTaskTests.swift#L55) includes model creation and must build anew per capture.


### Shared/Broadway/BroadwayCatalog

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [ContentView.swift](../../Shared/Broadway/BroadwayCatalog/Sources/ContentView.swift) | `NavigationStack` 7 | — |

### Shared/Broadway/BroadwayUI

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [BScrollPositionTests.swift](../../Shared/Broadway/BroadwayUI/Tests/BScrollPositionTests.swift) | `ScrollView` 287 | 201, 207 |

### Shared/Flyover

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [FlyoverSnapshotTests.swift](../../Shared/Flyover/SnapshotTests/FlyoverSnapshotTests.swift) | `FlyoverVariant` 101, 132 · `HStack` 179 · `List` 133 | — |
| [FlyoverAppearanceMenu.swift](../../Shared/Flyover/Sources/FlyoverAppearanceMenu.swift) | `Menu` 9 | — |
| [FlyoverCanvasView.swift](../../Shared/Flyover/Sources/FlyoverCanvasView.swift) | `ForEach` 68 · `GeometryReader` 53 · `ScrollView` 54 · `ZStack` 55 · `overlay` 116 | 72 |
| [FlyoverCompactControlBar.swift](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift) | `HStack` 12 · `ScrollView` 11 | — |
| [FlyoverConnectorCanvas.swift](../../Shared/Flyover/Sources/FlyoverConnectorCanvas.swift) | `ForEach` 11 · `ZStack` 10, 36 | — |
| [FlyoverControl.swift](../../Shared/Flyover/Sources/FlyoverControl.swift) | `FlyoverControl` 35, 64 · `LabeledContent` 36 | — |
| [FlyoverControlBar.swift](../../Shared/Flyover/Sources/FlyoverControlBar.swift) | `HStack` 12 · `ViewThatFits` 11 | — |
| [FlyoverDepthBandBackdrop.swift](../../Shared/Flyover/Sources/FlyoverDepthBandBackdrop.swift) | `VStack` 10 | — |
| [FlyoverExportContent.swift](../../Shared/Flyover/Sources/FlyoverExportContent.swift) | `Group` 10 | — |
| [FlyoverFocusedControls.swift](../../Shared/Flyover/Sources/FlyoverFocusedControls.swift) | `HStack` 12 · `ScrollView` 11 | — |
| [FlyoverFocusedVariantPicker.swift](../../Shared/Flyover/Sources/FlyoverFocusedVariantPicker.swift) | — | 12 |
| [FlyoverFocusedView.swift](../../Shared/Flyover/Sources/FlyoverFocusedView.swift) | `NavigationStack` 11 · `ScrollView` 12 | — |
| [FlyoverListView.swift](../../Shared/Flyover/Sources/FlyoverListView.swift) | `ForEach` 12, 14 · `LazyVStack` 11 · `ScrollView` 10 · `Section` 13 | — |
| [FlyoverRootView.swift](../../Shared/Flyover/Sources/FlyoverRootView.swift) | `Group` 11 | 15 |
| [FlyoverRouteSummary.swift](../../Shared/Flyover/Sources/FlyoverRouteSummary.swift) | `ForEach` 16 · `HStack` 15 | — |
| [FlyoverScreenContent.swift](../../Shared/Flyover/Sources/FlyoverScreenContent.swift) | `Group` 26 | — |
| [FlyoverScreenControls.swift](../../Shared/Flyover/Sources/FlyoverScreenControls.swift) | `ScrollView` 14 · `VStack` 15 | 17 |
| [FlyoverScreenFrame.swift](../../Shared/Flyover/Sources/FlyoverScreenFrame.swift) | `Group` 17 · `VStack` 14, 46 | — |
| [FlyoverScreenHeader.swift](../../Shared/Flyover/Sources/FlyoverScreenHeader.swift) | `HStack` 11 | — |
| [FlyoverViewportMenu.swift](../../Shared/Flyover/Sources/FlyoverViewportMenu.swift) | `Menu` 9 | — |
| [FlyoverZoomSlider.swift](../../Shared/Flyover/Sources/FlyoverZoomSlider.swift) | — | 10 |
| [FlyoverCanvasViewTests.swift](../../Shared/Flyover/Tests/FlyoverCanvasViewTests.swift) | `FlyoverVariant` 17 | — |

### Shared/Inspector

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [InspectorSnapshotTests.swift](../../Shared/Inspector/SnapshotTests/InspectorSnapshotTests.swift) | `NavigationStack` 20 | — |
| [EntityTableView.swift](../../Shared/Inspector/Sources/EntityTableView.swift) | `Button label` 202 · `ForEach` 184, 204 · `Group` 39 · `HStack` 183, 203, 224 · `LazyVStack` 168 · `ScrollView` 167 · `ToolbarItem` 65 · `VStack` 154 · `confirmationDialog` 78 | 141, 147, 154 |
| [InspectorDefaultsView.swift](../../Shared/Inspector/Sources/InspectorDefaultsView.swift) | `Form` 105 · `List` 13 · `NavigationLink label` 16 · `Section` 114 · `VStack` 17 · `confirmationDialog` 122 · `overlay` 30 | 32 |
| [InspectorFileBrowserView.swift](../../Shared/Inspector/Sources/InspectorFileBrowserView.swift) | `FileItemView destination` 83 · `Form` 248 · `Group` 36 · `Label` 186 · `List` 80 · `Menu` 52 · `NavigationLink` 185 · `Section` 249 · `ToolbarItem` 51 · `VStack` 187 · `swipeActions` 207 | 72, 80, 85 |
| [InspectorPreviewData.swift](../../Shared/Inspector/Sources/InspectorPreviewData.swift) | `NavigationStack` 134, 155, 186 | 188 |
| [InspectorSwiftDataView.swift](../../Shared/Inspector/Sources/InspectorSwiftDataView.swift) | `ForEach` 35 · `HStack` 106 · `List` 34 · `ToolbarItem` 51 | 90 |
| [InspectorUnavailableSwiftDataView.swift](../../Shared/Inspector/Sources/InspectorUnavailableSwiftDataView.swift) | `ContentUnavailableView actions` 17 · `confirmationDialog message` 34 | 21 |
| [InspectorView.swift](../../Shared/Inspector/Sources/InspectorView.swift) | `List` 39 · `NavigationSplitView` 38 · `Section` 40, 48, 56, 64 | 72, 79, 85, 141 |
| [RelationshipView.swift](../../Shared/Inspector/Sources/RelationshipView.swift) | `ForEach` 55 · `Group` 23 · `HStack` 99 · `List` 53 · `Section` 54 · `VStack` 100 | 53, 73, 104 |
| [RowDetailView.swift](../../Shared/Inspector/Sources/RowDetailView.swift) | `Button label` 36 · `ForEach` 33 · `HStack` 37 · `List` 23 · `Section` 32 · `ToolbarItem` 62 · `VStack` 103 · `confirmationDialog` 70 · `navigationDestination` 53 | 25, 32 |

### Shared/InstallerKitUI

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AppUpdatesView.swift](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift) | `UpdatePageLayout` 52 | 106, 112, 120, 127 |
| [UpdateBrowserPage.swift](../../Shared/InstallerKitUI/Sources/UpdateBrowserPage.swift) | `UpdatePageLayout` 11 | — |
| [UpdateBrowserView.swift](../../Shared/InstallerKitUI/Sources/UpdateBrowserView.swift) | `NavigationStack` 27 | — |
| [UpdateBuildInformation.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildInformation.swift) | `UpdateCard` 11 · `UpdateDetailRow` 13, 25 | — |
| [UpdateBuildRow.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildRow.swift) | `HStack` 18 · `VStack` 19 | — |
| [UpdateBuildSummary.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildSummary.swift) | `LazyVGrid` 11 · `UpdateCard` 10 · `VStack` 42 | — |
| [UpdateBuildView.swift](../../Shared/InstallerKitUI/Sources/UpdateBuildView.swift) | `NavigationLink` 36 · `UpdateBrowserPage` 13 · `UpdateHero` 18 | 15, 27, 36, 47, 52, 58 |
| [UpdateCard.swift](../../Shared/InstallerKitUI/Sources/UpdateCard.swift) | `VStack` 10 | — |
| [UpdateChanges.swift](../../Shared/InstallerKitUI/Sources/UpdateChanges.swift) | `ForEach` 33 · `HStack` 39 · `Link` 35 · `UpdateCard` 17 · `VStack` 43 | 33 |
| [UpdateChannelsView.swift](../../Shared/InstallerKitUI/Sources/UpdateChannelsView.swift) | `ForEach` 21 · `NavigationLink` 25 · `UpdateBrowserPage` 9 · `UpdateCard` 26 | 15, 21 |
| [UpdateCheckButton.swift](../../Shared/InstallerKitUI/Sources/UpdateCheckButton.swift) | `Button` 10 | — |
| [UpdateDetailRow.swift](../../Shared/InstallerKitUI/Sources/UpdateDetailRow.swift) | `layout` 13 | — |
| [UpdateFailureCard.swift](../../Shared/InstallerKitUI/Sources/UpdateFailureCard.swift) | `SnapshotCase` 34, 42 · `UpdateCard` 13 | — |
| [UpdateHero.swift](../../Shared/InstallerKitUI/Sources/UpdateHero.swift) | `VStack` 17 · `ZStack` 39 · `layout` 15 | — |
| [UpdateHistoryView.swift](../../Shared/InstallerKitUI/Sources/UpdateHistoryView.swift) | `ForEach` 19 · `NavigationLink` 24 · `UpdateBrowserPage` 11 · `UpdateCard` 25 | 19, 38 |
| [UpdateInstalledBuild.swift](../../Shared/InstallerKitUI/Sources/UpdateInstalledBuild.swift) | `UpdateCard` 10 · `UpdateDetailRow` 39 | 39 |
| [UpdateLocalBuildNotice.swift](../../Shared/InstallerKitUI/Sources/UpdateLocalBuildNotice.swift) | `UpdateCard` 10 | — |
| [UpdatePageLayout.swift](../../Shared/InstallerKitUI/Sources/UpdatePageLayout.swift) | `ScrollView` 9 | — |
| [UpdatePullRequestLink.swift](../../Shared/InstallerKitUI/Sources/UpdatePullRequestLink.swift) | — | 11 |
| [UpdateBrowserViewTestSupport.swift](../../Shared/InstallerKitUI/Tests/UpdateBrowserViewTestSupport.swift) | `NavigationStack` 26 | — |

### Shared/LifecycleKitUI

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [LifecycleContainer.swift](../../Shared/LifecycleKitUI/Sources/LifecycleContainer.swift) | `#Preview` 419 · `Group` 119 · `ZStack` 245 | 247, 319, 349 |
| [LifecycleFailureView.swift](../../Shared/LifecycleKitUI/Sources/LifecycleFailureView.swift) | `#Preview` 28 · `ContentUnavailableView` 15 | — |
| [LifecycleContainerTests.swift](../../Shared/LifecycleKitUI/Tests/LifecycleContainerTests.swift) | `LifecycleContainer splash` 225 · `PresentationVisibilityOverride` 259 | — |

### Shared/Periscope/PeriscopeTools

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [LogEventDetailView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Components/LogEventDetailView.swift) | `LabeledContent` 38 · `List` 21 · `Section` 22, 77 · `ToolbarItem` 102 | 38, 63, 77, 84, 155, 173 |
| [LogEventList.swift](../../Shared/Periscope/PeriscopeTools/Sources/Components/LogEventList.swift) | `List` 16 · `NavigationLink` 17 | — |
| [LogEventRow.swift](../../Shared/Periscope/PeriscopeTools/Sources/Components/LogEventRow.swift) | `HStack` 20 · `VStack` 19 | — |
| [LogHierarchyView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/LogHierarchyView.swift) | `HStack` 77 · `List` 52 · `NavigationLink` 54 · `OutlineGroup` 53 | 40, 46, 52 |
| [ScopeEventsView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/ScopeEventsView.swift) | — | 60, 66, 72 |
| [LogInspectable.swift](../../Shared/Periscope/PeriscopeTools/Sources/InspectMode/LogInspectable.swift) | `overlay` 35 | 37, 118, 124, 130 |
| [OpenSpansView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/OpenSpansView.swift) | `HStack` 63, 72 · `VStack` 62 | 31 |
| [SpanHistoryView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanHistoryView.swift) | `ForEach` 81 · `HStack` 113, 125 · `List` 79 · `Menu` 47 · `NavigationLink` 82 · `Section` 80 · `VStack` 112, 154 | 65, 71, 79 |
| [SpanTreeView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanTreeView.swift) | `HStack` 90 · `List` 55 · `NavigationLink` 57 · `OutlineGroup` 56 · `VStack` 83 | 43, 49, 55 |
| [LogTraceView.swift](../../Shared/Periscope/PeriscopeTools/Sources/Tracer/LogTraceView.swift) | `ForEach` 69 · `List` 34 · `NavigationLink` 70 | 69 |
| [PeriscopeViewer.swift](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift) | `ForEach` 170 · `List` 169 · `Menu` 194, 239 · `NavigationLink` 171 · `NavigationStack` 285 · `ScrollView` 286 · `ToolbarItem` 114 · `navigationDestination` 73 | 157, 163, 169 |
| [LogEventListTests.swift](../../Shared/Periscope/PeriscopeTools/Tests/LogEventListTests.swift) | `NavigationStack` 21 | — |

### Shared/SnapshotKit

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [SnapshotCase.swift](../../Shared/SnapshotKit/Sources/SnapshotCase.swift) | `ForEach` 160, 176 · `LazyVGrid` 175 · `VStack` 159, 161 | 172 |
| [SnapshotProviding.swift](../../Shared/SnapshotKit/Sources/SnapshotProviding.swift) | `ForEach` 41 · `ScrollView` 39 · `VStack` 40 | — |

### Shared/SnapshotKitTesting

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [SnapshotImageGrid.swift](../../Shared/SnapshotKitTesting/Sources/SnapshotImageGrid.swift) | `ForEach` 19, 24 · `Grid` 18 · `GridRow` 20 · `VStack` 25 | — |
| [AccessibilitySnapshotViewControllerTests.swift](../../Shared/SnapshotKitTesting/Tests/AccessibilitySnapshotViewControllerTests.swift) | `NavigationStack` 171 · `ScrollView` 172 | — |
| [LargeViewCaptureTests.swift](../../Shared/SnapshotKitTesting/Tests/LargeViewCaptureTests.swift) | `Form` 81 · `Grid` 200 · `NavigationStack` 270, 389 · `ScrollView` 199, 447 · `Section` 82 · `VStack` 356 | — |
| [SnapshotImageRenderingTests.swift](../../Shared/SnapshotKitTesting/Tests/SnapshotImageRenderingTests.swift) | `ForEach` 332 · `NavigationSplitView detail` 328 · `NavigationStack` 11, 329 · `ScrollView` 330 · `Tab` 324 · `VStack` 331 | — |

### Where/WhereIntents/Sources

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [DaysInRegionSnippetIntent.swift](../../Where/WhereIntents/Sources/DaysInRegionSnippetIntent.swift) | `Button` 89 · `DaysInRegionSnippetCard` 88 | 88 |

### Where/WhereShareExtension/Sources

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [ShareEvidenceView.swift](../../Where/WhereShareExtension/Sources/ShareEvidenceView.swift) | `#Preview` 132 · `Form` 72 · `Group` 29 · `HStack` 115 · `NavigationStack` 28 · `Section` 74, 85, 99 · `ToolbarItem` 45 | — |

### Where/WhereUI/SnapshotTests

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [WhereFlyoverWebExportTests.swift](../../Where/WhereUI/SnapshotTests/WhereFlyoverWebExportTests.swift) | `FlyoverVariant` 89 | — |

### Where/WhereUI/Sources

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [MainTabs.swift](../../Where/WhereUI/Sources/MainTabs.swift) | `Tab` 90, 115 · `Tab label` 122 · `overlay` 144 · `whereSnapshot` 385, 645 | 410 |
| [RootView.swift](../../Where/WhereUI/Sources/RootView.swift) | `#Preview` 336 · `GateView` 155 · `Group` 123 · `LifecycleContainer` 164 · `LifecycleContainer splash` 135 · `ZStack` 122 · `whereSnapshot` 302, 316 | 129, 175 |

### Where/WhereUI/Sources/Compatibility

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [DataCompatibilityView.swift](../../Where/WhereUI/Sources/Compatibility/DataCompatibilityView.swift) | `NavigationStack` 122 · `VStack` 53 · `sheet` 121 | 68, 84, 95 |

### Where/WhereUI/Sources/Developer

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [CardDesignerArtworkControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerArtworkControls.swift) | `#Preview` 23 · `Form` 25 | — |
| [CardDesignerArtworkLayerControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerArtworkLayerControls.swift) | `#Preview` 67 · `DisclosureGroup` 9 · `Form` 69 | 48, 54 |
| [CardDesignerCGFloatControl.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerCGFloatControl.swift) | `#Preview` 26 · `Form` 28 · `VStack` 11 | — |
| [CardDesignerDoubleControl.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerDoubleControl.swift) | `#Preview` 26 · `Form` 28 · `VStack` 11 | — |
| [CardDesignerEntryStampControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerEntryStampControls.swift) | `#Preview` 136 · `DisclosureGroup` 20, 34, 66, 102 | 102 |
| [CardDesignerExportSection.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerExportSection.swift) | `Button` 26, 50 · `Section` 12 | — |
| [CardDesignerFractionalTypographyControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerFractionalTypographyControls.swift) | `#Preview` 32 · `DisclosureGroup` 9 · `Form` 34 | — |
| [CardDesignerMicroprintControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerMicroprintControls.swift) | `#Preview` 35 · `Form` 37 | — |
| [CardDesignerPreview.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerPreview.swift) | `#Preview` 52 · `Button` 20 · `GlassEffectContainer` 19 | — |
| [CardDesignerSectionHeader.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSectionHeader.swift) | `#Preview` 19 · `HStack` 9 | — |
| [CardDesignerSecurityPrintControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSecurityPrintControls.swift) | `#Preview` 30 · `DisclosureGroup` 9 · `Form` 32 | — |
| [CardDesignerSharedControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSharedControls.swift) | `Section` 9 | — |
| [CardDesignerStudioView.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerStudioView.swift) | `ForEach` 71 · `Form` 41 · `Menu` 125 · `Picker` 43, 70 · `Section` 42 · `ToolbarItem` 124 · `VStack` 25 · `whereSnapshot` 175 | — |
| [CardDesignerTypographyControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerTypographyControls.swift) | `#Preview` 48 · `DisclosureGroup` 9 · `Form` 50 | 16, 23 |
| [CardDesignerVariantControls.swift](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerVariantControls.swift) | `DisclosureGroup` 176, 196 · `Section` 9, 56, 114, 146, 175 | 104 |
| [DeveloperCrashButton.swift](../../Where/WhereUI/Sources/Developer/DeveloperCrashButton.swift) | `Button` 12 · `confirmationDialog` 28 | — |
| [DeveloperCrashTestingView.swift](../../Where/WhereUI/Sources/Developer/DeveloperCrashTestingView.swift) | `List` 8 | — |
| [DeveloperDemoLaunchSheet.swift](../../Where/WhereUI/Sources/Developer/DeveloperDemoLaunchSheet.swift) | `Form` 63 · `NavigationStack` 62 · `Section` 64, 88 | 88 |
| [DeveloperDemoModeRow.swift](../../Where/WhereUI/Sources/Developer/DeveloperDemoModeRow.swift) | `Button` 15 · `Label` 16 · `VStack` 17 | — |
| [DeveloperInspectorModeRow.swift](../../Where/WhereUI/Sources/Developer/DeveloperInspectorModeRow.swift) | `Button` 17 · `Label` 18 · `VStack` 19 | — |
| [DeveloperLogViewModeRow.swift](../../Where/WhereUI/Sources/Developer/DeveloperLogViewModeRow.swift) | `Label` 18 · `Toggle` 17 | — |
| [DeveloperOverlay.swift](../../Where/WhereUI/Sources/Developer/DeveloperOverlay.swift) | `AdaptivePaneGeometryReader` 61 · `ZStack` 75 | 83, 104, 112 |
| [DeveloperOverlayButton.swift](../../Where/WhereUI/Sources/Developer/DeveloperOverlayButton.swift) | `#Preview` 40, 55 · `Button` 21 · `ZStack` 41, 56 | — |
| [DeveloperOverlayMenu.swift](../../Where/WhereUI/Sources/Developer/DeveloperOverlayMenu.swift) | `ForEach` 35 · `LazyVStack` 31 · `ScrollView` 30 | 37, 51, 60, 74 |
| [DeveloperOverlayPreview.swift](../../Where/WhereUI/Sources/Developer/DeveloperOverlayPreview.swift) | `Group` 17 | — |
| [DeveloperSurface.swift](../../Where/WhereUI/Sources/Developer/DeveloperSurface.swift) | `HStack` 26 · `VStack` 25 · `overlay` 86 | 41, 88 |
| [DeveloperTabBarInset.swift](../../Where/WhereUI/Sources/Developer/DeveloperTabBarInset.swift) | `GeometryReader` 63 · `background` 62 | — |
| [DeveloperToast.swift](../../Where/WhereUI/Sources/Developer/DeveloperToast.swift) | `#Preview` 139 · `HStack` 100 · `VStack` 81, 103 | — |
| [DeveloperToolMenuButton.swift](../../Where/WhereUI/Sources/Developer/DeveloperToolMenuButton.swift) | `Button` 13 | — |
| [DeveloperToolView.swift](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift) | — | 46, 57 |
| [DeviceLayoutLabView.swift](../../Where/WhereUI/Sources/Developer/DeviceLayout/DeviceLayoutLabView.swift) | `ForEach` 64 · `GeometryReader` 104 · `HStack` 26 · `Picker` 33 · `VStack` 25 · `whereSnapshot` 193 | 81, 87 |
| [DuoLayoutSnapshotFixture.swift](../../Where/WhereUI/Sources/Developer/DuoLayout/DuoLayoutSnapshotFixture.swift) | `#Preview` 69 · `Group` 83 | 88, 102 |
| [WhereFlyoverLocationsControls.swift](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverLocationsControls.swift) | `#Preview` 13 | — |
| [WhereFlyoverPresentationView.swift](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverPresentationView.swift) | `overlay` 11 | — |
| [WhereFlyoverView.swift](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverView.swift) | `Group` 11 | 19 |
| [RankingAnimationControls.swift](../../Where/WhereUI/Sources/Developer/RankingAnimation/RankingAnimationControls.swift) | `#Preview` 63 · `Section` 13 | — |
| [RankingAnimationLabView.swift](../../Where/WhereUI/Sources/Developer/RankingAnimation/RankingAnimationLabView.swift) | `Form` 21 · `Section` 22 | — |
| [RankingAnimationPreview.swift](../../Where/WhereUI/Sources/Developer/RankingAnimation/RankingAnimationPreview.swift) | `#Preview` 46 · `ForEach` 21 · `LocationCardRankingStack` 20 | — |
| [RegionMapLegend.swift](../../Where/WhereUI/Sources/Developer/RegionMapLegend.swift) | `#Preview` 62 · `ForEach` 22 · `HStack` 39 · `List` 17 · `Section` 18 | — |
| [RegionMapView.swift](../../Where/WhereUI/Sources/Developer/RegionMapView.swift) | `ForEach` 352 · `VStack` 74, 351 · `whereSnapshot` 295 | 62, 68, 74, 266, 273, 355 |

### Where/WhereUI/Sources/Devices

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [RemovedDeviceView.swift](../../Where/WhereUI/Sources/Devices/RemovedDeviceView.swift) | `#Preview` 44 · `VStack` 14, 19 | — |

### Where/WhereUI/Sources/Elsewhere

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [DayRelabelView.swift](../../Where/WhereUI/Sources/Elsewhere/DayRelabelView.swift) | `Form` 101 · `NavigationStack` 268, 280 · `Section` 118, 177 · `ToolbarItem` 78 · `whereSnapshot` 267, 279 | 159 |
| [ElsewhereView.swift](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift) | `ForEach` 90 · `GlassEffectContainer` 88 · `NavigationLink` 91 · `NavigationLink label` 97 · `NavigationStack` 54 · `ScrollView` 77 · `VStack` 78, 89 | 77, 88, 127 |
| [RegionDaysView.swift](../../Where/WhereUI/Sources/Elsewhere/RegionDaysView.swift) | `ForEach` 80 · `HStack` 138 · `List` 69 · `NavigationLink label` 83 · `Section` 71, 79 · `VStack` 65, 142 | 65, 71, 100, 113 |

### Where/WhereUI/Sources/Evidence

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AddEvidenceView.swift](../../Where/WhereUI/Sources/Evidence/AddEvidenceView.swift) | `HStack` 116 · `NavigationStack` 37 · `Section` 91, 133, 148 · `ToolbarItem` 49 | 94, 101 |
| [EvidenceBlobPreview.swift](../../Where/WhereUI/Sources/Evidence/EvidenceBlobPreview.swift) | `#Preview` 114 | 38 |
| [EvidenceDetailView.swift](../../Where/WhereUI/Sources/Evidence/EvidenceDetailView.swift) | `#Preview` 105, 117 · `NavigationStack` 106, 118 · `ScrollView` 29 · `VStack` 50 · `hosted` 135 | 60, 84 |
| [EvidenceListView.swift](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift) | `#Preview` 178, 188, 197 · `HStack` 147 · `List` 95 · `NavigationStack` 179 · `ToolbarItem` 45 · `VStack` 152 · `hostedVariant` 224, 246 | 83 |

### Where/WhereUI/Sources/Forecasting

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [LocationForecastContent.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastContent.swift) | `#Preview` 32 · `VStack` 14 | — |
| [LocationForecastEndorsementButtonStyle.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastEndorsementButtonStyle.swift) | `overlay` 21 | — |
| [LocationForecastEstimateLabel.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastEstimateLabel.swift) | `#Preview` 51 · `ViewThatFits` 20 | 20 |
| [LocationForecastHeader.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeader.swift) | `#Preview` 40 · `Button` 13 | 13, 30 |
| [LocationForecastHeaderLabel.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeaderLabel.swift) | `#Preview` 53 · `HStack` 18, 34 · `VStack` 17 | 17, 34 |
| [LocationForecastHeaderText.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeaderText.swift) | `VStack` 12 | — |
| [LocationForecastPanel.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastPanel.swift) | `#Preview` 94 · `VStack` 27 · `ZStack` 38, 65 · `background` 37 · `overlay` 64 · `whereThemeSnapshot` 129 | 41 |
| [LocationForecastProgress.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastProgress.swift) | `#Preview` 84 · `GeometryReader` 19 · `ZStack` 23 · `overlay` 31 | 28 |
| [LocationForecastRow.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastRow.swift) | `#Preview` 96 · `VStack` 19, 27 | 99 |
| [LocationForecastSilhouettes.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastSilhouettes.swift) | `ForEach` 23 · `GeometryReader` 12 · `ZStack` 22 · `mask` 37 | 26 |
| [LocationForecastSummary.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastSummary.swift) | `VStack` 21 · `whereThemeSnapshot` 90 | 28 |
| [LocationForecastSummarySurface.swift](../../Where/WhereUI/Sources/Forecasting/LocationForecastSummarySurface.swift) | `ZStack` 13 · `background` 34 · `overlay` 49 | 39 |
| [PlannedStayBoundarySection.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStayBoundarySection.swift) | `#Preview` 45 · `Section` 9 | 29 |
| [PlannedStayEditor.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStayEditor.swift) | `Form` 33 · `NavigationLink` 144 · `NavigationStack` 32 · `Section` 35, 64, 82, 91, 143 · `ToolbarItem` 115 · `whereSnapshot` 193 | 35, 64, 82, 91, 120 |
| [PlannedStaySummaryRow.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStaySummaryRow.swift) | `#Preview` 59 · `HStack` 19 · `List` 62 · `VStack` 18 | 36, 44, 62 |
| [PlannedStaysView.swift](../../Where/WhereUI/Sources/Forecasting/PlannedStaysView.swift) | `Button label` 102, 154 · `HStack` 103, 123 · `LabeledContent` 122 · `List` 27 · `NavigationLink label` 121 · `NavigationStack` 26 · `ObservableHostingView content` 173 · `Section` 29, 41, 70, 99 | 29, 70 |
| [PlanningRegionPickerView.swift](../../Where/WhereUI/Sources/Forecasting/PlanningRegionPickerView.swift) | `Button label` 63 · `HStack` 64 · `List` 18 · `NavigationStack` 92, 102 · `Section` 20 · `whereSnapshot` 91, 101 | 20 |

### Where/WhereUI/Sources/Intents

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [IntentSnippets.swift](../../Where/WhereUI/Sources/Intents/IntentSnippets.swift) | `#Preview` 187 · `ForEach` 130 · `HStack` 41, 132, 145 · `VStack` 47, 112, 129 · `hosted` 217 | — |

### Where/WhereUI/Sources/Launch

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [LaunchSplashView.swift](../../Where/WhereUI/Sources/Launch/LaunchSplashView.swift) | `TimelineView` 225 · `VStack` 154 · `ZStack` 112 · `background` 182 · `whereSnapshot` 275 | 118 |
| [WhereLifecycleFailureView.swift](../../Where/WhereUI/Sources/Launch/WhereLifecycleFailureView.swift) | `GeometryReader` 88 · `ScrollView` 89 · `VStack` 90 | 88 |

### Where/WhereUI/Sources/Manual

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [LoggedDaysView.swift](../../Where/WhereUI/Sources/Manual/LoggedDaysView.swift) | `ForEach` 164 · `HStack` 238 · `List` 163 · `NavigationStack` 72, 81, 307, 324 · `ToolbarItem` 58 · `VStack` 130, 245 · `sheet` 71, 80 · `whereSnapshot` 306, 315, 323 | 114 |
| [ManualDayView.swift](../../Where/WhereUI/Sources/Manual/ManualDayView.swift) | `NavigationStack` 525, 534, 543, 556 · `Section` 128, 168, 278 · `ToolbarItem` 78 · `whereSnapshot` 524, 533, 542, 555 | 195, 202, 208, 225, 236 |

### Where/WhereUI/Sources/Onboarding

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [OnboardingThemeSelectionView.swift](../../Where/WhereUI/Sources/Onboarding/OnboardingThemeSelectionView.swift) | `GeometryReader` 15 · `ScrollView` 16 · `VStack` 17, 25 · `ZStack` 63 | — |
| [OnboardingView.swift](../../Where/WhereUI/Sources/Onboarding/OnboardingView.swift) | `ForEach` 130 · `GeometryReader` 131, 259 · `Group` 71 · `NavigationStack` 232, 247 · `ScrollView` 260 · `TabView` 129 · `VStack` 128, 185, 191, 206, 261, 267, 278, 279 · `confirmationDialog` 158 · `whereSnapshot` 474, 495, 509 | 75 |

### Where/WhereUI/Sources/Primary

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [CalendarContentView.swift](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift) | `Button label` 168, 525 · `ForEach` 245, 612 · `Group` 106, 108, 222 · `HStack` 611 · `LazyVGrid` 231 · `NavigationStack` 742, 757, 785, 798, 812, 826 · `ScrollView` 221 · `ToolbarItem` 165, 181 · `VStack` 224, 244 · `overlay` 371 · `overlayPreferenceValue` 347 · `snapshot` 584, 741, 756, 770, 797, 811, 825 · `whereSnapshot` 597, 610, 639 | 108, 128, 137, 224, 244, 253, 373, 467, 474 |
| [CalendarOverviewFeedback.swift](../../Where/WhereUI/Sources/Primary/CalendarOverviewFeedback.swift) | `keyframeAnimator` 12 · `overlay` 15 | — |
| [CalendarSnapshotCases.swift](../../Where/WhereUI/Sources/Primary/CalendarSnapshotCases.swift) | `#Preview` 177 · `Group` 112 · `NavigationStack` 48 · `snapshot` 47 · `whereSnapshot` 39 | — |
| [CalendarZoomOverlay.swift](../../Where/WhereUI/Sources/Primary/CalendarZoomOverlay.swift) | `#Preview` 171 · `ForEach` 45 · `ZStack` 44, 46 | 57, 67 |
| [FlightJourneyRow.swift](../../Where/WhereUI/Sources/Primary/FlightJourneyRow.swift) | `ForEach` 22 · `HStack` 15 · `VStack` 17 · `background` 41 | 15 |
| [LocationCardDayCount.swift](../../Where/WhereUI/Sources/Primary/LocationCardDayCount.swift) | `#Preview` 28 · `HStack` 13 | — |
| [LocationCardEstimateSticker.swift](../../Where/WhereUI/Sources/Primary/LocationCardEstimateSticker.swift) | `#Preview` 80 · `VStack` 25 · `ViewThatFits` 65 · `overlay` 42, 48 | — |
| [LocationCardOvertakeModifier.swift](../../Where/WhereUI/Sources/Primary/LocationCardOvertakeModifier.swift) | `keyframeAnimator` 38 | — |
| [LocationCardRankingStack.swift](../../Where/WhereUI/Sources/Primary/LocationCardRankingStack.swift) | `#Preview` 70 · `KeyframeAnimator` 32 | — |
| [LocationDetailPaneContainer.swift](../../Where/WhereUI/Sources/Primary/LocationDetailPaneContainer.swift) | `#Preview` 106 · `ForEach` 50 · `ZStack` 45 | — |
| [LocationWelcomeOverlay.swift](../../Where/WhereUI/Sources/Primary/LocationWelcomeOverlay.swift) | `#Preview` 65 · `AdaptivePaneGeometryReader` 25 · `ScrollView` 30 · `ZStack` 16 | 18, 25 |
| [LocationWelcomeStatusAccessory.swift](../../Where/WhereUI/Sources/Primary/LocationWelcomeStatusAccessory.swift) | `Button` 32 · `HStack` 15, 33 | 15, 32 |
| [LocationsBackground.swift](../../Where/WhereUI/Sources/Primary/LocationsBackground.swift) | `ForEach` 54 · `GeometryReader` 45 · `ZStack` 21, 53 · `whereSnapshot` 120 | 24 |
| [LocationsCardsView.swift](../../Where/WhereUI/Sources/Primary/LocationsCardsView.swift) | `Button label` 81 · `ForEach` 72 · `LocationCardRankingStack` 71 · `ScrollView` 63 · `VStack` 64 | — |
| [LocationsDetailContent.swift](../../Where/WhereUI/Sources/Primary/LocationsDetailContent.swift) | `#Preview` 86 · `Group` 15 · `NavigationStack` 91 | 17, 23, 55 |
| [LocationsEstimatePanel.swift](../../Where/WhereUI/Sources/Primary/LocationsEstimatePanel.swift) | `#Preview` 22 | 11 |
| [LocationsFlightNotice.swift](../../Where/WhereUI/Sources/Primary/LocationsFlightNotice.swift) | `#Preview` 32 · `Group` 16 | 16 |
| [LocationsStateContent.swift](../../Where/WhereUI/Sources/Primary/LocationsStateContent.swift) | `ScrollView` 36, 53 · `VStack` 37, 54 | 17 |
| [LocationsStateView.swift](../../Where/WhereUI/Sources/Primary/LocationsStateView.swift) | `ScrollView` 15 · `VStack` 16 | — |
| [LocationsView.swift](../../Where/WhereUI/Sources/Primary/LocationsView.swift) | `AdaptivePaneContainer` 114 · `HStack` 255 · `NavigationSplitView detail` 137 · `NavigationStack` 118, 138, 319 · `ToolbarItemGroup` 706 · `overlay` 460 · `sheet` 161 · `whereSnapshot` 622 | 118, 129, 415, 423, 430, 462, 710, 719 |
| [MonthGridView.swift](../../Where/WhereUI/Sources/Primary/MonthGridView.swift) | `ForEach` 98, 134, 142, 144, 482 · `GeometryReader` 510 · `Grid` 132 · `GridRow` 133, 143 · `Group` 483 · `HStack` 340, 405, 481 · `VStack` 99, 325, 384 · `ZStack` 517 · `background` 65, 394 · `layout` 339 · `overlay` 403 | 101, 110, 147, 177, 184, 405, 510, 526, 540 |
| [PlannedPresenceJourneyBackground.swift](../../Where/WhereUI/Sources/Primary/PlannedPresenceJourneyBackground.swift) | `VStack` 18, 45 · `ZStack` 16 · `mask` 43 | 18, 45 |
| [PlannedPresenceJourneyCardContent.swift](../../Where/WhereUI/Sources/Primary/PlannedPresenceJourneyCardContent.swift) | `#Preview` 99 · `HStack` 41 · `VStack` 32, 63, 100 · `countLayout` 29 | 32, 41, 53, 63, 76 |
| [PlannedPresenceJourneyRow.swift](../../Where/WhereUI/Sources/Primary/PlannedPresenceJourneyRow.swift) | `#Preview` 78 · `HStack` 30 · `background` 59 · `overlay` 49 | 85 |
| [PlannedStayHatch.swift](../../Where/WhereUI/Sources/Primary/PlannedStayHatch.swift) | `#Preview` 43 | — |
| [PresenceJourneyCardBorder.swift](../../Where/WhereUI/Sources/Primary/PresenceJourneyCardBorder.swift) | `#Preview` 27 | 16 |
| [PresenceJourneyRail.swift](../../Where/WhereUI/Sources/Primary/PresenceJourneyRail.swift) | `ZStack` 23, 51 | — |
| [PresenceJourneyRow.swift](../../Where/WhereUI/Sources/Primary/PresenceJourneyRow.swift) | `#Preview` 94 · `HStack` 34 · `VStack` 39 · `background` 74 · `countLayout` 38 · `overlay` 64 | 99 |
| [PresenceTimelineList.swift](../../Where/WhereUI/Sources/Primary/PresenceTimelineList.swift) | `Group` 96 · `ScrollView` 145 · `ToolbarItem` 197 · `VStack` 103, 134, 149, 158 · `whereSnapshot` 287, 300, 323, 334, 345, 356 | 103, 116, 122, 134, 136, 151 |
| [PresenceTimelineRows.swift](../../Where/WhereUI/Sources/Primary/PresenceTimelineRows.swift) | `ForEach` 59 · `Group` 65 · `contextMenu` 138 | 68, 78, 101 |
| [RegionCardSurface.swift](../../Where/WhereUI/Sources/Primary/RegionCardSurface.swift) | — | 15 |
| [RegionLocationConstellation.swift](../../Where/WhereUI/Sources/Primary/RegionLocationConstellation.swift) | `#Preview` 64 | 72 |
| [RegionOutlineArtwork.swift](../../Where/WhereUI/Sources/Primary/RegionOutlineArtwork.swift) | `overlay` 37 | 63 |
| [RegionOutlineSecurityBorder.swift](../../Where/WhereUI/Sources/Primary/RegionOutlineSecurityBorder.swift) | — | 219 |
| [RegionSummaryCard.swift](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift) | `#Preview` 568 · `ForEach` 550 · `GeometryReader` 366 · `HStack` 315 · `VStack` 314, 316, 489, 569, 597 · `ZStack` 206, 367, 470, 549 · `overlay` 365 · `whereThemeSnapshot` 649 | 222, 238, 248, 319, 343, 353, 362, 369, 375, 381, 491, 511 |
| [RegionWelcomeCard.swift](../../Where/WhereUI/Sources/Primary/RegionWelcomeCard.swift) | `Button` 140 · `HStack` 41 · `VStack` 40, 49 · `ZStack` 82, 94 · `background` 81, 147 · `overlay` 139 · `whereThemeSnapshot` 221 | 66, 84, 110, 126 |
| [YearRibbon.swift](../../Where/WhereUI/Sources/Primary/YearRibbon.swift) | `#Preview` 94 · `ForEach` 41 · `HStack` 30 · `VStack` 24, 29, 40, 45 · `background` 75 · `overlay` 83 | 40, 64 |
| [YearRibbonBand.swift](../../Where/WhereUI/Sources/Primary/YearRibbonBand.swift) | `#Preview` 73 · `ZStack` 20 · `overlay` 52 | — |

### Where/WhereUI/Sources/Regions

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [GroupedRegionSections.swift](../../Where/WhereUI/Sources/Regions/GroupedRegionSections.swift) | `#Preview` 53 · `Form` 54 · `Group` 21 · `Section` 40 | 23 |
| [RegionCustomizeView.swift](../../Where/WhereUI/Sources/Regions/RegionCustomizeView.swift) | `Button label` 80, 134 · `ForEach` 76, 112, 130 · `GlassEffectContainer` 43 · `Group` 183 · `LazyVGrid` 75, 111, 129 · `ToolbarItem` 204 · `VStack` 25 · `overlay` 84, 91, 153 | 190 |
| [RegionPickerView.swift](../../Where/WhereUI/Sources/Regions/RegionPickerView.swift) | `#Preview` 319 · `Button label` 225 · `ForEach` 33 · `Group` 141, 194 · `HStack` 193, 226 · `LabeledContent` 229 · `List` 32 · `ScrollViewReader` 31 · `whereSnapshot` 304 | 43, 145 |
| [RegionsSettingsView.swift](../../Where/WhereUI/Sources/Regions/RegionsSettingsView.swift) | `Group` 37 · `HStack` 122 · `List` 74 · `NavigationStack` 36 · `Section` 75, 88 · `ToolbarItem` 105 · `hosted` 235 | 39, 45, 80 |

### Where/WhereUI/Sources/Resolution

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AbruptChangeDetailView.swift](../../Where/WhereUI/Sources/Resolution/AbruptChangeDetailView.swift) | `#Preview` 92 · `Form` 18 · `NavigationLink` 25, 39 · `NavigationStack` 93 · `Section` 23, 37, 51 · `hosted` 122 | 18 |
| [FlightDayDetailView.swift](../../Where/WhereUI/Sources/Resolution/FlightDayDetailView.swift) | `DisclosureGroup` 72, 114 · `ForEach` 28, 73, 115 · `Form` 21 · `LabeledContent` 48 · `Section` 23, 47, 63, 111, 161, 175 · `VStack` 74 · `whereSnapshot` 217, 235 | 23, 28, 47, 63, 111, 141, 148, 161 |
| [FlightReviewPointContent.swift](../../Where/WhereUI/Sources/Resolution/FlightReviewPointContent.swift) | `VStack` 12 | 35 |
| [FlightReviewPointRow.swift](../../Where/WhereUI/Sources/Resolution/FlightReviewPointRow.swift) | `Form` 70, 86, 104 · `whereSnapshot` 69, 85, 103 | 12 |
| [FlightStatusBanner.swift](../../Where/WhereUI/Sources/Resolution/FlightStatusBanner.swift) | `ForEach` 122 · `VStack` 22, 121 · `whereSnapshot` 102, 120 | 34 |
| [ResolutionView.swift](../../Where/WhereUI/Sources/Resolution/ResolutionView.swift) | `ForEach` 112 · `List` 99 · `NavigationLink label` 142, 178 · `NavigationStack` 28 · `VStack` 143, 179 · `swipeActions` 190 | 54, 71, 84, 106, 115, 128, 192, 212 |

### Where/WhereUI/Sources/Settings

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AboutOpenSourceFooter.swift](../../Where/WhereUI/Sources/Settings/AboutOpenSourceFooter.swift) | `#Preview` 24 · `Link` 10 | — |
| [AboutOpenSourceStampText.swift](../../Where/WhereUI/Sources/Settings/AboutOpenSourceStampText.swift) | `VStack` 9 | — |
| [AboutSettingsView.swift](../../Where/WhereUI/Sources/Settings/AboutSettingsView.swift) | `ForEach` 136 · `Form` 49 · `Group` 188 · `NavigationStack` 267, 281, 297, 315 · `Section` 74, 126 · `SettingsFocusScope` 48 · `VStack` 183, 185 · `whereSnapshot` 266, 280, 294, 310 | 136 |
| [AlertsSettingsView.swift](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift) | `#Preview` 276 · `Button label` 194 · `Form` 36 · `Section` 54, 94, 137, 172, 191 · `SettingsFocusScope` 35 | 61, 68, 104, 111, 147, 205 |
| [AppIconView.swift](../../Where/WhereUI/Sources/Settings/AppIconView.swift) | `Button label` 115 · `GeometryReader` 42 · `HStack` 120 · `NavigationStack` 41 · `ScrollView` 85 · `VStack` 116, 152, 175 · `ZStack` 51 · `background` 197 | — |
| [AppearanceSettingsView.swift](../../Where/WhereUI/Sources/Settings/AppearanceSettingsView.swift) | `Form` 32 · `HStack` 86 · `Section` 44, 56, 84, 103, 119 · `Section footer` 75 · `SettingsFocusScope` 31 · `Toggle` 85 · `whereSnapshot` 238, 262 | 119 |
| [BackupSettingsSection.swift](../../Where/WhereUI/Sources/Settings/BackupSettingsSection.swift) | `Button` 19 · `Section` 14 | — |
| [DataSettingsView.swift](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift) | `Form` 42 · `NavigationStack` 189 · `Section` 91, 122 · `SettingsFocusScope` 41 · `whereSnapshot` 188 | — |
| [DevelopmentUpdatesView.swift](../../Where/WhereUI/Sources/Settings/DevelopmentUpdatesView.swift) | `SettingsFocusScope` 18 | — |
| [DeviceSettingsSection.swift](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift) | `#Preview` 208 · `Button label` 98 · `HStack` 17, 121 · `Label` 119 · `LabeledContent` 35, 44 · `Section` 16 · `Section footer` 141 · `Section header` 118 · `VStack` 130 · `ViewThatFits` 120 | 25, 58, 75, 86, 96 |
| [DevicesSettingsView.swift](../../Where/WhereUI/Sources/Settings/DevicesSettingsView.swift) | `Form` 46 · `NavigationStack` 175 · `Section` 49, 57, 68 · `SettingsFocusScope` 45 · `alert` 95 · `whereSnapshot` 160, 174 | 49, 57, 68 |
| [DiagnosticPersonalDataSection.swift](../../Where/WhereUI/Sources/Settings/DiagnosticPersonalDataSection.swift) | `#Preview` 37 · `Section` 8 · `confirmationDialog` 19 | — |
| [EstimatedTimeFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift) | `Button label` 107 · `FeatureMarketingPanel` 106, 154 · `Form` 33 · `Section` 58, 76, 86, 96 · `VStack` 155 | 136 |
| [FeatureEstimatedTimeCalculationExample.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/FeatureEstimatedTimeCalculationExample.swift) | `FeatureMarketingPanel` 11 · `GeometryReader` 21 · `HStack` 27 · `VStack` 12, 45 | — |
| [FeatureEstimatedTimeStatusPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/FeatureEstimatedTimeStatusPreview.swift) | `FeatureMarketingPanel` 14 · `VStack` 15 | — |
| [FeatureEvidenceArchivePreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureEvidenceArchivePreview.swift) | `FeatureMarketingPanel` 21 · `Group` 52 · `VStack` 22, 80 | 40, 54 |
| [FeatureEvidenceComposePreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureEvidenceComposePreview.swift) | `FeatureMarketingPanel` 13 · `VStack` 14, 21 | — |
| [FeatureShareSheetPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/FeatureShareSheetPreview.swift) | `FeatureMarketingPanel` 11 · `Group` 19, 77 · `HStack` 39, 79 · `Label` 59 · `VStack` 12, 24, 60, 87 | 21, 39, 79, 87 |
| [ShareEvidenceFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/ShareEvidenceFeaturesContent.swift) | `FeatureMarketingPanel` 40 · `Form` 15 · `NavigationLink` 41 · `Section` 27 · `Section footer` 54 | — |
| [ShareEvidenceFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/ShareEvidenceFeaturesView.swift) | `SettingsFocusScope` 45 · `StaggeredRevealScope` 44 · `whereSnapshot` 103 | — |
| [FeatureDataAccuracyPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/FeatureDataAccuracyPreview.swift) | `FeatureMarketingPanel` 13 · `VStack` 14 | — |
| [InsightsAccuracyFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesContent.swift) | `FeatureMarketingPanel` 34 · `Form` 13 · `Section` 25, 46 · `Section footer` 69 | 34 |
| [FeatureAppIconPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/FeatureAppIconPreview.swift) | `FeatureMarketingPanel` 13 · `VStack` 14, 24 · `selectedLayout` 22 | 22 |
| [FeatureRegionStylePreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/FeatureRegionStylePreview.swift) | `#Preview` 81 · `FeatureMarketingPanel` 14 · `Label` 16 · `VStack` 15, 17, 60 · `previewLayout` 29 | — |
| [PersonalizationFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesContent.swift) | `FeatureMarketingPanel` 38, 59 · `Form` 18 · `Section` 30, 50, 71 · `Section footer` 83 | 59 |
| [PersonalizationFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesView.swift) | `SettingsFocusScope` 31 · `StaggeredRevealScope` 30 · `whereSnapshot` 104 | — |
| [PlacesYearFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PlacesYear/PlacesYearFeaturesContent.swift) | `FeatureGuidePanel` 15, 48 | 17, 27, 50 |
| [PlacesYearFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PlacesYear/PlacesYearFeaturesView.swift) | `whereSnapshot` 83, 93 | — |
| [PrivacyBackupsFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PrivacyBackups/PrivacyBackupsFeaturesView.swift) | `whereSnapshot` 65, 72 | — |
| [FeatureDiscoveryBackground.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureDiscoveryBackground.swift) | `ZStack` 11 | — |
| [FeatureGuideForm.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuideForm.swift) | `#Preview` 31 · `Form` 10 | — |
| [FeatureGuidePage.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuidePage.swift) | `#Preview` 25 · `NavigationStack` 26 · `StaggeredRevealScope` 12 | — |
| [FeatureGuidePanel.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuidePanel.swift) | `#Preview` 31 · `FeatureMarketingPanel` 13 · `VStack` 17 | — |
| [FeatureMarketingHeader.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureMarketingHeader.swift) | `#Preview` 42 · `VStack` 16 | — |
| [FeatureMarketingPanel.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureMarketingPanel.swift) | `#Preview` 29 | — |
| [FeatureSettingsLink.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureSettingsLink.swift) | — | 10 |
| [SiriChatBubble.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriChatBubble.swift) | `#Preview` 58 · `HStack` 18 · `VStack` 59 | — |
| [SiriFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriFeaturesContent.swift) | `ForEach` 29 · `Form` 13 · `Section` 25, 53 · `Section footer` 59 | — |
| [SiriFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriFeaturesView.swift) | `#Preview` 68 | — |
| [SiriIntentCard.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriIntentCard.swift) | `#Preview` 45 · `VStack` 16 | — |
| [FeatureSpotlightPreview.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Spotlight/FeatureSpotlightPreview.swift) | `#Preview` 63 · `FeatureMarketingPanel` 13 · `HStack` 33 · `VStack` 14, 36 | — |
| [FeatureHomeScreenExample.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/FeatureHomeScreenExample.swift) | `HStack` 14 · `VStack` 13 | — |
| [FeatureLockScreenExample.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/FeatureLockScreenExample.swift) | `#Preview` 69 · `HStack` 26 · `VStack` 14 | — |
| [WidgetExampleFrame.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/WidgetExampleFrame.swift) | `#Preview` 37 | — |
| [WidgetFeaturesContent.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/WidgetFeaturesContent.swift) | `Form` 13 · `Section` 25, 39 · `Section footer` 51 | — |
| [WidgetFeaturesView.swift](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/WidgetFeaturesView.swift) | `#Preview` 94 | — |
| [LicenseView.swift](../../Where/WhereUI/Sources/Settings/LicenseView.swift) | `NavigationStack` 65 · `VStack` 24 · `whereSnapshot` 64 | — |
| [LocationStatusRow.swift](../../Where/WhereUI/Sources/Settings/LocationStatusRow.swift) | `#Preview` 77 · `Form` 78 · `HStack` 15 · `Section` 79 | — |
| [PrivacyDiagnosticsSettingsView.swift](../../Where/WhereUI/Sources/Settings/PrivacyDiagnosticsSettingsView.swift) | `Form` 14 · `Picker` 48 · `Section` 22, 44 · `SettingsFocusScope` 13 · `VStack` 66 · `whereSnapshot` 215 | 66, 84 |
| [PrivacyPassportCard.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportCard.swift) | `#Preview` 39 · `Form` 40 · `PrivacyPassportCardSurface` 13 · `VStack` 14, 22 · `whereThemeSnapshot` 63 | — |
| [PrivacyPassportCardSurface.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportCardSurface.swift) | `#Preview` 73 · `Group` 16 · `ZStack` 50 · `background` 49 | 19, 52 |
| [PrivacyPassportDisclosureHeader.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureHeader.swift) | `#Preview` 82 · `HStack` 14, 44 · `PrivacyPassportCardSurface` 83 · `VStack` 38, 61 · `ViewThatFits` 13 | 38, 61 |
| [PrivacyPassportDisclosureRow.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureRow.swift) | `#Preview` 30 · `NavigationStack` 31 · `PrivacyPassportCardSurface` 32 | 12 |
| [PrivacyPassportDisclosureRowLabel.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureRowLabel.swift) | `#Preview` 45 · `Group` 12 · `HStack` 22 · `PrivacyPassportCardSurface` 46 · `VStack` 14 | 14, 22 |
| [PrivacyPassportDisclosureSymbol.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureSymbol.swift) | `#Preview` 22 | — |
| [PrivacyPassportDisclosureText.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureText.swift) | `#Preview` 27 · `PrivacyPassportCardSurface` 28 · `VStack` 12 | — |
| [PrivacyPassportHeader.swift](../../Where/WhereUI/Sources/Settings/PrivacyPassportHeader.swift) | `#Preview` 36 · `HStack` 21 · `VStack` 10 | 10, 21 |
| [RecordingConfigurationWarningTabLabel.swift](../../Where/WhereUI/Sources/Settings/RecordingConfigurationWarningTabLabel.swift) | `#Preview` 29 | — |
| [SettingsContent.swift](../../Where/WhereUI/Sources/Settings/SettingsContent.swift) | `ForEach` 78 · `Label` 111, 239 · `LabeledContent label` 207 · `List` 66 · `NavigationLink` 110 · `Section` 109, 138 · `VStack` 112 | 78, 81 |
| [SettingsIcon.swift](../../Where/WhereUI/Sources/Settings/SettingsIcon.swift) | `#Preview` 30 · `ForEach` 32 · `List` 31 | — |
| [SettingsRow.swift](../../Where/WhereUI/Sources/Settings/SettingsRow.swift) | `#Preview` 150 · `List` 154 · `ScrollViewReader` 119 · `SettingsFocusScope` 153 · `overlay` 78 | — |
| [SettingsView.swift](../../Where/WhereUI/Sources/Settings/SettingsView.swift) | `Group` 87 · `NavigationSplitView` 75 · `NavigationSplitView detail` 85 · `NavigationStack` 86 · `whereSnapshot` 286 | 164, 185, 198, 212 |
| [VisibleYearSettingsView.swift](../../Where/WhereUI/Sources/Settings/VisibleYearSettingsView.swift) | `Form` 14 · `SettingsFocusScope` 13 | — |

### Where/WhereUI/Sources/Shared

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AdaptivePaneContainer.swift](../../Where/WhereUI/Sources/Shared/AdaptivePaneContainer.swift) | `#Preview` 110 · `AdaptivePaneGeometryReader` 9 | — |
| [AppIconActivityIndicator.swift](../../Where/WhereUI/Sources/Shared/AppIconActivityIndicator.swift) | `#Preview` 61, 69 · `background` 40 | — |
| [AppIconLoadingView.swift](../../Where/WhereUI/Sources/Shared/AppIconLoadingView.swift) | `VStack` 16 | — |
| [CardSurfaceButtonStyle.swift](../../Where/WhereUI/Sources/Shared/CardSurfaceButtonStyle.swift) | `overlay` 28 | 14 |
| [ManualEntryAuditSection.swift](../../Where/WhereUI/Sources/Shared/ManualEntryAuditSection.swift) | `#Preview` 41 · `Form` 42 · `Section` 11 | — |
| [MatteSurfaceModifier.swift](../../Where/WhereUI/Sources/Shared/MatteSurfaceModifier.swift) | `overlay` 17 | 14 |
| [ObservableHostingView.swift](../../Where/WhereUI/Sources/Shared/ObservableHostingView.swift) | `#Preview` 47 | — |
| [PassportSeal.swift](../../Where/WhereUI/Sources/Shared/PassportSeal.swift) | `ZStack` 13 | — |
| [PresenceSelection.swift](../../Where/WhereUI/Sources/Shared/PresenceSelection.swift) | `overlay` 11 | 14 |
| [RecordedPointsMap.swift](../../Where/WhereUI/Sources/Shared/RecordedPointsMap.swift) | `#Preview` 175 · `Group` 55 | 59 |
| [RegionPolygonMap.swift](../../Where/WhereUI/Sources/Shared/RegionPolygonMap.swift) | `#Preview` 314 · `Group` 320 | 322 |
| [RegionToggleRow.swift](../../Where/WhereUI/Sources/Shared/RegionToggleRow.swift) | `#Preview` 22 · `Toggle` 11 | — |
| [SavingStatusRow.swift](../../Where/WhereUI/Sources/Shared/SavingStatusRow.swift) | `#Preview` 22 | — |
| [SecurityPrintRosette.swift](../../Where/WhereUI/Sources/Shared/SecurityPrintRosette.swift) | `#Preview` 66 | — |
| [StaggeredReveal.swift](../../Where/WhereUI/Sources/Shared/StaggeredReveal.swift) | `#Preview` 69 · `StaggeredRevealScope` 70 · `VStack` 71 | — |
| [StampBanner.swift](../../Where/WhereUI/Sources/Shared/StampBanner.swift) | `#Preview` 73 · `Group` 14 · `HStack` 17, 32 · `VStack` 16 · `background` 49 | 16, 32 |
| [TiltSheen.swift](../../Where/WhereUI/Sources/Shared/TiltSheen.swift) | `#Preview` 126 · `GeometryReader` 53 · `ZStack` 60 | — |
| [WhereContentRoot.swift](../../Where/WhereUI/Sources/Shared/WhereContentRoot.swift) | `#Preview` 36 | — |
| [WhereDatePicker.swift](../../Where/WhereUI/Sources/Shared/WhereDatePicker.swift) | `#Preview` 177 · `Form` 178 · `LabeledContent` 132 | 44, 59, 66, 73, 121 |
| [WhereFormRoot.swift](../../Where/WhereUI/Sources/Shared/WhereFormRoot.swift) | `#Preview` 42 | 26 |
| [WhereScreenRoot.swift](../../Where/WhereUI/Sources/Shared/WhereScreenRoot.swift) | — | 29 |
| [WhereThemePicker.swift](../../Where/WhereUI/Sources/Shared/WhereThemePicker.swift) | `ForEach` 36 · `Group` 15 · `HStack` 76 · `VStack` 63, 75 · `ViewThatFits` 19 · `overlay` 96 | 19 |
| [YearSelector.swift](../../Where/WhereUI/Sources/Shared/YearSelector.swift) | `Button label` 15 · `ForEach` 12 · `Menu` 11 | — |

### Where/WhereUI/Sources/Widgets

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [TodayAccessoryViews.swift](../../Where/WhereUI/Sources/Widgets/TodayAccessoryViews.swift) | `Group` 25 · `VStack` 60 · `ZStack` 58 | — |
| [TodayWidgetView.swift](../../Where/WhereUI/Sources/Widgets/TodayWidgetView.swift) | `ForEach` 80 · `HStack` 29, 82 · `VStack` 28, 63, 79, 97 | — |
| [WidgetCompatibilityView.swift](../../Where/WhereUI/Sources/Widgets/WidgetCompatibilityView.swift) | `VStack` 59 · `ViewThatFits` 58 · `containerBackground` 20 | 44 |
| [YearTotalsRectangularAccessoryView.swift](../../Where/WhereUI/Sources/Widgets/YearTotalsRectangularAccessoryView.swift) | `ForEach` 36 · `Group` 27 · `HStack` 37 · `VStack` 35 | 29, 35 |
| [YearTotalsWidgetView.swift](../../Where/WhereUI/Sources/Widgets/YearTotalsWidgetView.swift) | `ForEach` 55 · `HStack` 56 · `VStack` 30, 54, 75 · `whereSnapshot` 94 | — |

### Where/WhereUI/Sources/Year

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [YearView.swift](../../Where/WhereUI/Sources/Year/YearView.swift) | `Button label` 133 · `Group` 37 · `NavigationStack` 36 | 40 |

### Where/WhereUI/Tests

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [AdaptivePaneContainerTests.swift](../../Where/WhereUI/Tests/AdaptivePaneContainerTests.swift) | `AdaptivePaneHostedSurface` 11 | — |
| [CalendarContentViewTests.swift](../../Where/WhereUI/Tests/CalendarContentViewTests.swift) | `NavigationStack` 19 · `overlayPreferenceValue` 29 | — |
| [LocationsViewTests.swift](../../Where/WhereUI/Tests/LocationsViewTests.swift) | `AdaptivePaneHostedSurface` 114 · `overlay` 116, 245 | — |
| [MainTabsTests.swift](../../Where/WhereUI/Tests/MainTabsTests.swift) | `AdaptivePaneHostedSurface` 137 | — |
| [PresenceTimelineListTests.swift](../../Where/WhereUI/Tests/PresenceTimelineListTests.swift) | `overlay` 81 | — |
| [PrimaryRegionSelectionModelTests.swift](../../Where/WhereUI/Tests/PrimaryRegionSelectionModelTests.swift) | `NavigationStack` 121 | — |
| [RegionArtworkTaskTests.swift](../../Where/WhereUI/Tests/RegionArtworkTaskTests.swift) | `VStack` 20 | — |
| [WhereContentRootTests.swift](../../Where/WhereUI/Tests/WhereContentRootTests.swift) | `ScrollView` 71 · `VStack` 72 | — |
| [WhereFormRootTests.swift](../../Where/WhereUI/Tests/WhereFormRootTests.swift) | `Group` 117 | — |
| [WhereScreenRootTests.swift](../../Where/WhereUI/Tests/WhereScreenRootTests.swift) | `Group` 144 · `NavigationStack` 125 | 148 |

### Where/WhereWidgets/Sources

| Source | Builder and opening line | Branch expression lines |
| --- | --- | --- |
| [TodayWidget.swift](../../Where/WhereWidgets/Sources/TodayWidget.swift) | `StaticConfiguration` 25 | — |
| [YearTotalsWidget.swift](../../Where/WhereWidgets/Sources/YearTotalsWidget.swift) | `StaticConfiguration` 25 | 57, 63, 70, 76 |
