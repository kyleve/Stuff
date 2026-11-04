import Foundation
@_spi(Testing) @testable import WhereCore

/// A controlled batch at the committed mirrored-record boundary. Production value-store
/// writers persist each row; the production remote-change observer receives the signal.
/// This adapter does not model CloudKit transport, conflict resolution, or delivery timing.
struct InstallationHistoryDelivery {
    let samples: [LocationSample]
    let profiles: [RecordingDeviceProfile]
    let removals: [RecordingDeviceRemoval]
    let records: [VersionedHistoryRecord]

    func commit(
        to store: SwiftDataStore,
        remoteChanges: ScriptedStoreRemoteChangeSource,
    ) async throws {
        try await store.perform {
            for profile in profiles {
                try await store.addRecordingDeviceProfile(profile)
            }
            for sample in samples {
                try await store.add(sample: sample)
            }
            for removal in removals {
                try await store.addRecordingDeviceRemoval(removal)
            }
            for record in records {
                try await store.addVersionedHistoryRecord(record)
            }
        }
        remoteChanges.yield()
    }
}
