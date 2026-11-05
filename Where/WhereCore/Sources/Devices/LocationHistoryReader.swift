import Foundation
import RegionKit

/// The shared history read path. One store snapshot supplies raw observations, corrections,
/// calendar context, and device controls before any consumer groups the selected geography.
public struct LocationHistoryReader: Sendable {
    let store: any WhereStore
    let policy: DataCompatibilityPolicy
    private let geography: HistoryRegionAttribution

    public init(
        store: any WhereStore,
        policy: DataCompatibilityPolicy,
        geography: HistoryRegionAttribution,
    ) {
        self.store = store
        self.policy = policy
        self.geography = geography
    }

    public func projection(
        for query: LocationHistoryQuery,
        calendar: Calendar,
        attributor: any RegionAttributing,
    ) async throws -> LocationHistoryProjection {
        try await store.readSnapshot {
            // Foundation stores already enforce their admitted major at the physical read.
            // Merely shipping the next resolver must not activate an existing dataset.
            let major = try await admittedMajor()
            if major == 0 {
                return try await foundationProjection(
                    within: query.viewingPeriod(in: calendar),
                    attributor: attributor,
                )
            }
            guard major == RecordingEvidencePolicy.version.major else {
                throw RecordingHistorySelection.ValidationError.unsupportedPolicy
            }
            return try await recordingProjection(
                for: query,
                calendar: calendar,
                attributor: attributor,
            )
        }
    }

    func admittedMajor() async throws -> UInt {
        let major = policy.supportedMajors == [0] ? 0 : try await store.dataContractMajor()
        try policy.validate(requiredMajor: major)
        return major
    }

    /// Exact instant reads do not depend on a viewing calendar. Logical-date callers use the
    /// explicit query overload so a year or day boundary cannot truncate recording evidence.
    public func projection(
        in interval: DateInterval,
        attributor: any RegionAttributing,
    ) async throws -> LocationHistoryProjection {
        try await projection(
            for: .instants(RecordingPeriod(start: interval.start, end: interval.end)),
            calendar: Calendar(identifier: .gregorian),
            attributor: attributor,
        )
    }

    private func foundationProjection(
        within period: RecordingPeriod,
        attributor: any RegionAttributing,
    ) async throws -> LocationHistoryProjection {
        let attribution = try await attributionSnapshot(attributor)
        let samples = try await store.samples(in: DateInterval(
            start: period.start,
            end: period.end,
        ))
        let removals = try await store.recordingDeviceRemovals()
        let visible = RecordingDeviceRemovalFilter.visibleSamples(samples, removals: removals)
            .sorted(by: Self.ordered)
        let revisions = try await store.sampleAttributionRevisions(for: Set(visible.map(\.id)))
            .sorted { $0.id < $1.id }
        let winners = Self.winners(revisions)
        return LocationHistoryProjection(
            samples: visible.map { sample in
                let replacement = sample.source.isGPS ? winners[sample.id]?.replacementRegions : nil
                return AttributedLocationSample(
                    sample: sample,
                    regions: replacement ?? [attribution.region(at: sample.coordinate)],
                )
            },
            revisions: revisions,
        )
    }

    private func recordingProjection(
        for query: LocationHistoryQuery,
        calendar: Calendar,
        attributor: any RegionAttributing,
    ) async throws -> LocationHistoryProjection {
        let period = try query.recordingPeriod()
        let padding = RecordingEvidencePolicy.evidencePadding
        let samples = try await store.samples(in: DateInterval(
            start: period.start.addingTimeInterval(-padding),
            end: period.end.addingTimeInterval(padding),
        )).sorted(by: Self.ordered)
        let controls = try await RecordingControlStore(store: store, policy: policy).snapshot()
        let removals = try await store.recordingDeviceRemovals()
        let revisions = try await store.sampleAttributionRevisions(for: Set(samples.map(\.id)))
            .sorted { $0.id < $1.id }
        let catalog = await geography.snapshot()
        let observations = try RecordingObservation.history(
            samples: samples,
            corrections: revisions,
            controls: controls,
            catalog: catalog,
            version: policy.current,
        )
        let selected = try RecordingHistorySelection.resolve(
            observations: observations,
            controls: controls,
            removals: removals,
            within: period,
            version: policy.current,
        )
        var entries = try selected.attributedSamples()
        let attribution = try await attributionSnapshot(attributor)
        entries.append(contentsOf: samples.filter { !$0.source.isGPS }.map {
            AttributedLocationSample(sample: $0, regions: [attribution.region(at: $0.coordinate)])
        })
        return LocationHistoryProjection(
            samples: entries.filter { query.contains($0, viewingCalendar: calendar) }
                .sorted { Self.ordered($0.sample, $1.sample) },
            revisions: revisions,
            contract: .recording(selected),
        )
    }

    private static func ordered(_ lhs: LocationSample, _ rhs: LocationSample) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func winners(_ revisions: [SampleAttributionRevision])
        -> [UUID: SampleAttributionRevision]
    {
        var winners: [UUID: SampleAttributionRevision] = [:]
        for revision in revisions {
            if let current = winners[revision.sampleID],
               !SampleAttributionRevision.newer(revision, than: current) { continue }
            winners[revision.sampleID] = revision
        }
        return winners
    }

    func attributionSnapshot(_ attributor: any RegionAttributing) async throws
        -> any RegionAttributing
    {
        if let live = attributor as? RegionAttribution {
            return try await live.snapshot(for: store.trackedRegions())
        }
        return attributor
    }

    func correctionAttribution(
        for projection: LocationHistoryProjection,
        attributor: any RegionAttributing,
    ) async throws -> any RegionAttributing {
        switch projection.contract {
            case .foundation: try await attributionSnapshot(attributor)
            case .recording: await geography.snapshot()
        }
    }
}
