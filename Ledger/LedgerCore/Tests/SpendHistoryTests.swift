import Foundation
@_spi(Testing) import LedgerCore
import Testing

struct SpendHistoryTests {
    private let cycleStart = date(2026, 7, 4, 18, 16)
    private let now = date(2026, 7, 15, 12, 0)

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func sample(_ timestamp: Date, _ cents: Int, cycle: Date? = nil) -> SpendSample {
        SpendSample(timestamp: timestamp, cycleStart: cycle ?? cycleStart, onDemandCents: cents)
    }

    @Test func differencesTodayAndThisWeekFromBaselines() throws {
        let calendar = Self.calendar()
        let dayStart = calendar.startOfDay(for: now)
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: now)?.start)

        let current = sample(now, 145_000)
        let samples = [
            sample(weekStart, 100_000),
            sample(dayStart, 130_000),
            current,
        ]
        let deltas = SpendHistory.deltas(
            current: current,
            samples: samples,
            calendar: calendar,
            now: now,
        )

        #expect(deltas.todayCents == 15000) // 145000 - 130000
        #expect(deltas.thisWeekCents == 45000) // 145000 - 100000
    }

    @Test func returnsNilWithoutEnoughHistory() {
        let calendar = Self.calendar()
        let current = sample(now, 145_000)
        // Only the current sample — no baseline near the window starts.
        let deltas = SpendHistory.deltas(
            current: current,
            samples: [current],
            calendar: calendar,
            now: now,
        )
        #expect(deltas.todayCents == nil)
        #expect(deltas.thisWeekCents == nil)
    }

    @Test func countsWholeCycleWhenItBeganInsideTheWindow() {
        let calendar = Self.calendar()
        // Cycle started today, so today's (and the week's) baseline is 0.
        let current = sample(
            now,
            4200,
            cycle: calendar.startOfDay(for: now).addingTimeInterval(3600),
        )
        let deltas = SpendHistory.deltas(
            current: current,
            samples: [current],
            calendar: calendar,
            now: now,
        )
        #expect(deltas.todayCents == 4200)
        #expect(deltas.thisWeekCents == 4200)
    }

    @Test func ignoresSamplesFromOtherCycles() throws {
        let calendar = Self.calendar()
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let current = sample(now, 145_000)
        // A sample at week start, but from the previous cycle — must not be a
        // baseline for the current cycle.
        let previousCycle = sample(weekStart, 100_000, cycle: Self.date(2026, 6, 4))
        let deltas = SpendHistory.deltas(
            current: current,
            samples: [previousCycle, current],
            calendar: calendar,
            now: now,
        )
        #expect(deltas.thisWeekCents == nil)
    }

    @Test func clampsNegativeDeltasToZero() {
        let calendar = Self.calendar()
        let dayStart = calendar.startOfDay(for: now)
        let current = sample(now, 120_000)
        // Baseline higher than current (e.g. an adjustment) → not negative.
        let deltas = SpendHistory.deltas(
            current: current,
            samples: [sample(dayStart, 130_000), current],
            calendar: calendar,
            now: now,
        )
        #expect(deltas.todayCents == 0)
    }
}
