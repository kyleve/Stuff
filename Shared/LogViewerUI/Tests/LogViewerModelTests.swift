import Foundation
import LogKit
@testable import LogViewerUI
import Testing

@MainActor
struct LogViewerModelTests {
    private func seededStore() -> LogStore {
        let store = LogStore()
        store.record(LogEntry(level: .debug, subsystem: "s", category: "Net", message: "debug net"))
        store.record(LogEntry(level: .info, subsystem: "s", category: "Net", message: "info net"))
        store.record(LogEntry(level: .error, subsystem: "s", category: "DB", message: "error db"))
        store.record(LogEntry(
            level: .fault,
            subsystem: "s",
            category: "DB",
            message: "fault db crash",
        ))
        return store
    }

    @Test
    func defaultsShowAllEntriesNewestFirst() {
        let model = LogViewerModel(store: seededStore())
        #expect(model.filteredEntries.map(\.message) == [
            "fault db crash",
            "error db",
            "info net",
            "debug net",
        ])
    }

    @Test
    func minimumLevelFiltersOutLowerSeverity() {
        let model = LogViewerModel(store: seededStore())
        model.minimumLevel = .error
        #expect(model.filteredEntries.map(\.message) == ["fault db crash", "error db"])
    }

    @Test
    func categoryFilterRestrictsToSelection() {
        let model = LogViewerModel(store: seededStore())
        model.selectedCategory = "Net"
        #expect(model.filteredEntries.map(\.category) == ["Net", "Net"])
        #expect(model.categories == ["DB", "Net"])
    }

    @Test
    func searchMatchesMessageAndCategory() {
        let model = LogViewerModel(store: seededStore())
        model.searchText = "crash"
        #expect(model.filteredEntries.map(\.message) == ["fault db crash"])

        model.searchText = "net"
        #expect(model.filteredEntries.count == 2)
    }

    @Test
    func searchMatchesCategoryDisplayName() {
        let store = LogStore()
        store.record(LogEntry(
            level: .info,
            subsystem: "s",
            category: "net.raw",
            message: "connected",
        ))
        let model = LogViewerModel(store: store, categoryDisplayName: { _ in "Networking" })
        model.searchText = "network"
        #expect(model.filteredEntries.map(\.message) == ["connected"])
    }

    @Test
    func warningFiltersBetweenNoticeAndError() {
        let store = LogStore()
        store.record(LogEntry(level: .notice, subsystem: "s", category: "C", message: "n"))
        store.record(LogEntry(level: .warning, subsystem: "s", category: "C", message: "w"))
        store.record(LogEntry(level: .error, subsystem: "s", category: "C", message: "e"))
        let model = LogViewerModel(store: store)
        model.minimumLevel = .warning
        #expect(model.filteredEntries.map(\.message) == ["e", "w"])
    }

    @Test
    func combinedLevelCategoryAndSearchFilters() {
        let model = LogViewerModel(store: seededStore())
        model.minimumLevel = .error
        model.selectedCategory = "DB"
        model.searchText = "fault"
        #expect(model.filteredEntries.map(\.message) == ["fault db crash"])
    }

    @Test
    func hasNoFilterMatchesWhenFiltersExcludeEverything() {
        let model = LogViewerModel(store: seededStore())
        model.searchText = "missing-term"
        #expect(!model.isEmpty)
        #expect(model.hasNoFilterMatches)
        #expect(model.filteredEntries.isEmpty)
    }

    @Test
    func clearEmptiesModelEntries() {
        let model = LogViewerModel(store: seededStore())
        model.clear()
        #expect(model.isEmpty)
    }

    @Test
    func exportTextRendersOldestFirst() {
        let model = LogViewerModel(store: seededStore())
        model.minimumLevel = .error
        let text = model.exportText()
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.contains("error db") == true)
        #expect(lines.last?.contains("fault db crash") == true)
    }

    @Test
    func exportTextUsesCategoryDisplayName() {
        let model = LogViewerModel(store: seededStore(), categoryDisplayName: { category in
            category == "DB" ? "Database" : category
        })
        let text = model.exportText()
        #expect(text.contains("Database"))
        #expect(!text.contains("] DB:"))
    }

    @Test
    func observeReflectsLiveStoreUpdates() async {
        let store = LogStore()
        let model = LogViewerModel(store: store)

        store.record(LogEntry(level: .info, subsystem: "s", category: "Net", message: "live"))

        let deadline = Date(timeIntervalSinceNow: 1)
        while model.entries.isEmpty, Date() < deadline {
            await Task.yield()
        }

        #expect(model.entries.map(\.message) == ["live"])
    }
}
