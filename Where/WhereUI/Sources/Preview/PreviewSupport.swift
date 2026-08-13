#if DEBUG
    import CreditKit
    import Foundation
    import PeriscopeCore
    import RegionKit
    @_spi(Testing) import WhereCore

    /// Preview/test fixtures for `WhereUI`. Provides a synchronous sample
    /// `YearReport` (for static display previews) plus ready-to-render
    /// `WhereModel`/`WhereSession` values backed by in-memory `WhereServices`
    /// (for interactive previews that exercise the live read path) — none of it
    /// touches disk, CloudKit, or CoreLocation.
    ///
    /// Logged-in views read `@Environment(WhereSession.self)`, so they take a
    /// `*Session()` fixture; the app-level shell (Settings reset, onboarding)
    /// reads `WhereModel`, so it takes a `*Model()` fixture.
    public enum PreviewSupport {
        public static let year = 2026

        /// A private logging system for fixtures, so a preview's or snapshot's
        /// log sinks never join the process-wide pipeline (and a long-running
        /// snapshot host doesn't accumulate them).
        @MainActor
        public static let logSystem = Periscope(
            configuration: Periscope.Configuration(),
            sinks: [],
        )

        /// Fixed "now" for previews and snapshots — midday (Pacific) in the middle
        /// of the sample year, so "today" chrome (the calendar's current-day
        /// highlight, formatted dates, missing-day math) renders identically
        /// whenever a preview or snapshot runs. Snapshot references would
        /// otherwise churn every real-world day.
        public static let referenceNow: Date = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            return calendar.date(from: DateComponents(year: year, month: 7, day: 15, hour: 12))!
        }()

        /// How many days each region gets in the sample data. CA/NY heavy so
        /// the primary/secondary split is obvious.
        static let spread: [RegionDays] = [
            RegionDays(region: .california, days: 148),
            RegionDays(region: .newYork, days: 96),
            RegionDays(region: .canada, days: 21),
            RegionDays(region: .europeanUnion, days: 13),
            RegionDays(region: .other, days: 7),
        ]

        /// A believable `YearReport` built directly (no services needed), so
        /// `#Preview` blocks can render real content synchronously.
        public static func sampleReport() -> YearReport {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!

            var days: [DayPresence] = []
            var totals: [Region: Int] = [:]
            var dayOffset = 0
            for entry in spread {
                totals[entry.region] = entry.days
                for _ in 0 ..< entry.days {
                    let date = calendar.date(byAdding: .day, value: dayOffset, to: startOfYear)!
                    days.append(DayPresence(date: date, in: calendar, regions: [entry.region]))
                    dayOffset += 1
                }
            }
            return YearReport(year: year, days: days, totals: totals)
        }

        /// Memory-backed preferences shared by every preview fixture, honoring
        /// the no-disk contract: a preview must never read or write the host's
        /// real defaults, or a fixture's state outlives the preview and leaks
        /// into the next one.
        @MainActor
        public static func previewPreferences() -> WherePreferences {
            WherePreferences(store: InMemoryKeyValueStore())
        }

        /// In-memory, no-op-backed services shared by every preview fixture.
        /// Every scheduler seam is a no-op — the issue-alert one included, so the
        /// launch sequence's `issue-alerts` step can't suspend on a real
        /// `UNUserNotificationCenter` permission prompt in previews/tests.
        @MainActor
        public static func previewServices() -> WhereServices {
            previewServices(locationSource: ScriptedLocationSource())
        }

        @MainActor
        private static func previewServices(locationSource: any LocationSource) -> WhereServices {
            WhereServices(
                store: try! SwiftDataStore.inMemory(),
                locationSource: locationSource,
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                issueAlertScheduler: NoopDataIssueAlertScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
                // Pinned for the reason `referenceNow` exists: without it every
                // collaborator built here — the data-issue scanner above all —
                // computes against the wall clock, so a snapshot of anything
                // day-relative drifts every real-world day. That is not
                // hypothetical: `resolution.Empty_iPhone` rendered its
                // missing-days row as "Jan 1 – Jul 25 / 206 days" because the
                // reference happened to be recorded on July 25, and it had been
                // silently wrong on every day since — passing only because two
                // digit glyphs fall under the pixel threshold.
                now: { referenceNow },
            )
        }

        // MARK: - Coordinator (always-on views)

        /// A ready-to-render `WhereSession` coordinator over in-memory services,
        /// for the always-on views that read `@Environment(WhereSession.self)`
        /// (Settings, onboarding). It holds no report — that lives on
        /// `YearReportModel` now — so the report/year previews take a
        /// `*YearReportModel()` fixture instead.
        @MainActor
        public static func loadedSession() -> WhereSession {
            WhereSession(services: previewServices(), preferences: previewPreferences())
        }

        /// Current-device session whose permission must be promoted in Settings.app.
        @MainActor
        static func whenInUseSession() -> WhereSession {
            WhereSession(
                services: previewServices(
                    locationSource: ScriptedLocationSource(authorizationStatus: .whenInUse),
                ),
                preferences: previewPreferences(),
            )
        }

        /// A persisted warning generation for rendering the Settings banner without a view-only
        /// flag. The production model reads the same `WherePreferences` registration.
        @MainActor
        static func recordingConfigurationWarningModel()
            -> RecordingConfigurationWarningModel
        {
            let preferences = previewPreferences()
            var registration = preferences.recordingConfigurationWarningRegistration
            registration.register(isWarningConditionActive: true)
            preferences.recordingConfigurationWarningRegistration = registration
            return RecordingConfigurationWarningModel(preferences: preferences)
        }

        /// Current + left-behind device rows for the Devices screen.
        public static func recordingDeviceConfigurations() -> [RecordingDeviceConfiguration] {
            recordingDeviceConfigurations(automaticRecordingEnabled: true)
        }

        static func recordingDeviceConfigurations(
            automaticRecordingEnabled: Bool,
        ) -> [RecordingDeviceConfiguration] {
            let remoteID = RecordingDeviceID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            )
            return [
                RecordingDeviceConfiguration(
                    device: RecordingDevice(
                        id: InstallationRecordingContext.testing.currentDevice.id,
                        systemName: "iPhone",
                        nickname: "My iPhone",
                        kind: .phone,
                        registeredAt: referenceNow.addingTimeInterval(-90 * 24 * 60 * 60),
                        lastSeenAt: referenceNow,
                        removedAt: nil,
                        status: automaticRecordingEnabled ? .recording : .off,
                    ),
                    isCurrentDevice: true,
                    localAutomaticRecordingEnabled: automaticRecordingEnabled,
                ),
                RecordingDeviceConfiguration(
                    device: RecordingDevice(
                        id: remoteID,
                        systemName: "iPad",
                        nickname: "Home iPad",
                        kind: .tablet,
                        registeredAt: referenceNow.addingTimeInterval(-60 * 24 * 60 * 60),
                        lastSeenAt: referenceNow.addingTimeInterval(-2 * 24 * 60 * 60),
                        removedAt: nil,
                        status: .off,
                    ),
                    isCurrentDevice: false,
                    localAutomaticRecordingEnabled: nil,
                ),
            ]
        }

        // MARK: - Settings models (reminders / backup sub-screens)

        /// A reminders/summary editing model over in-memory services, for the
        /// Settings reminders and alerts sub-screen previews/tests.
        @MainActor
        public static func remindersSettingsModel() -> RemindersSettingsModel {
            RemindersSettingsModel(
                services: previewServices(),
                preferences: previewPreferences(),
            )
        }

        /// A backup export/import model over in-memory services, for the Settings
        /// backup sub-screen previews/tests.
        @MainActor
        public static func backupModel() -> BackupModel {
            BackupModel(services: previewServices())
        }

        // MARK: - Build metadata (About sub-screen)

        /// Build metadata as the shipping app carries it — the About screen's
        /// normal state. A preview or test bundle is never stamped, so this can't
        /// come from the real bundle.
        public static func stampedBuildInfo(isDirty: Bool = false) -> BuildInfo {
            BuildInfo(infoDictionary: [
                "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "42",
                "WhereGitSHA": "a18a9309c5d6",
                "WhereGitStatus": isDirty ? "dirty" : "clean",
                "WhereConfiguration": "Release",
                "WhereSwiftOptimizationLevel": "-O",
                "WhereSwiftCompilationMode": "wholemodule",
            ])
        }

        /// Build metadata from a bundle the stamp script never ran on — the
        /// RegionViewer, an extension, a test host.
        public static func unstampedBuildInfo() -> BuildInfo {
            BuildInfo(infoDictionary: [:])
        }

        /// An attribution report shaped like the generated one: a linked library
        /// and a development tool, so both About sections render. Only the app
        /// target ships a real report, so a preview or test bundle can't read one.
        public static func sampleAttribution() -> AttributionManifest {
            AttributionManifest(credits: [
                sampleCredit(noticeText: sampleNotice),
                SoftwareCredit(
                    name: "swiftui-pro",
                    kind: .developmentTool,
                    version: "61b74001b64b",
                    homepageURL: URL(string: "https://github.com/twostraws/swiftui-agent-skill"),
                    license: LicenseNotice(name: "MIT License", text: sampleNotice),
                ),
            ])
        }

        /// The library credit from ``sampleAttribution()``, with its notice text
        /// substitutable: pass `""` for the no-notice state a hand-edited report
        /// could reach, which the generator itself refuses to write.
        public static func sampleCredit(noticeText: String) -> SoftwareCredit {
            SoftwareCredit(
                name: "ZIPFoundation",
                kind: .library,
                version: "0.9.20",
                homepageURL: URL(string: "https://github.com/weichsel/ZIPFoundation"),
                license: LicenseNotice(name: "MIT License", text: noticeText),
            )
        }

        /// Stand-in notice text. Deliberately not a real license: a fixture that
        /// reproduced one verbatim would read as an attribution the app makes.
        public static let sampleNotice = """
        Sample License

        Copyright (c) 2026 Example Author

        Placeholder notice text for previews and tests. The shipping app renders
        the real notice carried by its generated attribution report.
        """

        // MARK: - Region picker / customization

        /// A primary-region selection model seeded with a few US picks + looks,
        /// for the picker/customization previews and tests.
        @MainActor
        public static func primaryRegionSelectionModel() -> PrimaryRegionSelectionModel {
            let texas = Region(rawValue: "us-TX")
            let existing: [PrimaryRegion] = [
                PrimaryRegion(
                    region: .california,
                    appearance: RegionAppearance(
                        color: .orange,
                        emoji: "🌴",
                        symbolName: .sunMaxFill,
                    ),
                    order: 0,
                ),
                PrimaryRegion(
                    region: .newYork,
                    appearance: RegionAppearance(
                        color: .indigo,
                        emoji: "🗽",
                        symbolName: .building2Fill,
                    ),
                    order: 1,
                ),
            ] + (texas.map {
                [PrimaryRegion(region: $0, appearance: nil, order: 2)]
            } ?? [])
            return PrimaryRegionSelectionModel(existing: existing)
        }

        // MARK: - Report models (scene / report + year views)

        /// A ready-to-render scene report model with the sample report injected
        /// and in-memory services behind it. Synchronous, so it drops straight
        /// into `#Preview`.
        @MainActor
        public static func loadedYearReportModel() -> YearReportModel {
            YearReportModel(
                services: previewServices(),
                details: sampleYearReportDetails(),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { referenceNow },
            )
        }

        /// A report stopped at the pinned "today" with a deterministic future
        /// New York stay, for forecast and planned-calendar previews.
        @MainActor
        public static func plannedStayYearReportModel(
            showsEstimatedTimeAndPlanning: Bool = true,
        ) -> YearReportModel {
            let completeReport = sampleReport()
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let today = CalendarDay(from: referenceNow, in: calendar)
            let recordedDays = completeReport.days.filter { $0.day <= today }
            var recordedTotals: [Region: Int] = [:]
            for day in recordedDays {
                for region in day.regions {
                    recordedTotals[region, default: 0] += 1
                }
            }
            let preferences = previewPreferences()
            preferences.showsEstimatedTimeAndPlanning = showsEstimatedTimeAndPlanning
            let model = YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    report: YearReport(
                        year: completeReport.year,
                        days: recordedDays,
                        totals: recordedTotals,
                    ),
                    primaryRegionLocations: sampleRegionLocations(),
                ),
                selectedYear: year,
                preferences: preferences,
                now: { referenceNow },
            )
            model.forecasts.setActivePlannedStay(PlannedStay(
                region: .newYork,
                through: CalendarDay(year: year, month: 8, day: 15),
            ))
            return model
        }

        /// The same complete year value `ReportReader.yearReportDetails` returns
        /// in production, built synchronously for previews and image tests.
        public static func sampleYearReportDetails() -> YearReportDetails {
            YearReportDetails(
                report: sampleReport(),
                primaryRegionLocations: sampleRegionLocations(),
            )
        }

        /// The loaded report fixture with the Appearance GPS-dot preference off,
        /// for the Locations snapshot that proves recorded points disappear.
        @MainActor
        public static func loadedYearReportModelWithLocationDotsHidden() -> YearReportModel {
            let model = loadedYearReportModel()
            model.showsRecordedLocationDots = false
            return model
        }

        /// The loaded report fixture with every estimated-time presentation off.
        @MainActor
        public static func loadedYearReportModelWithEstimatedTimeHidden() -> YearReportModel {
            let preferences = previewPreferences()
            preferences.showsEstimatedTimeAndPlanning = false
            return YearReportModel(
                services: previewServices(),
                details: sampleYearReportDetails(),
                selectedYear: year,
                preferences: preferences,
                now: { referenceNow },
            )
        }

        /// Deterministic point clouds for the Locations card constellations.
        /// Dates fall inside the corresponding region's block in `sampleReport`.
        private static func sampleRegionLocations() -> [Region: [RegionDayLocations]] {
            [
                .california: [RegionDayLocations(
                    day: CalendarDay(year: year, month: 2, day: 1),
                    points: [
                        regionPoint(37.7749, -122.4194),
                        regionPoint(37.8044, -122.2712),
                        regionPoint(37.3382, -121.8863),
                        regionPoint(38.5816, -121.4944),
                        regionPoint(36.7378, -119.7871),
                        regionPoint(34.0522, -118.2437),
                        regionPoint(33.7701, -118.1937),
                        regionPoint(32.7157, -117.1611),
                        regionPoint(34.4208, -119.6982),
                        regionPoint(35.3733, -119.0187),
                        regionPoint(39.0968, -120.0324),
                        regionPoint(40.5865, -122.3917),
                    ],
                )],
                .newYork: [RegionDayLocations(
                    day: CalendarDay(year: year, month: 6, day: 15),
                    points: [
                        regionPoint(40.7128, -74.0060),
                        regionPoint(40.6782, -73.9442),
                        regionPoint(40.7282, -73.7949),
                        regionPoint(40.9176, -73.7004),
                        regionPoint(41.7004, -73.9210),
                        regionPoint(42.6526, -73.7562),
                        regionPoint(43.0481, -76.1474),
                        regionPoint(43.1566, -77.6088),
                        regionPoint(42.8864, -78.8784),
                        regionPoint(43.0962, -79.0377),
                        regionPoint(44.6995, -73.4529),
                    ],
                )],
            ]
        }

        private static func regionPoint(
            _ latitude: Double,
            _ longitude: Double,
        ) -> RegionDayPoint {
            RegionDayPoint(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                horizontalAccuracy: 20,
            )
        }

        /// An empty report model (in-memory services, no data) for empty-state
        /// previews.
        @MainActor
        public static func emptyYearReportModel() -> YearReportModel {
            YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    report: YearReport(year: year, days: [], totals: [:]),
                    primaryRegionLocations: [:],
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { referenceNow },
            )
        }

        /// A report model whose only tracked days are in `.other` — there's data,
        /// but nothing ranks as "primary". Exercises the Primary tab's distinct
        /// "nothing in your headline spots" state.
        @MainActor
        public static func elsewhereOnlyYearReportModel() -> YearReportModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let days = (0 ..< 9).map { offset in
                DayPresence(
                    date: calendar.date(byAdding: .day, value: offset, to: startOfYear)!,
                    in: calendar,
                    regions: [.other],
                )
            }
            return YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    report: YearReport(year: year, days: days, totals: [.other: days.count]),
                    primaryRegionLocations: [:],
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { referenceNow },
            )
        }

        /// A report model whose current year has several unlogged stretches
        /// before a fixed "today", so missing-day detection has real gaps to
        /// render.
        @MainActor
        public static func missingDaysYearReportModel() -> YearReportModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let today = calendar.date(from: DateComponents(year: year, month: 2, day: 10))!

            // A handful of scattered logged days, leaving gaps in between.
            let loggedOffsets = [0, 1, 2, 8, 9, 20]
            let days = loggedOffsets.map { offset in
                DayPresence(
                    date: calendar.date(byAdding: .day, value: offset, to: startOfYear)!,
                    in: calendar,
                    regions: [.california],
                )
            }
            return YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    report: YearReport(
                        year: year,
                        days: days,
                        totals: [.california: days.count],
                    ),
                    primaryRegionLocations: [:],
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { today },
            )
        }

        // MARK: - Resolve model (Resolve tab)

        /// One data-resolution issue per category, for Resolve tab previews/tests.
        public static func sampleDataIssues() -> [any DataIssue] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let start = calendar.date(from: DateComponents(year: year, month: 3, day: 1))!
            let day2 = calendar.date(byAdding: .day, value: 1, to: start)!
            let day3 = calendar.date(byAdding: .day, value: 2, to: start)!
            let day4 = calendar.date(byAdding: .day, value: 3, to: start)!
            let startDay = CalendarDay(from: start, in: calendar)
            return [
                MissingDaysIssue(range: MissingDayRange(
                    start: startDay,
                    end: startDay,
                    dayCount: 1,
                )),
                BorderDriftIssue(
                    day: DayPresence(date: day2, in: calendar, regions: [.other]),
                    nearestRegion: .california,
                    distanceMeters: 6000,
                ),
                AbruptChangeIssue(
                    earlierDay: DayPresence(date: day2, in: calendar, regions: [.california]),
                    laterDay: DayPresence(date: day3, in: calendar, regions: [.newYork]),
                ),
                FlightDayIssue(
                    day: DayPresence(
                        date: day4,
                        in: calendar,
                        regions: [.newYork, .other, .california],
                    ),
                    keepRegions: [.newYork, .california],
                    removedRegions: [.other],
                    peakSpeedKMH: 880,
                ),
            ]
        }

        /// A Resolve model seeded (via the `@_spi(Testing)` seam) with one issue
        /// per category, so Resolve previews/tests render a populated list without
        /// raw samples to scan. Pass `seededWithIssues: false` for the empty state.
        ///
        /// Both cases seed, including the empty one: seeding is what marks the
        /// model loaded *and* `isSeeded`, so `ResolutionView` renders the state
        /// asked for instead of a spinner over a live `DataIssueScanner` pass.
        /// Skipping it for the empty case left `hasLoaded` false, which the view
        /// can't tell apart from "the first scan hasn't landed" — so the case
        /// rendered the loading placeholder and then whatever the real scan of the
        /// empty store found, and the capture raced that scan.
        @MainActor
        public static func resolveModel(seededWithIssues: Bool = true) -> ResolveModel {
            let resolve = ResolveModel(
                services: previewServices(),
                preferences: previewPreferences(),
            )
            resolve.setDataIssues(seededWithIssues ? sampleDataIssues() : [])
            return resolve
        }

        // MARK: - Logged days (manual entries sheet)

        /// A believable set of manual day entries across the sample year — a mix
        /// of additive backfills and an authoritative override with an audit
        /// note — for the logged-days list previews/tests.
        public static func sampleManualDays() -> [DayPresence] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            func day(_ month: Int, _ dayOfMonth: Int) -> Date {
                calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
            }
            return [
                DayPresence(
                    date: day(6, 2),
                    in: calendar,
                    regions: [.canada],
                    isAuthoritative: true,
                    audit: ManualEntryAudit(
                        recordedAt: day(6, 3),
                        note: "Corrected after reviewing my boarding pass.",
                        location: CapturedLocation(
                            coordinate: Coordinate(latitude: 49.2827, longitude: -123.1207),
                            horizontalAccuracy: 15,
                            timestamp: day(6, 2),
                        ),
                    ),
                ),
                DayPresence(
                    date: day(3, 14),
                    in: calendar,
                    regions: [.newYork],
                    audit: ManualEntryAudit(
                        recordedAt: day(3, 15),
                        note: "Backfilled a trip the GPS missed.",
                        location: nil,
                    ),
                ),
                DayPresence(date: day(1, 6), in: calendar, regions: [.california]),
            ]
        }

        /// A logged-days list model forced into a chosen state (no store read).
        @MainActor
        public static func loggedDaysModel(state: LoggedDaysModel.LoadState) -> LoggedDaysModel {
            let model = LoggedDaysModel(services: previewServices())
            model.previewLoad(state)
            return model
        }

        // MARK: - Evidence (evidence list / detail / compose)

        /// A believable set of evidence records spread across the sample year,
        /// for evidence-list previews/tests.
        public static func sampleEvidence() -> [Evidence] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            func date(_ month: Int, _ day: Int) -> Date {
                calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
            }
            return [
                Evidence(
                    kind: .planeTicket,
                    capturedAt: date(2, 3),
                    note: "SFO → JFK, seat 14C",
                    contentType: .pdf,
                ),
                Evidence(
                    kind: .email,
                    capturedAt: date(4, 18),
                    note: "Hotel reservation confirmation",
                    contentType: .plainText,
                ),
                Evidence(
                    kind: .photo,
                    capturedAt: date(7, 9),
                    note: nil,
                    contentType: .image,
                ),
                Evidence(
                    kind: .other("Ferry ticket"),
                    capturedAt: date(9, 22),
                    note: "Vancouver ↔ Victoria",
                    contentType: .rawData,
                ),
            ]
        }

        /// An evidence-list model forced into a chosen state (no store read).
        @MainActor
        public static func evidenceListModel(
            state: EvidenceListModel.LoadState,
        ) -> EvidenceListModel {
            let model = EvidenceListModel(services: previewServices())
            model.previewLoad(state)
            return model
        }

        /// An evidence-detail model for a synthetic record, forced to a loaded
        /// blob state so the preview renders without a store read.
        @MainActor
        public static func evidenceDetailModel(
            kind: EvidenceKind,
            contentType: EvidenceContentType,
            blob: Data?,
        ) -> EvidenceDetailModel {
            let evidence = Evidence(
                kind: kind,
                capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
                note: "Captured while traveling.",
                contentType: contentType,
            )
            let model = EvidenceDetailModel(evidence: evidence, services: previewServices())
            model.previewLoad(.loaded(blob))
            return model
        }

        /// A blank compose model over in-memory services.
        @MainActor
        public static func addEvidenceModel() -> AddEvidenceModel {
            AddEvidenceModel(services: previewServices(), now: { referenceNow })
        }

        // MARK: - Models (app-level shell)

        /// A ready-to-render app model with the sample report injected and
        /// in-memory services behind it (so its `session` is built up front and
        /// `MainTabs` seeds its `YearReportModel` with the sample report).
        /// Pre-onboarded over in-memory preferences, so `RootView` renders the
        /// logged-in UI and the host's real `UserDefaults` can't leak in.
        /// Synchronous, so it drops straight into `#Preview`.
        @MainActor
        public static func loadedModel(theme: WhereTheme = .alternate) -> WhereModel {
            let preferences = previewPreferences()
            preferences.hasOnboarded = true
            preferences.theme = theme
            return WhereModel(
                services: previewServices(),
                details: sampleYearReportDetails(),
                selectedYear: year,
                preferences: preferences,
                logSystem: logSystem,
                now: { referenceNow },
            )
        }

        /// Logged-in shell fixture whose current phone is the expected recorder but has both
        /// automatic recording and Always location access disabled. Launch reconciliation drives
        /// the real session and warning model before snapshot capture.
        @MainActor
        static func recordingConfigurationWarningAppModel() -> WhereModel {
            let preferences = previewPreferences()
            preferences.hasOnboarded = true
            let context = InstallationRecordingContext(
                currentDevice: InstallationRecordingContext.testing.currentDevice,
                registeredAt: InstallationRecordingContext.testing.registeredAt,
                recordingChoice: .off,
                isRejoining: false,
            )
            let services = WhereServices(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(authorizationStatus: .whenInUse),
                installationContext: context,
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                issueAlertScheduler: NoopDataIssueAlertScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
                now: { referenceNow },
            )
            return WhereModel(
                services: services,
                details: sampleYearReportDetails(),
                selectedYear: year,
                preferences: preferences,
                logSystem: logSystem,
                now: { referenceNow },
            )
        }

        /// Fixed day for widget previews and snapshots — a single pinned instant
        /// so the day/year chrome renders identically whenever a capture runs
        /// (an unpinned `.now` default churned references daily). Widget captures
        /// pin the timezone (Pacific), so this reads as a stable calendar day.
        public static let referenceWidgetDay = Date(timeIntervalSince1970: 1_770_000_000)

        /// A fresh, not-yet-onboarded model over **in-memory** preferences — for
        /// the onboarding preview/snapshot, honoring PreviewSupport's no-disk
        /// contract so the host's real defaults can't leak in.
        @MainActor
        public static func onboardingModel(theme: WhereTheme = .alternate) -> WhereModel {
            let preferences = previewPreferences()
            preferences.theme = theme
            return WhereModel(
                services: previewServices(),
                preferences: preferences,
                logSystem: logSystem,
                now: { referenceNow },
            )
        }

        /// An in-memory Periscope log store for the developer-surface previews and
        /// hosting tests — the same durable-sink type the app opens at launch,
        /// but backed by memory so nothing touches disk.
        @MainActor
        public static func previewLogStore() async throws -> PeriscopeStore {
            try await PeriscopeStore.make(
                storage: .inMemory,
                session: .current(attributes: BuildInfo.current(bundle: .main)
                    .logSessionAttributes),
            )
        }

        /// A `loadedModel()` with an in-memory log store attached, so the
        /// developer tools' log-viewer and Log View Mode rows render.
        @MainActor
        public static func loadedModel(withLogStore store: PeriscopeStore) -> WhereModel {
            let model = loadedModel()
            model.attach(logStore: store)
            return model
        }

        /// A widget snapshot built from the sample year totals, for widget
        /// previews and tests.
        public static func sampleWidgetSnapshot(
            dayRegions: Set<Region> = [.california],
            totals: [Region: Int]? = nil,
            day: Date = PreviewSupport.referenceWidgetDay,
            year: Int = PreviewSupport.year,
        ) -> WidgetSnapshot {
            WidgetSnapshot(
                day: day,
                year: year,
                dayRegions: dayRegions,
                totals: totals ?? [
                    .california: 132,
                    .newYork: 41,
                    .canada: 9,
                    .europeanUnion: 4,
                    .other: 2,
                ],
            )
        }

        /// Personalized feature-gallery content over the same pinned report and
        /// clock used by the rest of the WhereUI snapshot catalog.
        @MainActor
        static func featureDiscoveryPresentation() -> FeatureDiscoveryPresentation {
            let model = loadedYearReportModel()
            return FeatureDiscoveryPresentation(
                report: model.report,
                selectedYear: model.selectedYear,
                referenceDate: model.referenceDate,
                calendar: model.calendar,
            )
        }
    }
#endif
