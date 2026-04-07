import Foundation

public struct TaxDayCalculator: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func makeDailyRecords(from samples: [LocationSample]) -> [DailyJurisdictionRecord] {
        let grouped = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.timestamp)
        }

        return grouped
            .map { date, entries in
                let jurisdictions = orderedJurisdictions(
                    from: entries.map(\.jurisdiction),
                )

                return DailyJurisdictionRecord(date: date, jurisdictions: jurisdictions)
            }
            .sorted { $0.date < $1.date }
    }

    public func countDaysByJurisdiction(
        from records: [DailyJurisdictionRecord],
    ) -> [TaxJurisdiction: Int] {
        var totals: [TaxJurisdiction: Int] = [:]

        for record in records {
            for jurisdiction in record.jurisdictions where jurisdiction.countsTowardTaxDay {
                totals[jurisdiction, default: 0] += 1
            }
        }

        return totals
    }

    private func orderedJurisdictions(from jurisdictions: [TaxJurisdiction]) -> [TaxJurisdiction] {
        var seen = Set<TaxJurisdiction>()
        var ordered: [TaxJurisdiction] = []

        for jurisdiction in jurisdictions where seen.insert(jurisdiction).inserted {
            ordered.append(jurisdiction)
        }

        return ordered.sorted { $0.displayName < $1.displayName }
    }
}
