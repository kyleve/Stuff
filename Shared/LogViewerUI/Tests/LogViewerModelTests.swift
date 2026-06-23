import LogKit
@testable import LogViewerUI
import Testing

@MainActor
private func seededStore() -> LogStore {
    let store = LogStore()
    store.record(LogEntry(level: .debug, subsystem: "s", category: "Net", message: "debug net"))
    store.record(LogEntry(level: .info, subsystem: "s", category: "Net", message: "info net"))
    store.record(LogEntry(level: .error, subsystem: "s", category: "DB", message: "error db"))
    store.record(LogEntry(level: .fault, subsystem: "s", category: "DB", message: "fault db crash"))
    return store
}

@MainActor
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

@MainActor
@Test
func minimumLevelFiltersOutLowerSeverity() {
    let model = LogViewerModel(store: seededStore())
    model.minimumLevel = .error
    #expect(model.filteredEntries.map(\.message) == ["fault db crash", "error db"])
}

@MainActor
@Test
func categoryFilterRestrictsToSelection() {
    let model = LogViewerModel(store: seededStore())
    model.selectedCategory = "Net"
    #expect(model.filteredEntries.map(\.category) == ["Net", "Net"])
    #expect(model.categories == ["DB", "Net"])
}

@MainActor
@Test
func searchMatchesMessageAndCategory() {
    let model = LogViewerModel(store: seededStore())
    model.searchText = "crash"
    #expect(model.filteredEntries.map(\.message) == ["fault db crash"])

    model.searchText = "net"
    #expect(model.filteredEntries.count == 2)
}

@MainActor
@Test
func clearEmptiesModelEntries() {
    let model = LogViewerModel(store: seededStore())
    model.clear()
    #expect(model.isEmpty)
}

@MainActor
@Test
func exportTextRendersOldestFirst() {
    let model = LogViewerModel(store: seededStore())
    model.minimumLevel = .error
    let text = model.exportText { $0 }
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines.first?.contains("error db") == true)
    #expect(lines.last?.contains("fault db crash") == true)
}
