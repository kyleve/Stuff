import Foundation
import Testing
@testable import WhereCore

struct FileSharedEvidenceDraftQueueTests {
    @Test func independentWritersPublishCompleteDraftsAndExcludeThemFromBackup() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let first = FileSharedEvidenceDraftQueue(directory: directory)
        let second = FileSharedEvidenceDraftQueue(directory: directory)
        let a = try makeSharedEvidenceDraft()
        let b = try makeSharedEvidenceDraft()
        async let saveA: Void = first.enqueue(a)
        async let saveB: Void = second.enqueue(b)
        _ = try await (saveA, saveB)
        #expect(try await Set(first.pendingDraftIDs()) == [a.id, b.id])
        #expect(try await first.draft(for: a.id) == a)
        #expect(try await first.draft(for: b.id) == b)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true)
        try await second.enqueue(a)
        #expect(try await first.pendingDraftIDs().count == 2)
        try await first.acknowledge(a.id)
        try await first.acknowledge(a.id)
        #expect(try await second.draft(for: a.id) == nil)
        #expect(try await second.pendingDraftIDs() == [b.id])
    }

    @Test func conflictingIdentityCannotReplacePublishedBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let first = FileSharedEvidenceDraftQueue(directory: directory)
        let second = FileSharedEvidenceDraftQueue(directory: directory)
        let a = try makeSharedEvidenceDraft()
        let b = try SharedEvidenceDraft(id: a.id, items: makeSharedEvidenceDraft().items)
        try await first.enqueue(a)
        await #expect(throws: SharedEvidenceDraft.ValidationError.conflictingIdentity) {
            try await second.enqueue(b)
        }
        #expect(try await first.draft(for: a.id) == a)
    }

    @Test func corruptionIsAnErrorAndLeavesTheFileAvailableForRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
        }
        let queue = FileSharedEvidenceDraftQueue(directory: directory)
        #expect(try await queue.pendingDraftIDs().isEmpty)
        let draft = try makeSharedEvidenceDraft()
        try await queue.enqueue(draft)
        let file = directory.appending(path: draft.id.rawValue.uuidString)
            .appendingPathExtension("json")
        try Data("incomplete draft".utf8).write(to: file)
        #expect(try await queue.pendingDraftIDs() == [draft.id])
        await #expect(throws: DecodingError.self) { try await queue.draft(for: draft.id) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
