#if DEBUG
    import Foundation
    import WhereCore

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
                    days.append(DayPresence(date: date, regions: [entry.region]))
                    dayOffset += 1
                }
            }
            return YearReport(year: year, days: days, totals: totals)
        }

        /// In-memory, no-op-backed services shared by every preview fixture.
        @MainActor
        static func previewServices() -> WhereServices {
            WhereServices(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
                reminderScheduler: NoopLoggingReminderScheduler(),
                summaryScheduler: NoopDailySummaryScheduler(),
                widgetRefresher: NoopWidgetTimelineRefresher(),
            )
        }

        // MARK: - Sessions (logged-in views)

        /// A ready-to-render session with the sample report injected and
        /// in-memory services behind it. Synchronous, so it drops straight into
        /// `#Preview`.
        @MainActor
        public static func loadedSession() -> WhereSession {
            WhereSession(services: previewServices(), report: sampleReport(), selectedYear: year)
        }

        /// An empty session (in-memory services, no data) for empty-state
        /// previews.
        @MainActor
        public static func emptySession() -> WhereSession {
            WhereSession(
                services: previewServices(),
                report: YearReport(year: year, days: [], totals: [:]),
                selectedYear: year,
            )
        }

        /// A session whose only tracked days are in `.other` — there's data, but
        /// nothing ranks as "primary". Exercises the Primary tab's distinct
        /// "nothing in your headline spots" state.
        @MainActor
        public static func elsewhereOnlySession() -> WhereSession {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let days = (0 ..< 9).map { offset in
                DayPresence(
                    date: calendar.date(byAdding: .day, value: offset, to: startOfYear)!,
                    regions: [.other],
                )
            }
            return WhereSession(
                services: previewServices(),
                report: YearReport(year: year, days: days, totals: [.other: days.count]),
                selectedYear: year,
            )
        }

        /// A session whose current year has several unlogged stretches before a
        /// fixed "today", so the missing-day banner and `MissingDaysView` have
        /// real gaps to render.
        @MainActor
        public static func missingDaysSession() -> WhereSession {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let today = calendar.date(from: DateComponents(year: year, month: 2, day: 10))!

            // A handful of scattered logged days, leaving gaps in between.
            let loggedOffsets = [0, 1, 2, 8, 9, 20]
            let days = loggedOffsets.map { offset in
                DayPresence(
                    date: calendar.date(byAdding: .day, value: offset, to: startOfYear)!,
                    regions: [.california],
                )
            }
            return WhereSession(
                services: previewServices(),
                report: YearReport(year: year, days: days, totals: [.california: days.count]),
                selectedYear: year,
                now: { today },
            )
        }

        // MARK: - Models (app-level shell)

        /// A ready-to-render app model with the sample report injected and
        /// in-memory services behind it (so its `session` is built up front).
        /// Synchronous, so it drops straight into `#Preview`.
        @MainActor
        public static func loadedModel() -> WhereModel {
            WhereModel(services: previewServices(), report: sampleReport(), selectedYear: year)
        }
    }
#endif
