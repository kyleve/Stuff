#if DEBUG
    import Flyover
    import PeriscopeCore
    import PeriscopeTools
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// WhereUI's explicit, exhaustive Flyover registration.
    @MainActor
    enum WhereFlyoverCatalog {
        static func make(
            world: WhereFlyoverWorld,
        ) -> FlyoverCatalog<WhereFlyoverScreenID> {
            let locationsState = WhereFlyoverLocationsState(report: world.report)
            return FlyoverCatalog(
                groups: [
                    appGroup(world: world, locationsState: locationsState),
                    settingsGroup(world: world),
                    developerGroup(world: world),
                    widgetsGroup(),
                    snippetsGroup(world: world),
                ],
                transitions: transitions,
            )
        }

        private static func appGroup(
            world: WhereFlyoverWorld,
            locationsState: WhereFlyoverLocationsState,
        ) -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID("app"),
                title: "App flows",
                root: .locations,
                screens: [
                    snapshotScreen(
                        .launch,
                        title: "Launch",
                        navigationContainer: .none,
                        provider: LaunchSplashView.self,
                    ),
                    snapshotScreen(
                        .onboarding,
                        title: "Onboarding",
                        navigationContainer: .none,
                        provider: OnboardingView.self,
                    ),
                    regionPickerScreen(world: world),
                    regionCustomizeScreen(world: world),
                    locationsScreen(world: world, state: locationsState),
                    snapshotScreen(
                        .regionCalendar,
                        title: "Region Calendar",
                        provider: CalendarContentView.self,
                    ),
                    snapshotScreen(.elsewhere, title: "Elsewhere", provider: ElsewhereView.self),
                    snapshotScreen(
                        .regionDays,
                        title: "Region Days",
                        provider: RegionDaysView.self,
                    ),
                    snapshotScreen(
                        .resolution,
                        title: "Resolve",
                        provider: ResolutionView.self,
                    ),
                    snapshotScreen(
                        .manualDay,
                        title: "Manual Day",
                        provider: ManualDayView.self,
                    ),
                    snapshotScreen(
                        .dayRelabel,
                        title: "Relabel Day",
                        provider: DayRelabelView.self,
                    ),
                    abruptChangeScreen(world: world),
                    snapshotScreen(
                        .flightDay,
                        title: "Flight Day",
                        provider: FlightDayDetailView.self,
                    ),
                    yearScreen(world: world),
                    snapshotScreen(
                        .calendar,
                        title: "Calendar",
                        provider: CalendarContentView.self,
                    ),
                    snapshotScreen(
                        .timeline,
                        title: "Timeline",
                        provider: PresenceTimelineList.self,
                    ),
                    snapshotScreen(
                        .recentActivity,
                        title: "Recent Activity",
                        provider: RecentActivitySummaryView.self,
                    ),
                ],
            )
        }

        private static func settingsGroup(
            world: WhereFlyoverWorld,
        ) -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID("settings"),
                title: "Settings",
                root: .settings,
                screens: [
                    hostedScreen(
                        .settings,
                        title: "Settings",
                        world: world,
                        navigationContainer: .none,
                    ) {
                        SettingsView(report: world.report)
                    },
                    evidenceListScreen(world: world),
                    evidenceDetailScreen(world: world),
                    addEvidenceScreen(world: world),
                    snapshotScreen(
                        .loggedDays,
                        title: "Logged Days",
                        provider: LoggedDaysView.self,
                    ),
                    hostedScreen(.regions, title: "Regions", world: world) {
                        RegionsSettingsView(
                            usedThisYear: Set(
                                world.report.report.map { Array($0.totals.keys) } ?? [],
                            ),
                        )
                    },
                    hostedScreen(
                        .locationSettings,
                        title: "Location Settings",
                        world: world,
                    ) {
                        LocationSettingsView()
                    },
                    hostedScreen(
                        .alertsSettings,
                        title: "Alerts Settings",
                        world: world,
                    ) {
                        AlertsSettingsView(
                            report: world.report,
                            reminders: world.reminders,
                        )
                    },
                    hostedScreen(
                        .appearanceSettings,
                        title: "Appearance Settings",
                        world: world,
                    ) {
                        AppearanceSettingsView()
                    },
                    snapshotScreen(.appIcon, title: "App Icon", provider: AppIconView.self),
                    hostedScreen(
                        .visibleYear,
                        title: "Visible Year",
                        world: world,
                    ) {
                        VisibleYearSettingsView(report: world.report)
                    },
                    hostedScreen(.backup, title: "Backup", world: world) {
                        BackupSettingsView(backup: world.backup)
                    },
                    hostedScreen(.dataSettings, title: "Data", world: world) {
                        DataSettingsView(report: world.report)
                    },
                    snapshotScreen(
                        .about,
                        title: "About",
                        provider: AboutSettingsView.self,
                    ),
                    snapshotScreen(
                        .license,
                        title: "License",
                        provider: LicenseView.self,
                    ),
                ],
            )
        }

        private static func developerGroup(
            world: WhereFlyoverWorld,
        ) -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID("developer"),
                title: "Developer tools",
                root: .developerTools,
                screens: [
                    snapshotScreen(
                        .developerOverlay,
                        title: "Developer Overlay",
                        navigationContainer: .none,
                        provider: DeveloperOverlay.self,
                    ),
                    hostedScreen(
                        .developerTools,
                        title: "Developer Tools",
                        world: world,
                        navigationContainer: .none,
                    ) {
                        DeveloperToolsView()
                    },
                    hostedScreen(.logs, title: "Logs", world: world) {
                        WhereFlyoverLogView(world: world)
                    },
                    hostedScreen(.openSpans, title: "Open Spans", world: world) {
                        OpenSpansView(system: .shared)
                    },
                    hostedScreen(
                        .swiftDataInspector,
                        title: "SwiftData Inspector",
                        world: world,
                        navigationContainer: .none,
                    ) {
                        WhereFlyoverSwiftDataView(world: world)
                    },
                    snapshotScreen(
                        .regionMap,
                        title: "Region Map",
                        provider: RegionMapView.self,
                    ),
                ],
            )
        }

        private static func widgetsGroup() -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID("widgets"),
                title: "Widgets",
                root: .todayWidget,
                screens: [
                    snapshotScreen(
                        .todayWidget,
                        title: "Today Widget",
                        viewport: .fixed(CGSize(width: 338, height: 158)),
                        navigationContainer: .none,
                        provider: TodayWidgetView.self,
                    ),
                    snapshotScreen(
                        .todayInline,
                        title: "Today Inline",
                        viewport: .fixed(CGSize(width: 338, height: 60)),
                        navigationContainer: .none,
                        provider: TodayInlineAccessoryView.self,
                    ),
                    snapshotScreen(
                        .todayCircular,
                        title: "Today Circular",
                        viewport: .fixed(CGSize(width: 76, height: 76)),
                        navigationContainer: .none,
                        provider: TodayCircularAccessoryView.self,
                    ),
                    snapshotScreen(
                        .yearTotalsWidget,
                        title: "Year Totals Widget",
                        viewport: .fixed(CGSize(width: 338, height: 158)),
                        navigationContainer: .none,
                        provider: YearTotalsWidgetView.self,
                    ),
                    snapshotScreen(
                        .yearTotalsRectangular,
                        title: "Year Totals Rectangular",
                        viewport: .fixed(CGSize(width: 338, height: 76)),
                        navigationContainer: .none,
                        provider: YearTotalsRectangularAccessoryView.self,
                    ),
                ],
            )
        }

        private static func snippetsGroup(
            world: WhereFlyoverWorld,
        ) -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID("snippets"),
                title: "Intent snippets",
                root: .daysSnippet,
                screens: [
                    hostedScreen(
                        .daysSnippet,
                        title: "Days in Region Snippet",
                        world: world,
                        viewport: .fixed(CGSize(width: 360, height: 150)),
                        navigationContainer: .none,
                    ) {
                        DaysInRegionSnippetView(
                            snapshot: DaysInRegionSnapshot(
                                region: .california,
                                year: PreviewSupport.year,
                                dayCount: 132,
                            ),
                        )
                    },
                    hostedScreen(
                        .regionsSnippet,
                        title: "Regions Snippet",
                        world: world,
                        viewport: .fixed(CGSize(width: 360, height: 190)),
                        navigationContainer: .none,
                    ) {
                        RegionsSnippetView.today(regions: [.california, .newYork])
                    },
                ],
            )
        }

        private static func locationsScreen(
            world: WhereFlyoverWorld,
            state: WhereFlyoverLocationsState,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: .locations,
                title: "Locations",
                navigationContainer: .none,
                variants: [
                    hostedVariant(id: "demo", title: "Demo data", world: world) {
                        LocationsView(report: state.report)
                    },
                    hostedVariant(id: "empty", title: "Empty", world: world) {
                        LocationsView(report: PreviewSupport.emptyYearReportModel())
                    },
                ],
                reset: state.reset,
            ) {
                WhereFlyoverLocationsControls(state: state)
            }
        }

        private static func yearScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: .year,
                title: "Your Year",
                navigationContainer: .none,
                variants: [
                    hostedVariant(id: "calendar", title: "Calendar", world: world) {
                        YearView(report: world.report, initialMode: .calendar)
                    },
                    hostedVariant(id: "timeline", title: "Timeline", world: world) {
                        YearView(report: world.report, initialMode: .timeline)
                    },
                ],
            )
        }

        private static func regionPickerScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: .regionPicker,
                title: "Region Picker",
                variants: [
                    hostedVariant(id: "list", title: "List", world: world) {
                        RegionPickerView(
                            model: PreviewSupport.primaryRegionSelectionModel(),
                            initialMode: .list,
                        )
                    },
                    hostedVariant(id: "map", title: "Map", world: world) {
                        RegionPickerView(
                            model: PreviewSupport.primaryRegionSelectionModel(),
                            initialMode: .map,
                        )
                    },
                ],
            )
        }

        private static func regionCustomizeScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            hostedScreen(
                .regionCustomize,
                title: "Customize Regions",
                world: world,
            ) {
                RegionCustomizeView(
                    model: PreviewSupport.primaryRegionSelectionModel(),
                )
            }
        }

        private static func abruptChangeScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            hostedScreen(.abruptChange, title: "Abrupt Change", world: world) {
                AbruptChangeDetailView(
                    issue: AbruptChangeIssue(
                        earlierDay: DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: world.report.calendar,
                            regions: [.california],
                        ),
                        laterDay: DayPresence(
                            date: PreviewSupport.referenceNow.addingTimeInterval(86400),
                            in: world.report.calendar,
                            regions: [.newYork],
                        ),
                    ),
                    report: world.report,
                    resolve: PreviewSupport.resolveModel(),
                )
            }
        }

        private static func evidenceListScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: .evidenceList,
                title: "Evidence",
                variants: [
                    hostedVariant(id: "loaded", title: "Loaded", world: world) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(
                                state: .loaded(PreviewSupport.sampleEvidence()),
                            ),
                        )
                    },
                    hostedVariant(id: "empty", title: "Empty", world: world) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(state: .empty),
                        )
                    },
                    hostedVariant(id: "failed", title: "Failed", world: world) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(
                                state: .failed("The attachment index is unavailable."),
                            ),
                        )
                    },
                ],
            )
        }

        private static func evidenceDetailScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            hostedScreen(.evidenceDetail, title: "Evidence Detail", world: world) {
                EvidenceDetailView(model: PreviewSupport.evidenceDetailModel(
                    kind: .planeTicket,
                    contentType: .plainText,
                    blob: Data("SFO → JFK · 14C".utf8),
                ))
            }
        }

        private static func addEvidenceScreen(
            world: WhereFlyoverWorld,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            hostedScreen(.addEvidence, title: "Add Evidence", world: world) {
                AddEvidenceView(model: PreviewSupport.addEvidenceModel())
            }
        }

        private static func snapshotScreen<Provider: SnapshotProviding>(
            _ id: WhereFlyoverScreenID,
            title: String,
            viewport: FlyoverViewport = .device,
            navigationContainer: FlyoverNavigationContainer = .stack,
            provider _: Provider.Type,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: id,
                title: title,
                viewport: viewport,
                navigationContainer: navigationContainer,
                variants: Provider.snapshots.enumerated().map { index, snapshotCase in
                    FlyoverVariant(
                        id: FlyoverVariantID("\(id.rawValue).\(index)"),
                        snapshotCase: snapshotCase,
                    )
                },
            )
        }

        private static func hostedScreen(
            _ id: WhereFlyoverScreenID,
            title: String,
            world: WhereFlyoverWorld,
            viewport: FlyoverViewport = .device,
            navigationContainer: FlyoverNavigationContainer = .stack,
            @ViewBuilder content: @escaping @MainActor () -> some View,
        ) -> FlyoverScreen<WhereFlyoverScreenID> {
            FlyoverScreen(
                id: id,
                title: title,
                viewport: viewport,
                navigationContainer: navigationContainer,
                variants: [
                    hostedVariant(id: "default", title: "Default", world: world, content: content),
                ],
            )
        }

        private static func hostedVariant(
            id: String,
            title: String,
            world: WhereFlyoverWorld,
            @ViewBuilder content: @escaping @MainActor () -> some View,
        ) -> FlyoverVariant {
            FlyoverVariant(id: FlyoverVariantID(id), title: title) {
                WhereFlyoverHost(world: world, content: content)
            }
        }

        private static let transitions: [FlyoverTransition<WhereFlyoverScreenID>] = [
            FlyoverTransition(from: .locations, to: .regionCalendar, kind: .push),
            FlyoverTransition(from: .locations, to: .elsewhere, kind: .push),
            FlyoverTransition(from: .locations, to: .resolution, kind: .modal),
            FlyoverTransition(from: .elsewhere, to: .regionDays, kind: .push),
            FlyoverTransition(from: .regionDays, to: .dayRelabel, kind: .push),
            FlyoverTransition(from: .resolution, to: .manualDay, kind: .push),
            FlyoverTransition(from: .resolution, to: .dayRelabel, kind: .push),
            FlyoverTransition(from: .resolution, to: .abruptChange, kind: .push),
            FlyoverTransition(from: .resolution, to: .flightDay, kind: .push),
            FlyoverTransition(from: .abruptChange, to: .dayRelabel, kind: .push),
            FlyoverTransition(from: .flightDay, to: .dayRelabel, kind: .push),
            FlyoverTransition(from: .year, to: .recentActivity, kind: .modal),
            FlyoverTransition(from: .settings, to: .evidenceList, kind: .push),
            FlyoverTransition(from: .settings, to: .loggedDays, kind: .push),
            FlyoverTransition(from: .settings, to: .regions, kind: .modal),
            FlyoverTransition(from: .settings, to: .locationSettings, kind: .push),
            FlyoverTransition(from: .settings, to: .alertsSettings, kind: .push),
            FlyoverTransition(from: .settings, to: .appearanceSettings, kind: .push),
            FlyoverTransition(from: .settings, to: .visibleYear, kind: .push),
            FlyoverTransition(from: .settings, to: .backup, kind: .push),
            FlyoverTransition(from: .settings, to: .dataSettings, kind: .push),
            FlyoverTransition(from: .settings, to: .about, kind: .push),
            FlyoverTransition(from: .evidenceList, to: .evidenceDetail, kind: .push),
            FlyoverTransition(from: .evidenceList, to: .addEvidence, kind: .modal),
            FlyoverTransition(from: .loggedDays, to: .manualDay, kind: .modal),
            FlyoverTransition(from: .appearanceSettings, to: .appIcon, kind: .modal),
            FlyoverTransition(from: .about, to: .license, kind: .push),
            FlyoverTransition(from: .developerTools, to: .logs, kind: .push),
            FlyoverTransition(from: .developerTools, to: .openSpans, kind: .push),
            FlyoverTransition(
                from: .developerTools,
                to: .swiftDataInspector,
                kind: .push,
            ),
            FlyoverTransition(from: .developerTools, to: .regionMap, kind: .push),
        ]
    }
#endif
