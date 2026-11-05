import Foundation
import RegionKit

/// One consistent read of visible observations and their attribution revisions.
/// Revisions include tombstones so review equality detects changes whose
/// resulting presence happens to be unchanged.
public struct LocationHistoryProjection: Hashable, Sendable {
    public enum Contract: Hashable, Sendable {
        case foundation
        case recording(RecordingHistorySelection)
    }

    public let samples: [AttributedLocationSample]
    public let revisions: [SampleAttributionRevision]
    public let contract: Contract

    public var rawSamples: [LocationSample] {
        samples.map(\.sample)
    }

    public init(samples: [AttributedLocationSample], revisions: [SampleAttributionRevision]) {
        self.init(samples: samples, revisions: revisions, contract: .foundation)
    }

    public init(
        samples: [AttributedLocationSample],
        revisions: [SampleAttributionRevision],
        contract: Contract,
    ) {
        self.samples = samples
        self.revisions = revisions
        self.contract = contract
    }

    /// Group specific GPS geography only after source selection. Foundation and user-asserted
    /// samples retain their existing attribution contract.
    public func reportingSamples(primaryRegions: Set<Region>) -> [AttributedLocationSample] {
        switch contract {
            case .foundation: samples
            case .recording:
                samples.map { $0.reporting(primaryRegions: primaryRegions) }
        }
    }

    public func completeness(in days: ClosedRange<CalendarDay>) throws -> HistoryCompleteness {
        switch contract {
            case .foundation: .foundation
            case let .recording(selection): try HistoryCompleteness(
                    selection: selection,
                    days: days,
                )
        }
    }

    func clipped(to period: RecordingPeriod) throws -> Self {
        // Review context is physical. Preserve selected adjacent GPS even when a date-line
        // jump put its logical label outside the report's display-date query.
        let contextSamples: [AttributedLocationSample] = switch contract {
            case .foundation: samples
            case let .recording(selection): try selection.attributedSamples()
            + samples.filter { !$0.sample.source.isGPS }
        }
        let retained = contextSamples.filter { period.contains($0.sample.timestamp) }
            .sorted {
                if $0.sample.timestamp != $1.sample
                    .timestamp { return $0.sample.timestamp < $1.sample.timestamp }
                return $0.sample.id.uuidString < $1.sample.id.uuidString
            }
        var sampleIDs = Set(retained.map(\.sample.id))
        let clippedContract: Contract = switch contract {
            case .foundation: .foundation
            case let .recording(selection): try .recording(selection.clipped(to: period))
        }
        if case let .recording(selection) = clippedContract {
            sampleIDs.formUnion(selection.evidence.observations.map(\.sample.id))
        }
        return Self(
            samples: retained,
            revisions: revisions.filter { sampleIDs.contains($0.sampleID) },
            contract: clippedContract,
        )
    }

    /// Preview the same regional inputs and source selection that a saved correction will use.
    /// Keep rival tracks, manual assertions, and selected calendar labels in that calculation.
    func previewRegions(
        on day: CalendarDay,
        applying replacements: [LocationSample.ID: Set<Region>],
        primaryRegions: Set<Region>,
        manualDays: [DayPresence],
        calendar: Calendar,
    ) throws -> Set<Region> {
        let corrected: [AttributedLocationSample] = switch contract {
            case .foundation:
                samples.map { $0.replacingRegions(replacements[$0.sample.id] ?? $0.regions) }
            case let .recording(selection):
                try selection.replacingGeography(replacements).attributedSamples()
                    .map { $0.reporting(primaryRegions: primaryRegions) }
                    + samples.filter { !$0.sample.source.isGPS }
        }
        return DayAggregator(calendar: calendar, timeZone: calendar.timeZone)
            .report(for: day.year, history: corrected, manualDays: manualDays)
            .days.first { $0.day == day }?.regions ?? []
    }
}
