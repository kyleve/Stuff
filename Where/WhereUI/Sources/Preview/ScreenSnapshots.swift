#if DEBUG
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    // Snapshot matrices for the top-level WhereUI screens, driving both the
    // `#Preview` cutsheets and the `WhereUISnapshotTests` image tests off one
    // declaration. Fixtures come from `PreviewSupport`; `whereSnapshot(...)` seeds
    // the Broadway root so trait-aware stylesheet tokens resolve.

    extension PrimaryView: SnapshotProviding {
        /// The raised settle floor on `Loaded` outlasts the iOS 26 glass toolbar
        /// material adaptation (seen pre-adaptation once on `Loaded_iPhone`) —
        /// same mechanism as `RootView.LoggedIn`.
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .screenDefaults,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                PrimaryView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "ElsewhereOnly", configurations: .phoneLightDark) {
                PrimaryView(report: PreviewSupport.elsewhereOnlyYearReportModel())
            }
            whereSnapshot(name: "MissingDays", configurations: .phoneLightDark) {
                PrimaryView(report: PreviewSupport.missingDaysYearReportModel())
            }
        }
    }

    extension SecondaryView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .screenDefaults) {
                SecondaryView(report: PreviewSupport.loadedYearReportModel())
            }
        }
    }

    extension SettingsView: SnapshotProviding {
        /// The extra right-to-left variant exercises the RTL configuration axis
        /// on a directional screen (leading labels, trailing values/toggles).
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .screenDefaults + [
                    SnapshotConfiguration(layoutDirection: .rightToLeft, device: .iPhone),
                ],
            ) {
                SettingsView(report: PreviewSupport.loadedYearReportModel())
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
            }
        }
    }

    extension ResolutionView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithIssues", configurations: .screenDefaults) {
                ResolutionView(
                    report: PreviewSupport.loadedYearReportModel(),
                    resolve: PreviewSupport.resolveModel(),
                )
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                ResolutionView(
                    report: PreviewSupport.loadedYearReportModel(),
                    resolve: PreviewSupport.resolveModel(seededWithIssues: false),
                )
            }
        }
    }

    extension RegionDaysView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .screenDefaults) {
                NavigationStack {
                    RegionDaysView(
                        region: .other,
                        report: PreviewSupport.elsewhereOnlyYearReportModel(),
                    )
                }
            }
        }
    }

    extension RegionMapView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                NavigationStack { RegionMapView() }
            }
        }
    }

    extension DayRelabelView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                NavigationStack {
                    DayRelabelView(
                        day: DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.other],
                        ),
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
            whereSnapshot(name: "WithAudit", configurations: .phoneLightDark) {
                NavigationStack {
                    DayRelabelView(
                        day: DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.california],
                            isAuthoritative: true,
                            audit: ManualEntryAudit(
                                recordedAt: PreviewSupport.referenceNow,
                                note: "Corrected after reviewing my boarding pass.",
                                location: CapturedLocation(
                                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                                    horizontalAccuracy: 12,
                                    timestamp: PreviewSupport.referenceNow,
                                ),
                            ),
                        ),
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
        }
    }

    extension RecentActivitySummaryView: SnapshotProviding {
        // A NavigationStack + ScrollView sheet is a screen, not an intrinsic
        // component: greedy containers have no meaningful `sizeThatFits`, so
        // intrinsic sizing would measure just the pinned window picker.
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .screenDefaults) {
                RecentActivitySummaryView(
                    model: PreviewSupport.recentActivityModel(
                        state: .loaded("You were in California, then New York."),
                    ),
                )
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                RecentActivitySummaryView(model: PreviewSupport.recentActivityModel(state: .empty))
            }
            whereSnapshot(name: "Unavailable", configurations: .phoneLightDark) {
                RecentActivitySummaryView(
                    model: PreviewSupport.recentActivityModel(
                        state: .unavailable(.appleIntelligenceNotEnabled),
                    ),
                )
            }
            whereSnapshot(name: "Failed", configurations: .phoneLightDark) {
                RecentActivitySummaryView(
                    model: PreviewSupport
                        .recentActivityModel(state: .failed("Something went wrong.")),
                )
            }
        }
    }

    extension PresenceTimelineView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .screenDefaults) {
                PresenceTimelineView(report: PreviewSupport.loadedYearReportModel())
            }
        }
    }

    extension CalendarView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithData", configurations: .screenDefaults) {
                CalendarView(report: PreviewSupport.loadedYearReportModel())
            }
            // The whole sample year in one image: the full-content frame
            // measures the scroll view's content height, so all 12 lazy months
            // materialize and nothing scrolls. Wraps `CalendarYearGrid` — the
            // scrollable content — not `CalendarView` itself, whose
            // `NavigationStack` chrome defeats content measurement (see
            // `Frame.fullContent`).
            whereSnapshot(
                name: "FullYear",
                configurations: [
                    SnapshotConfiguration(device: .fullContent(name: "fullHeight", width: 402)),
                ],
            ) {
                CalendarYearGrid(months: fullYearMonths(), focusedRegion: nil) { _ in }
            }
        }

        /// The sample year's month grids, laid out synchronously (fixture
        /// failure is a programmer error, not a state to render).
        private static func fullYearMonths() -> [CalendarMonth] {
            let report = PreviewSupport.loadedYearReportModel()
            guard let yearReport = report.report else {
                preconditionFailure("The loaded preview fixture must carry a year report.")
            }
            do {
                return try yearReport.calendarMonths(
                    calendar: report.calendar,
                    referenceDate: report.referenceDate,
                    missingDates: report.missingDayKeys,
                    evidenceDays: report.evidenceDayKeys,
                    focusedRegion: nil,
                )
            } catch {
                preconditionFailure("The sample year failed to lay out calendar months: \(error)")
            }
        }
    }

    extension AppIconView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults, settle: .immediate) {
                NavigationStack { AppIconView(model: .preview()) }
            }
        }
    }

    extension LoggedDaysView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .screenDefaults) {
                LoggedDaysView(
                    report: PreviewSupport.loadedYearReportModel(),
                    model: PreviewSupport
                        .loggedDaysModel(state: .loaded(PreviewSupport.sampleManualDays())),
                )
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                LoggedDaysView(
                    report: PreviewSupport.loadedYearReportModel(),
                    model: PreviewSupport.loggedDaysModel(state: .empty),
                )
            }
            whereSnapshot(name: "Failed", configurations: .phoneLightDark) {
                LoggedDaysView(
                    report: PreviewSupport.loadedYearReportModel(),
                    model: PreviewSupport.loggedDaysModel(state: .failed("iCloud is unavailable.")),
                )
            }
        }
    }

    extension ManualDayView: SnapshotProviding {
        /// A plain add (`prefill: nil`) would default its date pickers to the
        /// real current date and churn the references daily, so the add cases
        /// prefill a fixed single day instead — same form, deterministic date.
        private static var addPrefill: MissingDayRange {
            let day = CalendarDay(from: PreviewSupport.referenceNow, in: .current)
            return MissingDayRange(start: day, end: day, dayCount: 1)
        }

        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Add", configurations: .screenDefaults) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .add(prefill: addPrefill),
                        showsCancelButton: false,
                    )
                }
            }
            whereSnapshot(name: "AddWithCancel", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .add(prefill: addPrefill),
                        showsCancelButton: true,
                    )
                }
            }
            whereSnapshot(name: "EditPlain", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .edit(DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.california],
                        )),
                        showsCancelButton: true,
                    )
                }
            }
            whereSnapshot(name: "EditAuthoritative", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .edit(DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.canada],
                            isAuthoritative: true,
                            audit: ManualEntryAudit(
                                recordedAt: PreviewSupport.referenceNow,
                                note: "Boarding pass.",
                                location: nil,
                            ),
                        )),
                        showsCancelButton: true,
                    )
                }
            }
        }
    }

    extension DeveloperToolsView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                DeveloperToolsView()
                    .environment(PreviewSupport.loadedSession())
            }
        }
    }

    extension DeveloperOverlay: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Collapsed", configurations: .phoneLightDark) {
                DeveloperOverlay()
                    .environment(PreviewSupport.loadedSession())
            }
        }
    }
#endif
