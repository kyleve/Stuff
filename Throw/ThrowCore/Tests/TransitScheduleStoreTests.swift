import Foundation
import Testing
@testable import ThrowCore

struct TransitScheduleStoreTests {
    @Test func memoryStoreRoundTripsSchedule() async throws {
        let store = InMemoryTransitScheduleStore(schedule: nil)
        let schedule = try TransitFixture.schedule()
        try await store.save(schedule)
        #expect(try await store.load() == schedule)
    }

    @Test func fileStoreReportsCorruptCacheInsteadOfEmptySuccess() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "schedule.plist")
        try Data("corrupt".utf8).write(to: url)
        let store = FileTransitScheduleStore(fileURL: url)
        await #expect(throws: TransitDataError.invalidSchedule) { try await store.load() }
    }
}
