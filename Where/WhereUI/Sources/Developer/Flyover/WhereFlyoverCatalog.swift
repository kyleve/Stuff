#if DEBUG
    import Flyover
    import PeriscopeTools

    /// Assembles the registrations declared beside each represented screen.
    @MainActor
    enum WhereFlyoverCatalog {
        static func make(
            world: WhereFlyoverWorld,
        ) -> FlyoverCatalog<WhereFlyoverScreenID> {
            FlyoverCatalog(
                groups: [
                    group(
                        id: "app",
                        title: "App flows",
                        root: LocationsView.flyoverID,
                        registrations: appRegistrations,
                        world: world,
                    ),
                    group(
                        id: "settings",
                        title: "Settings",
                        root: SettingsView.flyoverID,
                        registrations: settingsRegistrations,
                        world: world,
                    ),
                    group(
                        id: "developer",
                        title: "Developer tools",
                        root: DeveloperOverlay.flyoverID,
                        registrations: developerRegistrations,
                        world: world,
                    ),
                    group(
                        id: "widgets",
                        title: "Widgets",
                        root: TodayWidgetView.flyoverID,
                        registrations: widgetRegistrations,
                        world: world,
                    ),
                    group(
                        id: "snippets",
                        title: "Intent snippets",
                        root: DaysInRegionSnippetView.flyoverID,
                        registrations: snippetRegistrations,
                        world: world,
                    ),
                ],
                transitions: registrations.flatMap(\.transitions),
            )
        }

        static var registrations: [WhereFlyoverData] {
            appRegistrations
                + settingsRegistrations
                + developerRegistrations
                + widgetRegistrations
                + snippetRegistrations
        }

        private static var appRegistrations: [WhereFlyoverData] {
            [
                LaunchSplashView.flyoverData,
                OnboardingView.flyoverData,
                RegionPickerView.flyoverData,
                RegionCustomizeView.flyoverData,
                LocationsView.flyoverData,
                CalendarContentView.flyoverData,
                ElsewhereView.flyoverData,
                RegionDaysView.flyoverData,
                ResolutionView.flyoverData,
                ManualDayView.flyoverData,
                DayRelabelView.flyoverData,
                AbruptChangeDetailView.flyoverData,
                FlightDayDetailView.flyoverData,
                YearView.flyoverData,
                CalendarContentView.yearFlyoverData,
                PresenceTimelineList.flyoverData,
                RecentActivitySummaryView.flyoverData,
            ]
        }

        private static var settingsRegistrations: [WhereFlyoverData] {
            [
                SettingsView.flyoverData,
                EvidenceListView.flyoverData,
                EvidenceDetailView.flyoverData,
                AddEvidenceView.flyoverData,
                LoggedDaysView.flyoverData,
                RegionsSettingsView.flyoverData,
                DevicesSettingsView.flyoverData,
                AlertsSettingsView.flyoverData,
                AppearanceSettingsView.flyoverData,
                AppIconView.flyoverData,
                VisibleYearSettingsView.flyoverData,
                DataSettingsView.flyoverData,
                AboutSettingsView.flyoverData,
                LicenseView.flyoverData,
            ]
        }

        private static var developerRegistrations: [WhereFlyoverData] {
            [
                DeveloperOverlay.flyoverData,
                WhereFlyoverLogView.flyoverData,
                OpenSpansView.flyoverData,
                WhereFlyoverSwiftDataView.flyoverData,
                RegionMapView.flyoverData,
            ]
        }

        private static var widgetRegistrations: [WhereFlyoverData] {
            [
                TodayWidgetView.flyoverData,
                TodayInlineAccessoryView.flyoverData,
                TodayCircularAccessoryView.flyoverData,
                MacSummaryWidgetView.flyoverData,
                YearTotalsWidgetView.flyoverData,
                YearTotalsRectangularAccessoryView.flyoverData,
            ]
        }

        private static var snippetRegistrations: [WhereFlyoverData] {
            [
                DaysInRegionSnippetView.flyoverData,
                RegionsSnippetView.flyoverData,
            ]
        }

        private static func group(
            id: String,
            title: String,
            root: WhereFlyoverScreenID,
            registrations: [WhereFlyoverData],
            world: WhereFlyoverWorld,
        ) -> FlyoverGroup<WhereFlyoverScreenID> {
            FlyoverGroup(
                id: FlyoverGroupID(id),
                title: title,
                root: root,
                screens: registrations.map { $0.screen(in: world) },
            )
        }
    }
#endif
