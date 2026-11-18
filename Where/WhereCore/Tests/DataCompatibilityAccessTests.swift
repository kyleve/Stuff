import Foundation
import Testing
@testable import WhereCore

struct DataCompatibilityAccessTests {
    @Test func readerRequiresExactVerifiedEvidenceBeforeOpeningHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let access = FileDataCompatibilityReceipt(directory: directory)
        #expect(throws: DataCompatibilityFailure.self) {
            try access.requireAccess(version: .baseline)
        }
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        try access.save(.init(
            domain: .local,
            version: .baseline,
            access: .verified,
            removedDeviceID: nil,
        ))
        #expect(try access.requireAccess(version: .baseline).domain == .local)
        #expect(throws: DataCompatibilityFailure.self) {
            try access.requireAccess(version: .init(rawValue: 2))
        }
        try access.save(.init(
            domain: .local,
            version: .baseline,
            access: .blocked,
            removedDeviceID: nil,
        ))
        #expect(throws: DataCompatibilityFailure.self) {
            try access.requireAccess(version: .baseline)
        }
        try Data("invalid".utf8).write(to: directory.appending(path: "receipt.json"))
        #expect(throws: DecodingError.self) { try access.requireAccess(version: .baseline) }
    }

    @Test func configuredCloudStorageWaitsForCloudAdmission() {
        let storage = SwiftDataStore.Storage.cloudKit(appGroupIdentifier: "group.test")
        #expect(storage.admitted(for: .local) == .localOnly(appGroupIdentifier: "group.test"))
        #expect(storage.admitted(for: .cloud(.init(
            containerIdentifier: "iCloud.test",
            userRecordName: "user-a",
        ))) == storage)
        #expect(SwiftDataStore.Storage.inMemory.admitted(for: .local) == .inMemory)
    }
}
