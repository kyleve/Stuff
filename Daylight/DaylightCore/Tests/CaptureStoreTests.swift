@testable import DaylightCore
import Foundation
import Testing

struct CaptureStoreTests {
    @Test func roundTripsStateAcrossOwnersAndRejectsCorruption() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let store = try CaptureStore(root: root)
        var settings = CaptureSettings.standard
        settings.recipe.preset = .warm
        try await store.saveSettings(settings)
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunset),
            date: Date(timeIntervalSince1970: 10000),
        )
        let sequence = CaptureSequence(event: event, settings: settings)
        try await store.save(sequence)
        let reopened = try CaptureStore(root: root)
        #expect(try await reopened.settings() == settings)
        #expect(try await reopened.sequences() == [sequence])
        try Data("broken".utf8).write(to: root.appendingPathComponent("settings.json"))
        await #expect(throws: (any Error).self) { try await reopened.settings() }
    }
}
