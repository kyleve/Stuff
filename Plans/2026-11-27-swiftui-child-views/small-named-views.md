# Small named views and their callers

[Plan overview](README.md) · [Declaration and inline index](audit.md) · [Baseline source](https://github.com/kyleve/Stuff/tree/5b1747d01ddb5a3392d5b0499d6f5e3784613f01)

At the audited revision, 113 named views had a 5–19-line `body` and a source filename matching the type. These rows address the reverse placement question. When one concrete child belongs to one parent, the merged rule places it in that parent’s file. Resolve its callers, existing role and final formatted size before moving it. Each source link points to the body declaration and the caller links point to explicit construction sites.

At 13 lines, `LocationForecastHeaderText` is constructed by `LocationForecastHeaderLabel` in both of its layout branches and by its own preview. Review it for relocation alongside that parent. By comparison, `UpdateBuildSummary` has 18 lines and renders on both the update page and the individual build screen. The Installer pilot should preserve both callers.

For the first pass, SwiftSyntax identified explicit constructor calls (including qualified names, generic specialization and explicit `.init`) across tracked Swift. The comparison groups those calls by enclosing type and source file. It distinguishes runtime Swift, including developer tools, from recognizable preview, snapshot, test and Flyover-registration contexts. The latter still matter for access control and reuse. Call counts omit inferred `.init`, constructor references passed as values, generated code and external clients. Search declarations, protocols, registrations and callers before accepting sole ownership. A single navigation destination or public API can have only one visible caller and still own its own screen or module boundary.

| Review context | Bodies |
| --- | ---: |
| One enclosing type in another file | 36 |
| Multiple enclosing types | 39 |
| Independent screen, host or capture root | 24 |
| Public view | 11 |
| Same-file caller | 2 |
| Fixture | 1 |

Use the numbered plan that owns the source. Record the final placement or the specific ownership reason for retaining it. Keep named boundaries required by the module contract and move the relevant previews, access or registrations with the represented view as appropriate. Where a body falls below five lines after inner extractions, the rule imposes no location.

For multiple enclosing types the table shows up to two callers and the count of further caller types. A source file may appear in both this list and the helper or inline index.

## One enclosing type in another file

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [FlyoverCompactControlBar](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift#L10) | 19 | [FlyoverControlBar](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L26) |
| [FlyoverConnectorCanvas](../../Shared/Flyover/Sources/FlyoverConnectorCanvas.swift#L9) | 13 | [FlyoverCanvasView](../../Shared/Flyover/Sources/FlyoverCanvasView.swift#L66) |
| [FlyoverControlBar](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L10) | 19 | [FlyoverRootView](../../Shared/Flyover/Sources/FlyoverRootView.swift#L27) |
| [FlyoverFocusedControls](../../Shared/Flyover/Sources/FlyoverFocusedControls.swift#L10) | 18 | [FlyoverFocusedView](../../Shared/Flyover/Sources/FlyoverFocusedView.swift#L24) |
| [FlyoverFocusedVariantPicker](../../Shared/Flyover/Sources/FlyoverFocusedVariantPicker.swift#L8) | 10 | [FlyoverFocusedControls](../../Shared/Flyover/Sources/FlyoverFocusedControls.swift#L13) |
| [FlyoverGroupBackdrop](../../Shared/Flyover/Sources/FlyoverGroupBackdrop.swift#L9) | 13 | [FlyoverCanvasView](../../Shared/Flyover/Sources/FlyoverCanvasView.swift#L58) |
| [FlyoverOverview](../../Shared/Flyover/Sources/FlyoverOverview.swift#L8) | 6 | [FlyoverRootView](../../Shared/Flyover/Sources/FlyoverRootView.swift#L13) |
| [FlyoverScreenHeader](../../Shared/Flyover/Sources/FlyoverScreenHeader.swift#L10) | 11 | [FlyoverScreenFrame](../../Shared/Flyover/Sources/FlyoverScreenFrame.swift#L15) |
| [CardDesignerArtworkControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerArtworkControls.swift#L8) | 11 | [CardDesignerVariantControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerVariantControls.swift#L92) |
| [CardDesignerPreview](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerPreview.swift#L18) | 17 | [CardDesignerStudioView](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerStudioView.swift#L26) |
| [CardDesignerSecurityPrintControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSecurityPrintControls.swift#L8) | 18 | [CardDesignerSharedControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSharedControls.swift#L40) |
| [DeveloperOverlayButton](../../Where/WhereUI/Sources/Developer/DeveloperOverlayButton.swift#L19) | 17 | [DeveloperOverlay](../../Where/WhereUI/Sources/Developer/DeveloperOverlay.swift#L112) |
| [DeveloperToolMenuButton](../../Where/WhereUI/Sources/Developer/DeveloperToolMenuButton.swift#L11) | 15 | [DeveloperOverlayMenu](../../Where/WhereUI/Sources/Developer/DeveloperOverlayMenu.swift#L37) |
| [DeveloperToolUnavailableView](../../Where/WhereUI/Sources/Developer/DeveloperToolUnavailableView.swift#L8) | 7 | [DeveloperToolView](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift#L66) |
| [RegionMapLegend](../../Where/WhereUI/Sources/Developer/RegionMapLegend.swift#L16) | 19 | [RegionMapView](../../Where/WhereUI/Sources/Developer/RegionMapView.swift#L99) |
| [EvidenceBlobPreview](../../Where/WhereUI/Sources/Evidence/EvidenceBlobPreview.swift#L17) | 13 | [EvidenceDetailView](../../Where/WhereUI/Sources/Evidence/EvidenceDetailView.swift#L79) |
| [LocationForecastControls](../../Where/WhereUI/Sources/Forecasting/LocationForecastControls.swift#L9) | 11 | [LocationForecastContent](../../Where/WhereUI/Sources/Forecasting/LocationForecastContent.swift#L25) |
| [LocationForecastEstimateLabel](../../Where/WhereUI/Sources/Forecasting/LocationForecastEstimateLabel.swift#L11) | 19 | [LocationForecastRow](../../Where/WhereUI/Sources/Forecasting/LocationForecastRow.swift#L20) |
| [LocationForecastHeaderText](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeaderText.swift#L9) | 13 | [LocationForecastHeaderLabel](../../Where/WhereUI/Sources/Forecasting/LocationForecastHeaderLabel.swift#L31) |
| [CalendarZoomOverlay](../../Where/WhereUI/Sources/Primary/CalendarZoomOverlay.swift#L9) | 5 | [CalendarContentView](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L373) |
| [LocationsStateContent](../../Where/WhereUI/Sources/Primary/LocationsStateContent.swift#L12) | 19 | [LocationsStateView](../../Where/WhereUI/Sources/Primary/LocationsStateView.swift#L18) |
| [LocationsStateView](../../Where/WhereUI/Sources/Primary/LocationsStateView.swift#L14) | 14 | [LocationsContent](../../Where/WhereUI/Sources/Primary/LocationsView.swift#L415) |
| [MonthGridView](../../Where/WhereUI/Sources/Primary/MonthGridView.swift#L57) | 17 | [CalendarContentView](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L497) |
| [FlightReviewPointRow](../../Where/WhereUI/Sources/Resolution/FlightReviewPointRow.swift#L10) | 17 | [FlightDayDetailView](../../Where/WhereUI/Sources/Resolution/FlightDayDetailView.swift#L116) |
| [AboutOpenSourceFooter](../../Where/WhereUI/Sources/Settings/AboutOpenSourceFooter.swift#L9) | 10 | [AboutSettingsView](../../Where/WhereUI/Sources/Settings/AboutSettingsView.swift#L60) |
| [AboutOpenSourceStampText](../../Where/WhereUI/Sources/Settings/AboutOpenSourceStampText.swift#L7) | 10 | [AboutOpenSourceFooter](../../Where/WhereUI/Sources/Settings/AboutOpenSourceFooter.swift#L16) |
| [FeatureEstimatedTimeStatusPreview](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/FeatureEstimatedTimeStatusPreview.swift#L13) | 9 | [EstimatedTimeFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L47) |
| [FeatureGuideForm](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuideForm.swift#L9) | 17 | [FeatureGuidePage](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuidePage.swift#L14) |
| [PrivacyPassportDisclosureRow](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureRow.swift#L10) | 15 | [PrivacyPassportCard](../../Where/WhereUI/Sources/Settings/PrivacyPassportCard.swift#L24) |
| [PrivacyPassportDisclosureSymbol](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureSymbol.swift#L10) | 7 | [PrivacyPassportDisclosureRowLabel](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureRowLabel.swift#L15) |
| [PrivacyPassportDisclosureText](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureText.swift#L10) | 11 | [PrivacyPassportDisclosureRowLabel](../../Where/WhereUI/Sources/Settings/PrivacyPassportDisclosureRowLabel.swift#L16) |
| [RecordingConfigurationWarningTabLabel](../../Where/WhereUI/Sources/Settings/RecordingConfigurationWarningTabLabel.swift#L9) | 15 | [MainTabs](../../Where/WhereUI/Sources/MainTabs.swift#L123) |
| [SettingsIcon](../../Where/WhereUI/Sources/Settings/SettingsIcon.swift#L14) | 10 | [SettingsContent](../../Where/WhereUI/Sources/Settings/SettingsContent.swift#L211) |
| [AdaptivePaneContainer](../../Where/WhereUI/Sources/Shared/AdaptivePaneContainer.swift#L8) | 7 | [LocationsView](../../Where/WhereUI/Sources/Primary/LocationsView.swift#L114) |
| [AppIconActivityIndicator](../../Where/WhereUI/Sources/Shared/AppIconActivityIndicator.swift#L36) | 17 | [AppIconLoadingView](../../Where/WhereUI/Sources/Shared/AppIconLoadingView.swift#L17) |
| [YearSelector](../../Where/WhereUI/Sources/Shared/YearSelector.swift#L10) | 16 | [VisibleYearSettingsView](../../Where/WhereUI/Sources/Settings/VisibleYearSettingsView.swift#L17) |

## Multiple enclosing types

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [FlyoverScreenFrame](../../Shared/Flyover/Sources/FlyoverScreenFrame.swift#L12) | 19 | [FlyoverCanvasView](../../Shared/Flyover/Sources/FlyoverCanvasView.swift#L72) · [FlyoverListView](../../Shared/Flyover/Sources/FlyoverListView.swift#L15) |
| [FlyoverViewModePicker](../../Shared/Flyover/Sources/FlyoverViewModePicker.swift#L7) | 7 | [FlyoverCompactControlBar](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift#L13) · [FlyoverControlBar](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L13) |
| [FlyoverViewportMenu](../../Shared/Flyover/Sources/FlyoverViewportMenu.swift#L8) | 16 | [FlyoverCompactControlBar](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift#L17) · [FlyoverControlBar](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L17) |
| [FlyoverZoomSlider](../../Shared/Flyover/Sources/FlyoverZoomSlider.swift#L8) | 9 | [FlyoverCompactControlBar](../../Shared/Flyover/Sources/FlyoverCompactControlBar.swift#L15) · [FlyoverControlBar](../../Shared/Flyover/Sources/FlyoverControlBar.swift#L15) |
| [UpdateBuildSummary](../../Shared/InstallerKitUI/Sources/UpdateBuildSummary.swift#L9) | 18 | [UpdateBuildView](../../Shared/InstallerKitUI/Sources/UpdateBuildView.swift#L46) · [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L103) |
| [UpdateCard](../../Shared/InstallerKitUI/Sources/UpdateCard.swift#L9) | 14 | [UpdateBuildInformation](../../Shared/InstallerKitUI/Sources/UpdateBuildInformation.swift#L11) · [UpdateBuildSummary](../../Shared/InstallerKitUI/Sources/UpdateBuildSummary.swift#L10) · +8 |
| [UpdateCheckButton](../../Shared/InstallerKitUI/Sources/UpdateCheckButton.swift#L9) | 11 | [UpdateBrowserPage](../../Shared/InstallerKitUI/Sources/UpdateBrowserPage.swift#L23) · [UpdateInstalledBuild](../../Shared/InstallerKitUI/Sources/UpdateInstalledBuild.swift#L47) |
| [UpdateDetailRow](../../Shared/InstallerKitUI/Sources/UpdateDetailRow.swift#L8) | 17 | [UpdateBuildInformation](../../Shared/InstallerKitUI/Sources/UpdateBuildInformation.swift#L13) · [UpdateInstalledBuild](../../Shared/InstallerKitUI/Sources/UpdateInstalledBuild.swift#L11) · +1 |
| [UpdateFailureCard](../../Shared/InstallerKitUI/Sources/UpdateFailureCard.swift#L11) | 14 | [UpdateBrowserPage](../../Shared/InstallerKitUI/Sources/UpdateBrowserPage.swift#L13) · [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L70) |
| [UpdateInstallLink](../../Shared/InstallerKitUI/Sources/UpdateInstallLink.swift#L9) | 9 | [UpdateBuildView](../../Shared/InstallerKitUI/Sources/UpdateBuildView.swift#L33) · [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L87) |
| [UpdateLocalBuildNotice](../../Shared/InstallerKitUI/Sources/UpdateLocalBuildNotice.swift#L9) | 10 | [UpdateChannelsView](../../Shared/InstallerKitUI/Sources/UpdateChannelsView.swift#L41) · [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L67) |
| [UpdatePageLayout](../../Shared/InstallerKitUI/Sources/UpdatePageLayout.swift#L8) | 9 | [UpdateBrowserPage](../../Shared/InstallerKitUI/Sources/UpdateBrowserPage.swift#L11) · [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L52) |
| [UpdatePullRequestLink](../../Shared/InstallerKitUI/Sources/UpdatePullRequestLink.swift#L9) | 8 | [UpdateBuildInformation](../../Shared/InstallerKitUI/Sources/UpdateBuildInformation.swift#L12) · [UpdateInstalledBuild](../../Shared/InstallerKitUI/Sources/UpdateInstalledBuild.swift#L16) |
| [LogEventList](../../Shared/Periscope/PeriscopeTools/Sources/Components/LogEventList.swift#L15) | 12 | [LogInspectorView](../../Shared/Periscope/PeriscopeTools/Sources/InspectMode/LogInspectable.swift#L130) · [ScopeEventsView](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/ScopeEventsView.swift#L72) · +1 |
| [CardDesignerCGFloatControl](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerCGFloatControl.swift#L10) | 12 | [CardDesignerArtworkLayerControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerArtworkLayerControls.swift#L10) · [CardDesignerEntryStampControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerEntryStampControls.swift#L8) · +5 |
| [CardDesignerDoubleControl](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerDoubleControl.swift#L10) | 12 | [CardDesignerArtworkLayerControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerArtworkLayerControls.swift#L40) · [CardDesignerEntryStampControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerEntryStampControls.swift#L14) · +5 |
| [CardDesignerSectionHeader](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSectionHeader.swift#L8) | 7 | [CardDesignerSharedControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerSharedControls.swift#L49) · [CardDesignerVariantControls](../../Where/WhereUI/Sources/Developer/CardDesigner/CardDesignerVariantControls.swift#L53) · +1 |
| [LocationForecastContent](../../Where/WhereUI/Sources/Forecasting/LocationForecastContent.swift#L13) | 13 | [LocationForecastPanel](../../Where/WhereUI/Sources/Forecasting/LocationForecastPanel.swift#L29) · [LocationForecastSummary](../../Where/WhereUI/Sources/Forecasting/LocationForecastSummary.swift#L28) |
| [LocationCardDayCount](../../Where/WhereUI/Sources/Primary/LocationCardDayCount.swift#L12) | 11 | [LocationCardEstimateSticker](../../Where/WhereUI/Sources/Primary/LocationCardEstimateSticker.swift#L19) · [RegionSummaryCard](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift#L353) |
| [LocationsEstimatePanel](../../Where/WhereUI/Sources/Primary/LocationsEstimatePanel.swift#L8) | 9 | [LocationsCardsView](../../Where/WhereUI/Sources/Primary/LocationsCardsView.swift#L145) · [LocationsStateContent](../../Where/WhereUI/Sources/Primary/LocationsStateContent.swift#L46) |
| [LocationsFlightNotice](../../Where/WhereUI/Sources/Primary/LocationsFlightNotice.swift#L9) | 18 | [LocationsCardsView](../../Where/WhereUI/Sources/Primary/LocationsCardsView.swift#L65) · [LocationsStateView](../../Where/WhereUI/Sources/Primary/LocationsStateView.swift#L17) |
| [PlannedStayHatch](../../Where/WhereUI/Sources/Primary/PlannedStayHatch.swift#L13) | 15 | [DayCell](../../Where/WhereUI/Sources/Primary/MonthGridView.swift#L526) · [PlannedPresenceJourneyBackground](../../Where/WhereUI/Sources/Primary/PlannedPresenceJourneyBackground.swift#L36) |
| [PresenceJourneyCardBorder](../../Where/WhereUI/Sources/Primary/PresenceJourneyCardBorder.swift#L10) | 12 | [PlannedPresenceJourneyRow](../../Where/WhereUI/Sources/Primary/PlannedPresenceJourneyRow.swift#L50) · [PresenceJourneyRow](../../Where/WhereUI/Sources/Primary/PresenceJourneyRow.swift#L65) |
| [RegionSummaryCard](../../Where/WhereUI/Sources/Primary/RegionSummaryCard.swift#L410) | 17 | [ElsewhereView](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift#L98) · [LocationsCardsView](../../Where/WhereUI/Sources/Primary/LocationsCardsView.swift#L82) · +3 |
| [FeatureDiscoveryBackground](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureDiscoveryBackground.swift#L9) | 10 | [DataCompatibilityView](../../Where/WhereUI/Sources/Compatibility/DataCompatibilityView.swift#L108) · [EstimatedTimeFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L127) · +6 |
| [FeatureGuidePage](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuidePage.swift#L11) | 9 | [PlacesYearFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PlacesYear/PlacesYearFeaturesView.swift#L12) · [PrivacyBackupsFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PrivacyBackups/PrivacyBackupsFeaturesView.swift#L12) · +1 |
| [FeatureGuidePanel](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureGuidePanel.swift#L12) | 14 | [EstimatedTimeFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L97) · [InsightsAccuracyFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesContent.swift#L47) · +4 |
| [FeatureMarketingPanel](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureMarketingPanel.swift#L12) | 12 | [EstimatedTimeFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L106) · [FeatureEstimatedTimeCalculationExample](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/FeatureEstimatedTimeCalculationExample.swift#L11) · +5 |
| [FeatureSettingsLink](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Shared/FeatureSettingsLink.swift#L8) | 8 | [EstimatedTimeFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L119) · [InsightsAccuracyFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesContent.swift#L57) · +4 |
| [WidgetExampleFrame](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/WidgetExampleFrame.swift#L15) | 8 | [FeatureHomeScreenExample](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/FeatureHomeScreenExample.swift#L15) · [FeatureLockScreenExample](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/FeatureLockScreenExample.swift#L21) |
| [LocationStatusRow](../../Where/WhereUI/Sources/Settings/LocationStatusRow.swift#L14) | 13 | [DeviceSettingsSection](../../Where/WhereUI/Sources/Settings/DeviceSettingsSection.swift#L69) · [RecordingFeaturesContent](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Recording/RecordingFeaturesContent.swift#L17) |
| [AppIconLoadingView](../../Where/WhereUI/Sources/Shared/AppIconLoadingView.swift#L15) | 10 | [CalendarContentView](../../Where/WhereUI/Sources/Primary/CalendarContentView.swift#L116) · [EvidenceListView](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift#L77) · +5 |
| [ManualEntryAuditSection](../../Where/WhereUI/Sources/Shared/ManualEntryAuditSection.swift#L10) | 12 | [DayRelabelView](../../Where/WhereUI/Sources/Elsewhere/DayRelabelView.swift#L215) · [ManualDayView](../../Where/WhereUI/Sources/Manual/ManualDayView.swift#L182) |
| [ObservableHostingView](../../Where/WhereUI/Sources/Shared/ObservableHostingView.swift#L29) | 8 | [AlertsSettingsDestination](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L14) · [DataSettingsDestination](../../Where/WhereUI/Sources/Settings/DataSettingsView.swift#L14) · +4 |
| [RegionToggleRow](../../Where/WhereUI/Sources/Shared/RegionToggleRow.swift#L10) | 7 | [DayRelabelView](../../Where/WhereUI/Sources/Elsewhere/DayRelabelView.swift#L110) · [ManualDayView](../../Where/WhereUI/Sources/Manual/ManualDayView.swift#L230) |
| [SavingStatusRow](../../Where/WhereUI/Sources/Shared/SavingStatusRow.swift#L12) | 5 | [AlertsSettingsView](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L196) · [DayRelabelView](../../Where/WhereUI/Sources/Elsewhere/DayRelabelView.swift#L134) · +2 |
| [SecurityPrintRosette](../../Where/WhereUI/Sources/Shared/SecurityPrintRosette.swift#L15) | 17 | [LocationForecastPanel](../../Where/WhereUI/Sources/Forecasting/LocationForecastPanel.swift#L51) · [LocationForecastSummarySurface](../../Where/WhereUI/Sources/Forecasting/LocationForecastSummarySurface.swift#L14) · +5 |
| [WhereDatePicker](../../Where/WhereUI/Sources/Shared/WhereDatePicker.swift#L42) | 11 | [AlertsSettingsView](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L61) · [ManualDayView](../../Where/WhereUI/Sources/Manual/ManualDayView.swift#L195) · +1 |
| [WhereThemePicker](../../Where/WhereUI/Sources/Shared/WhereThemePicker.swift#L14) | 14 | [AppearanceSettingsView](../../Where/WhereUI/Sources/Settings/AppearanceSettingsView.swift#L34) · [OnboardingThemeSelectionView](../../Where/WhereUI/Sources/Onboarding/OnboardingThemeSelectionView.swift#L35) |

## Independent screen, host or capture root

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [ContentView](../../Shared/Broadway/BroadwayCatalog/Sources/ContentView.swift#L6) | 10 | [BroadwayCatalogApp](../../Shared/Broadway/BroadwayCatalog/Sources/BroadwayApp.swift#L7) |
| [FlyoverExportContent](../../Shared/Flyover/Sources/FlyoverExportContent.swift#L9) | 11 | [FlyoverWebExporter](../../Shared/Flyover/Sources/FlyoverWebExporter.swift#L91) |
| [RelationshipView](../../Shared/Inspector/Sources/RelationshipView.swift#L22) | 10 | [RowDetailView](../../Shared/Inspector/Sources/RowDetailView.swift#L54) |
| [UpdateBrowserView](../../Shared/InstallerKitUI/Sources/UpdateBrowserView.swift#L26) | 10 | [UpdatePage](../../Shared/InstallerKitUI/Sources/AppUpdatesView.swift#L77) |
| [ScopeEventsView](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/ScopeEventsView.swift#L35) | 15 | [LogHierarchyView](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/LogHierarchyView.swift#L55) |
| [DeveloperCrashTestingView](../../Where/WhereUI/Sources/Developer/DeveloperCrashTestingView.swift#L7) | 11 | [DeveloperToolView](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift#L35) |
| [DeveloperToolView](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift#L22) | 5 | [DeveloperSurface](../../Where/WhereUI/Sources/Developer/DeveloperSurface.swift#L80) |
| [WhereFlyoverHost](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverHost.swift#L9) | 6 | [WhereFlyoverData](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverData.swift#L124) |
| [WhereFlyoverLogView](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverLogView.swift#L10) | 5 | [Flyover use](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverLogView.swift#L24) |
| [WhereFlyoverPresentationView](../../Where/WhereUI/Sources/Developer/Flyover/WhereFlyoverPresentationView.swift#L9) | 12 | [DeveloperOverlay](../../Where/WhereUI/Sources/Developer/DeveloperOverlay.swift#L144) |
| [ElsewhereView](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift#L53) | 18 | [MainTabs](../../Where/WhereUI/Sources/MainTabs.swift#L105) |
| [RegionDaysView](../../Where/WhereUI/Sources/Elsewhere/RegionDaysView.swift#L48) | 11 | [ElsewhereView](../../Where/WhereUI/Sources/Elsewhere/ElsewhereView.swift#L92) |
| [EvidenceDetailView](../../Where/WhereUI/Sources/Evidence/EvidenceDetailView.swift#L28) | 15 | [EvidenceListView](../../Where/WhereUI/Sources/Evidence/EvidenceListView.swift#L55) |
| [ResolutionView](../../Where/WhereUI/Sources/Resolution/ResolutionView.swift#L27) | 16 | [InsightsAccuracyFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesView.swift#L22) · [LocationsView](../../Where/WhereUI/Sources/Primary/LocationsView.swift#L170) |
| [EstimatedTimeFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/EstimatedTime/EstimatedTimeFeaturesView.swift#L12) | 7 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L191) |
| [ShareEvidenceFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Evidence/ShareEvidenceFeaturesView.swift#L43) | 15 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L185) |
| [InsightsAccuracyFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/InsightsAccuracy/InsightsAccuracyFeaturesView.swift#L13) | 10 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L193) |
| [PersonalizationFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Personalization/PersonalizationFeaturesView.swift#L29) | 18 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L198) |
| [PlacesYearFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PlacesYear/PlacesYearFeaturesView.swift#L11) | 7 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L162) |
| [PrivacyBackupsFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/PrivacyBackups/PrivacyBackupsFeaturesView.swift#L11) | 7 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L170) |
| [RecordingFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Recording/RecordingFeaturesView.swift#L12) | 10 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L164) |
| [SiriFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Siri/SiriFeaturesView.swift#L11) | 7 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L175) |
| [WidgetFeaturesView](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/WidgetFeaturesView.swift#L12) | 7 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L180) |
| [VisibleYearSettingsView](../../Where/WhereUI/Sources/Settings/VisibleYearSettingsView.swift#L12) | 17 | [SettingsDestinationView](../../Where/WhereUI/Sources/Settings/SettingsView.swift#L160) |

## Public view

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [BRootView](../../Shared/Broadway/BroadwayUI/Sources/BRootView.swift#L35) | 15 | [View](../../Shared/Broadway/BroadwayUI/Sources/BRootView.swift#L60) |
| [InspectorView](../../Shared/Inspector/Sources/InspectorView.swift#L28) | 6 | [WhereInspectorApplicationRuntime](../../Where/Where/Sources/WhereInspectorApplicationRuntime.swift#L127) |
| [LifecycleFailureView](../../Shared/LifecycleKitUI/Sources/LifecycleFailureView.swift#L14) | 9 | [LifecycleContainer](../../Shared/LifecycleKitUI/Sources/LifecycleContainer.swift#L380) · [WhereLifecycleFailureView](../../Where/WhereUI/Sources/Launch/WhereLifecycleFailureView.swift#L86) |
| [LogHierarchyView](../../Shared/Periscope/PeriscopeTools/Sources/Hierarchy/LogHierarchyView.swift#L20) | 10 | [PeriscopeViewer](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L145) |
| [OpenSpansView](../../Shared/Periscope/PeriscopeTools/Sources/Spans/OpenSpansView.swift#L19) | 6 | [DeveloperToolView](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift#L70) |
| [SpanHistoryView](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanHistoryView.swift#L22) | 18 | [PeriscopeViewer](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L78) |
| [SpanTreeView](../../Shared/Periscope/PeriscopeTools/Sources/Spans/SpanTreeView.swift#L22) | 11 | [PeriscopeViewer](../../Shared/Periscope/PeriscopeTools/Sources/Viewer/PeriscopeViewer.swift#L76) |
| [RegionMapView](../../Where/WhereUI/Sources/Developer/RegionMapView.swift#L35) | 7 | [DeveloperToolView](../../Where/WhereUI/Sources/Developer/DeveloperToolView.swift#L73) · [RegionViewerApp](../../Where/RegionViewer/Sources/RegionViewerApp.swift#L17) |
| [RootView](../../Where/WhereUI/Sources/RootView.swift#L111) | 7 | [RegularApplicationRuntime](../../Where/Where/Sources/RegularApplicationRuntime.swift#L263) |
| [WidgetCompatibilityView](../../Where/WhereUI/Sources/Widgets/WidgetCompatibilityView.swift#L15) | 16 | [TodayWidgetContent](../../Where/WhereWidgets/Sources/TodayWidget.swift#L50) · [YearTotalsWidgetContent](../../Where/WhereWidgets/Sources/YearTotalsWidget.swift#L50) |
| [YearTotalsWidgetView](../../Where/WhereUI/Sources/Widgets/YearTotalsWidgetView.swift#L29) | 18 | [FeatureHomeScreenExample](../../Where/WhereUI/Sources/Settings/FeaturePreviews/Widgets/FeatureHomeScreenExample.swift#L21) · [YearTotalsWidgetContent](../../Where/WhereWidgets/Sources/YearTotalsWidget.swift#L57) |

## Same-file caller

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [AlertsSettingsView](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L34) | 15 | [AlertsSettingsDestination](../../Where/WhereUI/Sources/Settings/AlertsSettingsView.swift#L17) |
| [WhereScreenRoot](../../Where/WhereUI/Sources/Shared/WhereScreenRoot.swift#L24) | 11 | [View](../../Where/WhereUI/Sources/Shared/WhereScreenRoot.swift#L46) |

## Fixture

| Named view | Body lines | Observed caller |
| --- | ---: | --- |
| [DeveloperOverlayPreview](../../Where/WhereUI/Sources/Developer/DeveloperOverlayPreview.swift#L16) | 11 | [Preview use](../../Where/WhereUI/Sources/Developer/DeveloperDemoModeRow.swift#L52) |
