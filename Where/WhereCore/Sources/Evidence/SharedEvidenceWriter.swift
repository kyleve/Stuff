import Foundation

/// Direct, local-store share writes. A draft keeps the grant it observed on opening.
public struct SharedEvidenceWriter: Sendable {
    public struct Item: Sendable {
        public let evidence: Evidence
        public let blob: Data?

        public init(evidence: Evidence, blob: Data?) {
            self.evidence = evidence
            self.blob = blob
        }
    }

    /// Share extensions display Open Where for an expired or unavailable grant.
    public struct AccessUnavailable: Error {}

    private let access: any DataCompatibilityAccessChecking
    private let author: DataCompatibilityReceipt.ShareAuthor?
    private let domain: DataCompatibilityDomain?

    public init(access: any DataCompatibilityAccessChecking) {
        self.access = access
        let receipt = try? access.requireAccess(version: .current)
        author = receipt?.shareAuthor
        domain = receipt?.domain
    }

    private func requireAuthor() throws -> DataCompatibilityReceipt.ShareAuthor {
        guard let author, let receipt = try? access.requireAccess(version: .current),
              receipt.domain == domain, receipt.shareAuthor == author,
              receipt.removedDeviceID != author.deviceID else { throw AccessUnavailable() }
        return author
    }

    public func save(
        _ items: [Item],
        openStore: @Sendable () throws -> any WhereStore,
    ) async throws {
        let grant = try requireAuthor()
        let store = try openStore()
        do {
            try await store.perform(expectedDataGenerationID: grant.generationID) {
                try await requireActiveInstallation(grant.deviceID, in: store)
                for item in items {
                    try await store.write(
                        evidence: item.evidence.added(by: grant.deviceID),
                        blob: item.blob,
                    )
                }
                _ = try requireAuthor()
                try Task.checkCancellation()
            }
        } catch RecordingPersistenceError.dataGenerationChanged {
            throw AccessUnavailable()
        } catch WhereStoreReadConflictError.changedDuringTransaction {
            throw AccessUnavailable()
        }
    }

    private func requireActiveInstallation(
        _ id: RecordingDeviceID,
        in store: any WhereStore,
    ) async throws {
        do {
            try await store.readSnapshot {
                let profiles = try await store.recordingDeviceProfiles()
                guard let profile = profiles.first(where: { $0.id == id })
                else { throw AccessUnavailable() }
                let removals = try await store.recordingDeviceRemovals()
                let reset = try await store
                    .recordingDeviceResetBarrier(for: profile.registrationGenerationID)
                guard reset == nil, !removals.contains(where: { $0.deviceID == id }) else {
                    throw AccessUnavailable()
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccessUnavailable()
        }
    }
}
