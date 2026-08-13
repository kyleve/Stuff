import Foundation
import os
import Testing
@_spi(Testing) import WhereCore

struct WidgetPresentationPublisherTests {
    private final class ReloadSpy: Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)

        var reloadCount: Int {
            count.withLock { $0 }
        }

        func reload() {
            count.withLock { $0 += 1 }
        }
    }

    @Test func publishesWithoutTouchingWidgetData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WidgetPresentationPublisherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)
        let reloads = ReloadSpy()
        let publisher = WidgetPresentationPublisher(store: store, reloadTimelines: reloads.reload)

        await publisher.publish(.alternate)

        #expect(store.readTheme() == .alternate)
        #expect(reloads.reloadCount == 1)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appending(path: "widget-snapshot.json").path,
        ))
    }

    @Test func repeatedThemeIsAWriteAndReloadNoOp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WidgetPresentationPublisherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)
        let reloads = ReloadSpy()
        let publisher = WidgetPresentationPublisher(store: store, reloadTimelines: reloads.reload)

        await publisher.publish(.alternate)
        await publisher.publish(.alternate)

        #expect(store.readTheme() == .alternate)
        #expect(reloads.reloadCount == 1)
    }

    @Test func sequentialChangesFinishOnTheNewestTheme() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WidgetPresentationPublisherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetPresentationStore(directory: directory)
        let reloads = ReloadSpy()
        let publisher = WidgetPresentationPublisher(store: store, reloadTimelines: reloads.reload)

        await publisher.publish(.alternate)
        await publisher.publish(.standard)

        #expect(store.readTheme() == .standard)
        #expect(reloads.reloadCount == 2)
    }
}
