import Foundation

/// Every discovered year's scan inputs, admitted together before any scanner publishes them.
struct HistoricalDataIssueReads {
    struct Year {
        let context: RecordingReviewReference.Context
        let reads: DataIssueReads
    }

    let generationID: WhereDataGenerationID
    let years: [Year]
}

extension ReportReader {
    func historicalDataIssueReads(currentYear: Int) async throws -> HistoricalDataIssueReads {
        _ = try Self.dataIssueContextDays(for: currentYear)
        return try await Self.logger.measure(.historicalDataIssueReads, budget: .seconds(5)) {
            try await store.readSnapshot {
                let generation = try await store.dataGeneration()
                let years = try await Set(historyYears()).union([currentYear]).sorted()
                var results: [HistoricalDataIssueReads.Year] = []
                for year in years {
                    try Task.checkCancellation()
                    let reads = try await dataIssueReads(for: year)
                    guard reads.dataGenerationID == generation.id else {
                        throw DataCompatibilityError.concurrentChange
                    }
                    try results.append(.init(
                        context: .init(
                            historicalYear: year,
                            query: .days(Self.dataIssueContextDays(for: year)),
                        ),
                        reads: reads,
                    ))
                }
                return HistoricalDataIssueReads(generationID: generation.id, years: results)
            }
        }
    }
}
