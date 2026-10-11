import Foundation
import Testing
@testable import WhereCore

struct WidgetCompatibilityStoreTests {
    @Test func missingBlockedAndMalformedMetadataNeverExposeCachedData() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
        let store = WidgetCompatibilityStore(directory: directory)
        #expect(try store.read() == nil)
        try store.write(.init(requiredVersion: .initial))
        #expect(try store.read()?.allowsData == true)
        #expect(try directory.appending(path: "widget-compatibility.json")
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        try store.write(.init(requiredVersion: .init(rawValue: 2)))
        #expect(try store.read()?.allowsData == false)
        try store.write(.init(requiredVersion: nil))
        #expect(try store.read()?.allowsData == false)
        try Data("broken".utf8).write(to: directory.appending(path: "widget-compatibility.json"))
        #expect(throws: DecodingError.self) { try store.read() }
    }
}
