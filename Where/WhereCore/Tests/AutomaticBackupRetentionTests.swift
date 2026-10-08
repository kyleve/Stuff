import CryptoKit
import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct AutomaticBackupRetentionTests {
    @Test(arguments: [0, 1, 2, 3])
    func aChangedCandidateOrKeeperPreventsDeletion(changedIndex: Int) async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let verified = try await fixture.makeVerifiedFiles(count: 4)
        try Data("changed after authentication".utf8).write(to: verified[changedIndex].file.url)
        try await AutomaticBackupRetention(verified: verified, retainedFileCount: 3).prune()
        #expect(verified.allSatisfy { FileManager.default.fileExists(atPath: $0.file.url.path) })
    }

    @Test func aMissingKeeperPreservesTheOldestRecoverableFile() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let verified = try await fixture.makeVerifiedFiles(count: 4)
        try FileManager.default.removeItem(at: verified[1].file.url)
        await #expect(throws: CocoaError.self) {
            try await AutomaticBackupRetention(verified: verified, retainedFileCount: 3).prune()
        }
        #expect(FileManager.default.fileExists(atPath: verified[0].file.url.path))
    }

    @Test func unchangedAuthenticatedKeepersAuthorizePruning() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let verified = try await fixture.makeVerifiedFiles(count: 5)
        try await AutomaticBackupRetention(verified: verified, retainedFileCount: 3).prune()
        #expect(verified.prefix(2)
            .allSatisfy { FileManager.default.fileExists(atPath: $0.file.url.path) == false })
        #expect(verified.suffix(3)
            .allSatisfy { FileManager.default.fileExists(atPath: $0.file.url.path) })
    }

    @Test func cancelledPruningDeletesNothing() async throws {
        let fixture = try AutomaticBackupStorageFixture()
        defer { try? fixture.cleanup() }
        let verified = try await fixture.makeVerifiedFiles(count: 4)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await AutomaticBackupRetention(verified: verified, retainedFileCount: 3).prune()
        }
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(verified.allSatisfy { FileManager.default.fileExists(atPath: $0.file.url.path) })
    }
}
