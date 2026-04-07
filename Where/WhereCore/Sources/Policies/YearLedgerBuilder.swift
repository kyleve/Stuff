import Foundation

public struct YearLedgerBuilder: Sendable {
    private let calendar: Calendar
    private let taxDayCalculator: TaxDayCalculator

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
        taxDayCalculator = TaxDayCalculator(calendar: calendar)
    }

    public func makeLedgers(
        year: Int,
        samples: [LocationSample],
        manualEntries: [ManualLogEntry],
    ) -> [DailyStateLedger] {
        let yearSamples = samples.filter { calendar.component(.year, from: $0.timestamp) == year }
        let yearEntries = manualEntries.filter { calendar.component(.year, from: $0.timestamp) == year }

        let trackedRecords = taxDayCalculator.makeDailyRecords(from: yearSamples)
        let recordsByDay = Dictionary(uniqueKeysWithValues: trackedRecords.map { ($0.date, $0) })
        let entriesByDay = Dictionary(grouping: yearEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        let allDays = Set(recordsByDay.keys).union(entriesByDay.keys).sorted()

        return allDays.map { day in
            let trackedJurisdictions = recordsByDay[day]?.jurisdictions ?? []
            let manualForDay = (entriesByDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
            let finalJurisdictions = finalJurisdictions(
                trackedJurisdictions: trackedJurisdictions,
                manualEntries: manualForDay,
            )

            return DailyStateLedger(
                date: day,
                trackedJurisdictions: trackedJurisdictions,
                manualEntries: manualForDay,
                finalJurisdictions: finalJurisdictions,
                note: note(for: trackedJurisdictions, manualEntries: manualForDay, finalJurisdictions: finalJurisdictions),
            )
        }
    }

    public func makeYearSummary(year: Int, ledgers: [DailyStateLedger]) -> YearSummary {
        var totals: [TaxJurisdiction: Int] = [:]
        var unknownDays = 0

        for ledger in ledgers {
            if ledger.finalJurisdictions.contains(.unknown) {
                unknownDays += 1
            }

            for jurisdiction in ledger.finalJurisdictions where jurisdiction.countsTowardTaxDay {
                totals[jurisdiction, default: 0] += 1
            }
        }

        return YearSummary(
            year: year,
            totalsByJurisdiction: totals,
            unknownDayCount: unknownDays,
            totalTrackedDays: ledgers.count,
        )
    }

    public func finalJurisdictions(
        trackedJurisdictions: [TaxJurisdiction],
        manualEntries: [ManualLogEntry],
    ) -> [TaxJurisdiction] {
        let correctionJurisdictions = manualEntries
            .filter { $0.kind == .correction }
            .map(\.jurisdiction)

        if !correctionJurisdictions.isEmpty {
            return orderedUnique(correctionJurisdictions)
        }

        let supplementalJurisdictions = manualEntries
            .filter { $0.kind == .supplemental }
            .map(\.jurisdiction)

        return orderedUnique(trackedJurisdictions + supplementalJurisdictions)
    }

    private func orderedUnique(_ jurisdictions: [TaxJurisdiction]) -> [TaxJurisdiction] {
        var seen = Set<TaxJurisdiction>()
        var ordered: [TaxJurisdiction] = []

        for jurisdiction in jurisdictions where seen.insert(jurisdiction).inserted {
            ordered.append(jurisdiction)
        }

        return ordered.sorted { $0.displayName < $1.displayName }
    }

    private func note(
        for trackedJurisdictions: [TaxJurisdiction],
        manualEntries: [ManualLogEntry],
        finalJurisdictions: [TaxJurisdiction],
    ) -> String? {
        if finalJurisdictions.contains(.unknown) {
            return "Review location coverage"
        }

        if manualEntries.contains(where: { $0.kind == .correction }) {
            return "Manual correction applied"
        }

        if finalJurisdictions.count > 1 || trackedJurisdictions.count > 1 {
            return "Multiple jurisdictions logged"
        }

        return nil
    }
}
