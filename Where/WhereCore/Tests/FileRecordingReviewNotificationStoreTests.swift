import Foundation
import Testing
@testable import WhereCore

struct FileRecordingReviewNotificationStoreTests {
    @Test func savedContextSurvivesRelaunchAndCleanupIsIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { cleanup(directory) }
        let original = try notification()
        let first = FileRecordingReviewNotificationStore(directory: directory)
        #expect(try await first.load(original.id) == nil)
        try await first.save(original)
        try await first.save(original)
        let relaunched = FileRecordingReviewNotificationStore(directory: directory)
        #expect(try await relaunched.load(original.id) == original)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true)
        try await relaunched.remove(original.id)
        try await relaunched.remove(original.id)
        #expect(try await first.load(original.id) == nil)
        try await relaunched.save(original)
        try await relaunched.removeAll()
        try await relaunched.removeAll()
        #expect(try await relaunched.load(original.id) == nil)
    }

    @Test func corruptAndMismatchedFilesFailInsteadOfReportingMissingWork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { cleanup(directory) }
        let original = try notification()
        let store = FileRecordingReviewNotificationStore(directory: directory)
        try await store.save(original)
        let file = directory.appendingPathComponent(original.id.rawValue.uuidString)
            .appendingPathExtension("json")
        try Data("invalid".utf8).write(to: file)
        await #expect(throws: DecodingError.self) { try await store.load(original.id) }
        await #expect(throws: DecodingError.self) { try await store.save(original) }
        let different = try notification()
        try JSONEncoder().encode(different).write(to: file)
        await #expect(throws: FileRecordingReviewNotificationStore.StorageError.identityMismatch) {
            try await store.load(original.id)
        }
    }

    @Test func existingContextCannotBeRewrittenForAnAlreadyDeliveredNotification() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { cleanup(directory) }
        let original = try notification()
        let store = FileRecordingReviewNotificationStore(directory: directory)
        try await store.save(original)
        var object = try #require(JSONSerialization
            .jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["policyVersion"] = ["major": 1, "minor": 1, "patch": 0]
        let changed = try JSONDecoder().decode(
            RecordingReviewNotification.self,
            from: JSONSerialization.data(withJSONObject: object),
        )
        await #expect(throws: FileRecordingReviewNotificationStore.StorageError
            .conflictingContext)
        {
            try await store.save(changed)
        }
        #expect(try await store.load(original.id) == original)
    }

    @Test func storageFailureDoesNotBecomeASuccessfulSave() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { cleanup(directory) }
        try Data("not a directory".utf8).write(to: directory)
        let store = FileRecordingReviewNotificationStore(directory: directory)
        await #expect(throws: (any Error).self) { try await store.save(notification()) }
    }

    private func notification() throws -> RecordingReviewNotification {
        let snapshot = try RecordingReviewTestSupport.snapshot([
            RecordingIssueTestSupport.issue(start: 100, end: 300),
        ])
        return try RecordingReviewNotification(
            references: [RecordingReviewTestSupport.reference(snapshot)],
            binding: .local(storeID: .init(rawValue: "test")),
        )
    }

    private func cleanup(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            Issue.record(error)
        }
    }
}
