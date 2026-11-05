extension ReportReader {
    /// Actual stored history years, independent of a selected year. Callers add the current year
    /// when they also need today's missing-history work in an otherwise empty dataset.
    public func historyYears() async throws -> [Int] {
        try await Self.logger.measure(.historyYears, budget: .seconds(2)) {
            try await store.readSnapshot {
                var inventory = HistoryYearInventory()
                for manual in try await store.allManualDays() {
                    try Task.checkCancellation()
                    try inventory.include(day: manual.day)
                }
                for evidence in try await store.allEvidence() {
                    try Task.checkCancellation()
                    try inventory.include(
                        timestamp: evidence.capturedAt,
                        calendar: aggregator.calendar,
                    )
                }
                return try await inventory.years
                    .union(history.historyYears(calendar: aggregator.calendar)).sorted()
            }
        }
    }
}
