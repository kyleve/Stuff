import Foundation
import LogKit
import Observation

private let exportTimestampFormatter = Date.ISO8601FormatStyle(
    includingFractionalSeconds: true,
)

private final class ObservationHandle: @unchecked Sendable {
    private var task: Task<Void, Never>?

    func start(_ operation: @escaping @MainActor () async -> Void) {
        task = Task { await operation() }
    }

    func cancel() {
        task?.cancel()
    }
}

/// Drives ``LogViewer``: mirrors a ``LogStore`` into observable state and
/// applies the active filters. Recording happens off the main actor in the
/// store; this model only consumes snapshots on the main actor for display.
@MainActor
@Observable
final class LogViewerModel {
    private let store: LogStore
    private let categoryDisplayName: @Sendable (String) -> String
    @ObservationIgnored private let observation = ObservationHandle()

    private(set) var entries: [LogEntry]

    private var cachedCategories: [String]?
    private var cachedFilteredEntries: [LogEntry]?

    var searchText = "" {
        didSet { if searchText != oldValue { invalidateFilterCache() } }
    }

    var minimumLevel: LogLevel = .debug {
        didSet { if minimumLevel != oldValue { invalidateFilterCache() } }
    }

    /// `nil` means "all categories".
    var selectedCategory: String? {
        didSet { if selectedCategory != oldValue { invalidateFilterCache() } }
    }

    init(
        store: LogStore,
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.store = store
        self.categoryDisplayName = categoryDisplayName
        entries = store.snapshot()
        observation.start { [weak self] in
            await self?.observe()
        }
    }

    deinit {
        observation.cancel()
    }

    /// Observe the store until this task is cancelled.
    func observe() async {
        for await snapshot in store.changes() {
            entries = snapshot
            invalidateEntryCache()
        }
    }

    /// Distinct categories present in the buffer, sorted for a stable filter.
    var categories: [String] {
        if let cachedCategories {
            return cachedCategories
        }
        let result = Array(Set(entries.map(\.category))).sorted()
        cachedCategories = result
        return result
    }

    /// Entries newest-first, after level/category/search filters.
    var filteredEntries: [LogEntry] {
        if let cachedFilteredEntries {
            return cachedFilteredEntries
        }
        let result = entries.reversed().filter { entry in
            guard entry.level >= minimumLevel else { return false }
            if let selectedCategory, entry.category != selectedCategory { return false }
            guard !searchText.isEmpty else { return true }
            let displayCategory = categoryDisplayName(entry.category)
            return entry.message.localizedCaseInsensitiveContains(searchText)
                || displayCategory.localizedCaseInsensitiveContains(searchText)
        }
        cachedFilteredEntries = result
        return result
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// The store has entries, but the active filters exclude all of them.
    var hasNoFilterMatches: Bool {
        !isEmpty && filteredEntries.isEmpty
    }

    func clear() {
        store.clear()
        entries = store.snapshot()
        invalidateEntryCache()
    }

    /// Plain-text rendering of the currently-filtered entries, for share/copy.
    func exportText() -> String {
        Self.formatExportText(
            entries: filteredEntries.reversed(),
            categoryDisplayName: categoryDisplayName,
        )
    }

    nonisolated static func formatExportText(
        entries: [LogEntry],
        categoryDisplayName: @escaping @Sendable (String) -> String,
    ) -> String {
        entries.map { entry in
            let timestamp = entry.date.formatted(exportTimestampFormatter)
            let level = entry.level.badgeLabel
            let category = categoryDisplayName(entry.category)
            return "\(timestamp) [\(level)] \(category): \(entry.message)"
        }
        .joined(separator: "\n")
    }

    private func invalidateEntryCache() {
        cachedCategories = nil
        invalidateFilterCache()
    }

    private func invalidateFilterCache() {
        cachedFilteredEntries = nil
    }
}
