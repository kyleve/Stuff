import Foundation
import Testing
@testable import WhereCore

struct CompatibleWidgetSnapshotReaderTests {
    @Test func cachedLocationsStayHiddenUntilCompatibilityIsKnown() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: directory) } }
        let snapshots = WidgetSnapshotStore(directory: directory)
        let compatibility = WidgetCompatibilityStore(directory: directory)
        let reader = CompatibleWidgetSnapshotReader(
            snapshotStore: snapshots,
            compatibilityStore: compatibility,
        )
        let value = WidgetSnapshot(
            day: .distantPast,
            year: 2026,
            dayRegions: [.california],
            totals: [.california: 10],
        )
        try snapshots.write(value)
        #expect(try reader.read() == nil)
        try compatibility.write(.init(requiredVersion: .initial))
        #expect(try reader.read() == value)
        try compatibility.write(.init(requiredVersion: .init(rawValue: 2)))
        #expect(try reader.read() == nil)
        try compatibility.write(.init(requiredVersion: nil))
        #expect(try reader.read() == nil)
        try Data("corrupt".utf8).write(to: directory.appending(path: "widget-compatibility.json"))
        #expect(throws: (any Error).self) { try reader.read() }
    }
}
