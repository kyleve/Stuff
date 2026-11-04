import Foundation
import Testing
@testable import WhereCore

@MainActor
struct FileDataCompatibilityCacheTests {
    @Test func absentAndCorruptFilesAreDistinct() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let file = directory.appendingPathComponent("compatibility.json")
        let cache = FileDataCompatibilityCache(fileURL: file)
        #expect(try cache.load() == nil)
        let value = DataCompatibilityCache(
            storeID: DataCompatibilityTestSupport.storeID,
            accountID: ScriptedSharedDataCompatibilityTransport.account,
            requiredMajor: 4,
            verified: false,
        )
        try cache.save(value)
        #expect(try FileDataCompatibilityCache(fileURL: file).load() == value)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true)
        try Data("not json".utf8).write(to: file)
        #expect(throws: DecodingError.self) { try cache.load() }
    }
}
