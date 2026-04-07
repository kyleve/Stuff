import Foundation
import WhereCore

public actor YearProgressController: YearProgressProviding {
    private let calendar: Calendar
    private let ledgerBuilder: YearLedgerBuilder
    private let sampleData: [LocationSample]
    private let manualEntries: [ManualLogEntry]
    private let dayFormatter: DateFormatter

    public init(
        calendar: Calendar = .current,
        sampleData: [LocationSample]? = nil,
        manualEntries: [ManualLogEntry]? = nil,
    ) {
        self.calendar = calendar
        ledgerBuilder = YearLedgerBuilder(calendar: calendar)
        self.sampleData = sampleData ?? SampleDataFactory.make(calendar: calendar)
        self.manualEntries = manualEntries ?? SampleDataFactory.makeManualEntries(calendar: calendar)
        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "MMM d"
    }

    public func availableYears() async -> [Int] {
        let years = Set(sampleData.map { calendar.component(.year, from: $0.timestamp) })
        return years.sorted()
    }

    public func snapshot(for year: Int) async -> YearProgressSnapshot {
        let ledgers = ledgerBuilder.makeLedgers(
            year: year,
            samples: sampleData,
            manualEntries: manualEntries,
        )
        let yearSummary = ledgerBuilder.makeYearSummary(year: year, ledgers: ledgers)

        let primary = [TaxJurisdiction.california, .newYork].map { jurisdiction in
            YearProgressSnapshot.JurisdictionSummary(
                jurisdiction: jurisdiction,
                totalDays: yearSummary.totalsByJurisdiction[jurisdiction, default: 0],
            )
        }

        let secondary = [TaxJurisdiction.unknown].map { jurisdiction in
            YearProgressSnapshot.JurisdictionSummary(
                jurisdiction: jurisdiction,
                totalDays: jurisdiction == .unknown ? yearSummary.unknownDayCount : 0,
            )
        }

        let recentDays = ledgers
            .suffix(5)
            .reversed()
            .map { ledger in
                YearProgressSnapshot.RecentDay(
                    dateLabel: dayFormatter.string(from: ledger.date),
                    jurisdictions: ledger.finalJurisdictions,
                    note: ledger.note,
                )
            }

        return YearProgressSnapshot(
            year: year,
            primarySummaries: primary,
            secondarySummaries: secondary,
            trackingStatus: trackingStatus(for: ledgers),
            recentDays: recentDays,
        )
    }

    private func trackingStatus(for ledgers: [DailyStateLedger]) -> TrackingStatus {
        guard !ledgers.isEmpty else {
            return .needsAttention
        }

        if ledgers.contains(where: \.needsReview) {
            return .needsReview
        }

        return .healthy
    }
}

private enum SampleDataFactory {
    static func make(calendar: Calendar) -> [LocationSample] {
        let year = calendar.component(.year, from: Date())

        return [
            makeSample(year: year, month: 1, day: 4, hour: 9, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 1, day: 4, hour: 20, jurisdiction: .newYork, calendar: calendar),
            makeSample(year: year, month: 2, day: 10, hour: 8, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 2, day: 11, hour: 8, jurisdiction: .california, calendar: calendar),
            makeSample(year: year, month: 2, day: 12, hour: 8, jurisdiction: .unknown, calendar: calendar),
            makeSample(year: year, month: 2, day: 13, hour: 8, jurisdiction: .newYork, calendar: calendar),
        ]
    }

    static func makeManualEntries(calendar: Calendar) -> [ManualLogEntry] {
        let year = calendar.component(.year, from: Date())

        return [
            ManualLogEntry(
                timestamp: makeDate(year: year, month: 2, day: 12, hour: 12, calendar: calendar),
                jurisdiction: .newYork,
                note: "Attached ticket for overnight travel",
                kind: .correction,
            ),
            ManualLogEntry(
                timestamp: makeDate(year: year, month: 1, day: 4, hour: 21, calendar: calendar),
                jurisdiction: .california,
                note: "Added airport evidence",
                kind: .supplemental,
            ),
        ]
    }

    private static func makeSample(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        jurisdiction: TaxJurisdiction,
        calendar: Calendar,
    ) -> LocationSample {
        let components = DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
        )

        return LocationSample(
            timestamp: components.date ?? Date(),
            jurisdiction: jurisdiction,
        )
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar,
    ) -> Date {
        DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
        )
        .date ?? Date()
    }
}
