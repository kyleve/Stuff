import Foundation
import WhereCore

public actor YearProgressController: YearProgressProviding {
    private let calendar: Calendar
    private let ledgerBuilder: YearLedgerBuilder
    private let yearDataProvider: any YearDataProviding
    private let dayFormatter: DateFormatter

    public init(
        calendar: Calendar = .current,
        yearDataProvider: (any YearDataProviding)? = nil,
    ) {
        self.calendar = calendar
        ledgerBuilder = YearLedgerBuilder(calendar: calendar)
        self.yearDataProvider = yearDataProvider ?? SampleYearDataProvider(calendar: calendar)
        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "MMM d"
    }

    public func availableYears() async -> [Int] {
        await yearDataProvider.availableYears()
    }

    public func snapshot(for year: Int) async -> YearProgressSnapshot {
        let bundle = await yearDataProvider.bundle(for: year)
        let ledgers = ledgerBuilder.makeLedgers(
            year: year,
            samples: bundle.locationSamples,
            manualEntries: bundle.manualEntries,
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
            trackingStatus: trackingStatus(
                for: ledgers,
                syncCheckpoint: bundle.syncCheckpoint,
                trackingState: bundle.trackingState,
            ),
            recentDays: recentDays,
        )
    }

    private func trackingStatus(
        for ledgers: [DailyStateLedger],
        syncCheckpoint: SyncCheckpoint,
        trackingState: TrackingState?,
    ) -> TrackingStatus {
        if let trackingState {
            let runtimeStatus = trackingState.runtimeStatus(at: Date())
            if runtimeStatus == .needsAttention {
                return .needsAttention
            }
        }

        guard !ledgers.isEmpty else {
            return .needsAttention
        }

        if syncCheckpoint.state == .failed {
            return .needsAttention
        }

        if let trackingState, trackingState.runtimeStatus(at: Date()) == .needsReview {
            return .needsReview
        }

        if ledgers.contains(where: \.needsReview) {
            return .needsReview
        }

        return .healthy
    }
}
