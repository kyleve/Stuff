import Foundation
import RegionKit

/// A current, copied input for replay. It makes no claim about an earlier detector execution.
public struct DataIssueInvestigation: Sendable {
    public let capturedAt: Date
    public let input: DataIssueInput
    public let dismissedIssueIDs: Set<DataIssueID>

    /// Runs the production detector against captured values, without the live scanner's cache or
    /// writes.
    public func replay(category: DataIssueCategory) -> [any DataIssue] {
        switch category {
            case .missingDays: MissingDaysDetector().detectAnyIssues(in: input)
            case .borderDrift: BorderDriftDetector().detectAnyIssues(in: input)
            case .abruptChange: AbruptLocationChangeDetector().detectAnyIssues(in: input)
            case .flightDay: FlightDayDetector().detectAnyIssues(in: input)
        }
    }
}

extension ReportReader {
    /// Captures related persistence reads under one snapshot and freezes the current attribution
    /// policy.
    public func investigation(
        year: Int,
        primaryRegions: [Region],
        driftThresholdMeters: Double,
        now: Date,
    ) async throws -> DataIssueInvestigation {
        let frozen: RegionAttributor
        if let live = attributor as? RegionAttribution {
            frozen = live.snapshot
        } else if let immutable = attributor as? RegionAttributor {
            frozen = immutable
        } else {
            throw InvestigationError.unsupportedAttributor
        }
        return try await store.readSnapshot {
            let samples = try await LocationHistoryReader(store: store)
                .samples(in: aggregator.yearInterval(year: year))
            let manuals = try await store.manualDays(in: dayRange(for: year))
            let dismissed = try await store.dismissedIssueIDs()
            let report = aggregator.report(
                for: year,
                samples: samples,
                manualDays: manuals,
                attributor: frozen,
            )
            let other = aggregator.locations(in: .other, samples: samples, attributor: frozen)
            return DataIssueInvestigation(capturedAt: now, input: DataIssueInput(
                year: year,
                report: report,
                otherDayCoordinates: Dictionary(uniqueKeysWithValues: other.map { (
                    $0.day,
                    $0.points.map(\.coordinate),
                ) }),
                daySamples: DaySamples(samples: samples, calendar: aggregator.calendar),
                primaryRegions: primaryRegions,
                attributor: frozen,
                driftThresholdMeters: driftThresholdMeters,
                calendar: aggregator.calendar,
                now: now,
            ), dismissedIssueIDs: dismissed)
        }
    }
}

private enum InvestigationError: Error, LocalizedError {
    case unsupportedAttributor
    var errorDescription: String? {
        "This attribution implementation cannot produce an immutable investigation snapshot."
    }
}
