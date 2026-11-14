import Foundation
import Testing
@testable import WhereCore

@MainActor
struct DataCompatibilityReceiptTests {
    @Test func fileRoundTripIsExcludedFromBackupAndBlocksOtherVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let store = FileDataCompatibilityReceipt(directory: directory)
        #expect(try store.load() == nil)
        try store.save(.init(
            accountID: .init(rawValue: "test-account"),
            version: .init(rawValue: 2),
            access: .verified,
            removedDeviceID: nil,
        ))
        let receipt = try #require(try store.load())
        try receipt.requireAccess(version: .init(rawValue: 2))
        #expect(throws: DataCompatibilityFailure.self) {
            try receipt.requireAccess(version: .baseline)
        }
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true)
        try store.save(.init(
            accountID: receipt.accountID,
            version: receipt.version,
            access: .blocked,
            removedDeviceID: nil,
        ))
        #expect(throws: DataCompatibilityFailure.self) {
            try #require(try store.load()).requireAccess(version: .init(rawValue: 2))
        }
    }

    @Test func corruptReceiptIsNotMissingVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: directory.appending(path: "receipt.json"))
        let store = FileDataCompatibilityReceipt(directory: directory)
        #expect(throws: DecodingError.self) { try store.load() }
    }

    @Test(arguments: [0, -1])
    func nonpositiveReceiptVersionThrows(value: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: [
            "accountID": "account-a",
            "version": value,
            "access": "verified",
        ])
        try data.write(to: directory.appending(path: "receipt.json"))
        #expect(throws: DecodingError.self) {
            try FileDataCompatibilityReceipt(directory: directory).load()
        }
    }
}
