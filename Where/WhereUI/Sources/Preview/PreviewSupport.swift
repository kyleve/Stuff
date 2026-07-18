#if DEBUG
    import Foundation
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

        /// In-memory, no-op-backed services shared by every preview fixture.
        /// Every scheduler seam is a no-op — the issue-alert one included, so the
        /// launch sequence's `issue-alerts` step can't suspend on a real
        /// `UNUserNotificationCenter` permission prompt in previews/tests.
        @MainActor
        public static func previewServices() -> WhereServices {
            WhereServices(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                issueAlertScheduler: NoopDataIssueAlertScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
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
            WhereSession(services: previewServices())
        }

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
                        symbolName: "sun.max.fill",
                    ),
                    order: 0,
                ),
                PrimaryRegion(
                    region: .newYork,
                    appearance: RegionAppearance(
                        color: .indigo,
                        emoji: "🗽",
                        symbolName: "building.2.fill",
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
                report: sampleReport(),
                selectedYear: year,
                now: { referenceNow },
            )
        }

        /// An empty report model (in-memory services, no data) for empty-state
        /// previews.
        @MainActor
        public static func emptyYearReportModel() -> YearReportModel {
            YearReportModel(
                services: previewServices(),
                report: YearReport(year: year, days: [], totals: [:]),
                selectedYear: year,
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
                report: YearReport(year: year, days: days, totals: [.other: days.count]),
                selectedYear: year,
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
                report: YearReport(year: year, days: days, totals: [.california: days.count]),
                selectedYear: year,
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
        @MainActor
        public static func resolveModel(seededWithIssues: Bool = true) -> ResolveModel {
            let resolve = ResolveModel(services: previewServices(), preferences: WherePreferences())
            if seededWithIssues { resolve.setDataIssues(sampleDataIssues()) }
            return resolve
        }

        // MARK: - Recent activity (24h summary sheet)

        /// A recent-activity model forced into a chosen state (no generator run),
        /// so the summary sheet's states drop straight into a `#Preview`.
        @MainActor
        public static func recentActivityModel(
            state: RecentActivityModel.LoadState,
        ) -> RecentActivityModel {
            let model = RecentActivityModel(services: previewServices())
            model.previewLoad(state)
            return model
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
                DayPresence(date: day(1, 6), in: calendar, regions: [.california]),
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
            AddEvidenceModel(services: previewServices())
        }

        // MARK: - Models (app-level shell)

        /// A ready-to-render app model with the sample report injected and
        /// in-memory services behind it (so its `session` is built up front and
        /// `MainTabs` seeds its `YearReportModel` with the sample report).
        /// Pre-onboarded over in-memory preferences, so `RootView` renders the
        /// logged-in UI and the host's real `UserDefaults` can't leak in.
        /// Synchronous, so it drops straight into `#Preview`.
        @MainActor
        public static func loadedModel() -> WhereModel {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            preferences.hasOnboarded = true
            return WhereModel(
                services: previewServices(),
                report: sampleReport(),
                selectedYear: year,
                preferences: preferences,
                now: { referenceNow },
            )
        }

        /// A widget snapshot built from the sample year totals, for widget
        /// previews and tests.
        public static func sampleWidgetSnapshot(
            dayRegions: Set<Region> = [.california],
            totals: [Region: Int]? = nil,
            day: Date = .now,
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
    }
#endif
