import Foundation
import LogKit
import Observation

/// Drives ``LogViewer``: mirrors a ``LogStore`` into observable state and
/// applies the active filters. Recording happens off the main actor in the
/// store; this model only consumes snapshots on the main actor for display.
@MainActor
@Observable
final class LogViewerModel {
    private let store: LogStore

    private(set) var entries: [LogEntry]

    var searchText = ""
    var minimumLevel: LogLevel = .debug
    /// `nil` means "all categories".
    var selectedCategory: String?

    init(store: LogStore) {
        self.store = store
        entries = store.snapshot()
    }

    /// Observe the store until the surrounding `.task` is cancelled.
    func observe() async {
        for await snapshot in store.changes() {
            entries = snapshot
        }
    }

    /// Distinct categories present in the buffer, sorted for a stable filter.
    var categories: [String] {
        Array(Set(entries.map(\.category))).sorted()
    }

    /// Entries newest-first, after level/category/search filters.
    var filteredEntries: [LogEntry] {
        entries.reversed().filter { entry in
            guard entry.level >= minimumLevel else { return false }
            if let selectedCategory, entry.category != selectedCategory { return false }
            guard !searchText.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(searchText)
                || entry.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func clear() {
        store.clear()
        entries = store.snapshot()
    }

    /// Plain-text rendering of the currently-filtered entries, for share/copy.
    func exportText(categoryDisplayName: (String) -> String) -> String {
        let formatter = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return filteredEntries.reversed().map { entry in
            let timestamp = entry.date.formatted(formatter)
            let level = entry.level.displayName.uppercased()
            let category = categoryDisplayName(entry.category)
            return "\(timestamp) [\(level)] \(category): \(entry.message)"
        }
        .joined(separator: "\n")
    }
}
