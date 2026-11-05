import Foundation
import RegionKit

extension DataIssueScanner {
    struct CachedHistoricalScan {
        let trackedRegions: [Region]
        let driftThresholdMeters: Double
        let day: Date
        let at: Date
        let result: HistoricalDataIssueScanResult
    }

    #if DEBUG
        @_spi(Testing) public func setBeforeHistoricalPublicationForTesting(
            _ operation: @escaping @Sendable () async -> Void,
        ) {
            beforeHistoricalPublication = operation
        }
    #endif

    /// Main issue discovery and reminders share this all-history scope, independent of a
    /// scene's selected year. One failed year fails the whole refresh, preserving pending work.
    public func historicalScan(
        driftThresholdMeters: Double,
        force: Bool,
    ) async throws -> HistoricalDataIssueScanResult {
        while true {
            try Task.checkCancellation()
            let currentDate = now()
            let currentDay = calendar.startOfDay(for: currentDate)
            let trackedRegions = attributor.loadedRegions
            if !force, let cached = historicalCache,
               cached.trackedRegions == trackedRegions,
               cached.driftThresholdMeters == driftThresholdMeters,
               cached.day == currentDay,
               currentDate.timeIntervalSince(cached.at) < scanInterval,
               cached.result.nextReassessmentAt.map({ currentDate < $0 }) ?? true
            {
                return cached.result
            }
            let revision = invalidationRevision
            let result = try await Self.logger.measure(.historicalScan, budget: .seconds(8)) {
                let reads = try await reportReader.historicalDataIssueReads(
                    currentYear: calendar.component(.year, from: currentDate),
                )
                return try HistoricalDataIssueScanResult(
                    reads: reads,
                    scopeID: recordingReviewScopeID,
                    assessment: DataIssueAssessment(calendar: calendar, detectors: detectors),
                    driftThresholdMeters: driftThresholdMeters,
                    now: currentDate,
                )
            }
            #if DEBUG
                await beforeHistoricalPublication?()
            #endif
            try Task.checkCancellation()
            guard revision == invalidationRevision,
                  trackedRegions == attributor.loadedRegions else { continue }
            historicalCache = CachedHistoricalScan(
                trackedRegions: trackedRegions,
                driftThresholdMeters: driftThresholdMeters,
                day: currentDay,
                at: currentDate,
                result: result,
            )
            return result
        }
    }
}
