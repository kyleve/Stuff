#if DEBUG
    import Foundation
    import WhereCore

    /// Preview/test fixtures for `WhereUI`. Provides both a synchronous sample
    /// `YearReport` (for static display previews) and an in-memory
    /// `WhereController` seeded via `addManualDay` (for interactive previews
    /// that exercise the live read path) — neither touches disk, CloudKit, or
    /// CoreLocation.
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

        /// A believable `YearReport` built directly (no controller needed), so
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

        /// A ready-to-render model with the sample report injected and an
        /// in-memory controller behind it. Synchronous, so it drops straight
        /// into `#Preview`.
        @MainActor
        public static func loadedModel() -> WhereModel {
            let controller = WhereController(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
            )
            return WhereModel(
                controller: controller,
                report: sampleReport(),
                selectedYear: year,
            )
        }

        /// An empty model (in-memory controller, no data) for empty-state
        /// previews.
        @MainActor
        public static func emptyModel() -> WhereModel {
            let controller = WhereController(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
            )
            return WhereModel(
                controller: controller,
                report: YearReport(year: year, days: [], totals: [:]),
                selectedYear: year,
            )
        }

        /// A model whose only tracked days are in `.other` — there's data, but
        /// nothing ranks as "primary". Exercises the Primary tab's distinct
        /// "nothing in your headline spots" state.
        @MainActor
        public static func elsewhereOnlyModel() -> WhereModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            let days = (0 ..< 9).map { offset in
                DayPresence(
                    date: calendar.date(byAdding: .day, value: offset, to: startOfYear)!,
                    regions: [.other],
                )
            }
            let controller = WhereController(
                store: try! SwiftDataStore.inMemory(),
                locationSource: ScriptedLocationSource(),
            )
            return WhereModel(
                controller: controller,
                report: YearReport(year: year, days: days, totals: [.other: days.count]),
                selectedYear: year,
            )
        }
    }
#endif
