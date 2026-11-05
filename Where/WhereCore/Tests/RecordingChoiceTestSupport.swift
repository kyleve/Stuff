import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

enum RecordingChoiceTestSupport {
    static let policy = RecordingBackupTestSupport.policy
    static let author = RecordingControlsTestSupport.device

    actor Commits {
        private(set) var count = 0
        func record() {
            count += 1
        }
    }

    static func request() throws -> RecordingChoiceRequest {
        try .init(
            scope: .periods([RecordingAssessmentTestSupport.period(0, 100)]),
            action: .select(author),
        )
    }

    static func sample(seconds: Double) throws -> LocationSample {
        let observation = try RecordingAssessmentTestSupport.observation(seconds: seconds)
        return LocationSample(
            id: observation.sample.id,
            timestamp: observation.sample.timestamp,
            coordinate: observation.sample.coordinate,
            horizontalAccuracy: observation.sample.horizontalAccuracy,
            source: observation.sample.source,
            recordingDeviceID: observation.deviceID,
            recordingDay: observation.recordingDay,
        )
    }

    static func store() async throws -> SwiftDataStore {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        return store
    }

    static func coordinator(
        store: any WhereStore,
        commits: Commits = Commits(),
    ) -> RecordingChoiceCoordinator {
        RecordingChoiceCoordinator(
            store: store,
            policy: policy,
            author: author,
            geography: HistoryRegionAttribution(catalog: LocationHistoryReaderTestSupport
                .Geography()),
            onCommitted: { await commits.record() },
        )
    }

    static func proposal(_ review: RecordingChoiceReview) throws -> RecordingChoiceReview.Proposal {
        guard case let .ready(proposal) = review else {
            throw TestError.expectedProposal
        }
        return proposal
    }

    static func append(_ control: RecordingControl, store: any WhereStore) async throws {
        try await store.performInCurrentGeneration {
            try await store.addVersionedHistoryRecord(RecordingControlCodec.encode(
                control,
                generationID: store.dataGeneration().id,
            ))
        }
    }

    enum TestError: Error { case expectedProposal }
}
