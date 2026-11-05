import Foundation

/// Reads only the history that can affect a proposed source choice, including causal ancestors
/// outside the displayed period. All values come from the same pinned store snapshot.
public struct RecordingReviewReader: Sendable {
    private let store: any WhereStore
    private let policy: DataCompatibilityPolicy

    public init(store: any WhereStore, policy: DataCompatibilityPolicy) {
        self.store = store
        self.policy = policy
    }

    public func evidence(for request: RecordingChoiceRequest) async throws
        -> RecordingReviewEvidence
    {
        let periods = try request.evidencePeriods()
        return try await store.readSnapshot {
            let generationID = try await store.dataGeneration().id
            let complete = try await RecordingControlStore(store: store, policy: policy).snapshot()
            let controls = try relevantControls(complete, periods: periods)
            var samples: Set<LocationSample> = []
            var manualDays: Set<DayPresence> = []
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            for period in periods {
                try await samples.formUnion(store.samples(in: DateInterval(
                    start: period.start,
                    end: period.end,
                )))
                // Manual assertions use logical dates. Include every day that any supported
                // recording offset could assign within the evidence window.
                let first = CalendarDay(
                    from: period.start.addingTimeInterval(-18 * 60 * 60),
                    in: calendar,
                )
                let last = CalendarDay(
                    from: period.end.addingTimeInterval(18 * 60 * 60),
                    in: calendar,
                )
                try await manualDays.formUnion(store.manualDays(in: first ... last))
            }
            var deviceIDs = Set(samples.compactMap(\.recordingDeviceID))
            if case let .select(deviceID) = request.action { deviceIDs.insert(deviceID) }
            if case let .recordingDay(deviceID, _) = request.scope { deviceIDs.insert(deviceID) }
            for choice in controls.sourceChoices {
                if case let .select(deviceID) = choice.action { deviceIDs.insert(deviceID) }
            }
            let removals = try await store.recordingDeviceRemovals().filter { removal in
                deviceIDs.contains(removal.deviceID)
                    && periods.contains { removal.removedAt < $0.end }
            }
            return try await RecordingReviewEvidence(
                generationID: generationID,
                policyVersion: RecordingEvidencePolicy.version,
                samples: samples,
                corrections: Set(store.sampleAttributionRevisions(for: Set(samples.map(\.id)))),
                controls: controls,
                removals: Set(removals),
                manualDays: manualDays,
                primaryRegions: store.primaryRegions(),
            )
        }
    }

    private func relevantControls(
        _ complete: RecordingControlSnapshot,
        periods: [RecordingPeriod],
    ) throws -> RecordingControlSnapshot {
        let records = Dictionary(uniqueKeysWithValues: complete.records.map { ($0.id, $0) })
        var retained = Set(complete.records.filter { record in
            switch record.scope {
                case .entireHistory: true
                case let .periods(scopes):
                    scopes.contains { scope in periods.contains { scope.overlaps($0) } }
            }
        }.map(\.id))
        var pending = Array(retained)
        while let recordID = pending.popLast() {
            guard let record = records[recordID] else { continue }
            if case let .understood(control) = try RecordingControlCodec.admit(
                record,
                policy: policy,
            ) {
                for predecessor in control.predecessorRecordIDs
                    where retained.insert(predecessor).inserted
                {
                    pending.append(predecessor)
                }
            }
        }
        return try RecordingControlSnapshot(
            records: complete.records.filter { retained.contains($0.id) },
            generationID: complete.generationID,
            policy: policy,
        )
    }
}
