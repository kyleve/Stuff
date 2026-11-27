import Foundation
import Synchronization
import Testing
@testable import WhereCore

struct SharedEvidenceWriterTests {
    private let phone = RecordingDeviceID(rawValue: UUID())
    private var profile: RecordingDeviceProfile {
        .init(
            id: phone,
            systemName: "iPhone",
            kind: .phone,
            registeredAt: .now,
            registrationGenerationID: .initial,
        )
    }

    private var draft: Evidence {
        Evidence(kind: .document, capturedAt: .now, note: "Trip ticket", contentType: .pdf)
    }

    private func receipt(generation: WhereDataGenerationID = .initial) -> DataCompatibilityReceipt {
        DataCompatibilityReceipt(
            domain: .local,
            version: .current,
            access: .verified,
            removedDeviceID: nil,
        )
        .withShareAuthor(.init(deviceID: phone, generationID: generation))
    }

    @Test func confirmedInstallationCanShareWithoutRecordingAndPreservesEveryBlob() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.addRecordingDeviceProfile(profile) }
        let attachment = draft
        let note = draft
        let data = Data([1, 3, 8])
        let writer = SharedEvidenceWriter(access: FixedDataCompatibilityAccess(receipt: receipt()))
        try await writer.save([
            .init(evidence: attachment, blob: data),
            .init(evidence: note, blob: nil),
        ]) { store }
        let evidence = try await store.allEvidence()
        #expect(Set(evidence.map(\.id)) == [attachment.id, note.id])
        #expect(evidence.allSatisfy { $0.addedByDeviceID == phone })
        #expect(try await store.read(for: attachment.id) == data)
        #expect(try await store.read(for: note.id) == nil)
    }

    @Test(arguments: [0, 1, 2])
    func changingOrMissingReceiptRejectsDraftWithoutPartialData(validReads: Int) async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.addRecordingDeviceProfile(profile) }
        let initial = receipt()
        let access = ChangingShareAccess(initial: initial, validReads: validReads)
        let writer = SharedEvidenceWriter(access: access)
        let item = draft
        let opened = Mutex(0)
        await #expect(throws: SharedEvidenceWriter.AccessUnavailable.self) {
            try await writer.save([.init(evidence: item, blob: Data([1]))]) {
                opened.withLock { $0 += 1 }
                return store
            }
        }
        #expect(opened.withLock { $0 } == (validReads == 2 ? 1 : 0))
        #expect(try await store.allEvidence().isEmpty)
        #expect(try await store.read(for: item.id) == nil)
    }

    @Test(arguments: [WhereDataGenerationReason.accountReset, .backupReplace])
    func retiredGenerationCannotWriteAfterResetOrReplace(
        reason: WhereDataGenerationReason,
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.addRecordingDeviceProfile(profile) }
        let writer = SharedEvidenceWriter(access: FixedDataCompatibilityAccess(receipt: receipt()))
        let next = try await store.perform {
            try await store.rotateDataGeneration(reason: reason, changedBy: phone, at: .now)
        }
        await #expect(throws: SharedEvidenceWriter.AccessUnavailable.self) {
            try await writer.save([.init(evidence: draft, blob: nil)]) { store }
        }
        if reason == .accountReset {
            // A freshly stamped but pre-reset profile still cannot author new content.
            let staleProfile =
                SharedEvidenceWriter(
                    access: FixedDataCompatibilityAccess(receipt: receipt(generation: next
                            .id)),
                )
            await #expect(throws: SharedEvidenceWriter.AccessUnavailable.self) {
                try await staleProfile.save([.init(evidence: draft, blob: nil)]) { store }
            }
        }
        #expect(try await store.allEvidence().isEmpty)
    }

    @Test func removalArrivingBeforeAppObservesItRejectsTheDraft() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.addRecordingDeviceProfile(profile) }
        let writer = SharedEvidenceWriter(access: FixedDataCompatibilityAccess(receipt: receipt()))
        try await store.perform {
            try await store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: phone,
                removedAt: .now,
                removedByDeviceID: RecordingDeviceID(rawValue: UUID()),
            ))
        }
        await #expect(throws: SharedEvidenceWriter.AccessUnavailable.self) {
            try await writer.save([.init(evidence: draft, blob: nil)]) { store }
        }
        #expect(try await store.allEvidence().isEmpty)
    }
}

/// The third check runs after the writes have been staged.
private final class ChangingShareAccess: DataCompatibilityAccessChecking {
    private let initial: DataCompatibilityReceipt
    private let validReads: Int
    private let reads = Mutex(0)

    init(initial: DataCompatibilityReceipt, validReads: Int) {
        self.initial = initial
        self.validReads = validReads
    }

    func requireAccess(version: DataModelVersion) throws -> DataCompatibilityReceipt {
        let count = reads.withLock { count in
            count += 1
            return count
        }
        let current = count <= validReads ? initial : initial.withShareAuthor(nil)
        try current.requireAccess(version: version)
        return current
    }
}
