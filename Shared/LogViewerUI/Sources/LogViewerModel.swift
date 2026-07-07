import Foundation
import LogKit
import Observation

private let exportTimestampFormatter = Date.ISO8601FormatStyle(
    includingFractionalSeconds: true,
)

private final class ObservationHandle: @unchecked Sendable {
    private var tasks: [Task<Void, Never>] = []

    func start(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { await operation() })
    }

    func cancel() {
        for task in tasks {
            task.cancel()
        }
    }
}

/// Drives ``LogViewer``: mirrors one or more ``LogStore``s into observable
/// state (merged chronologically) and applies the active filters. Recording
/// happens off the main actor in the store(s); this model only consumes
/// snapshots on the main actor for display.
@MainActor
@Observable
final class LogViewerModel {
    private let stores: [LogStore]
    private let categoryDisplayName: @Sendable (String) -> String
    @ObservationIgnored private let observation = ObservationHandle()

    /// The most recent snapshot from each store, kept in `stores` order so a
    /// change to one store re-merges without re-reading the others.
    @ObservationIgnored private var latestSnapshots: [[LogEntry]]

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
        stores: [LogStore],
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.stores = stores
        self.categoryDisplayName = categoryDisplayName
        latestSnapshots = stores.map { $0.snapshot() }
        entries = Self.merged(latestSnapshots)
        // Observe each store on its own task. Each loop re-promotes `self` per
        // iteration (`guard let self else { break }`), so between log lines the
        // tasks hold only a weak reference: the model can deinit while parked in
        // `for await`, and `deinit` then cancels every task. (An instance
        // `observe()` call would instead keep `self` alive for the streams'
        // whole lifetime — see `YearReportModel.observeDataChanges()`.)
        for index in stores.indices {
            let store = stores[index]
            observation.start { [weak self] in
                for await snapshot in store.changes() {
                    guard let self else { break }
                    apply(snapshot, at: index)
                }
            }
        }
    }

    /// Convenience for the common single-buffer case.
    convenience init(
        store: LogStore,
        categoryDisplayName: @escaping @Sendable (String) -> String = { $0 },
    ) {
        self.init(stores: [store], categoryDisplayName: categoryDisplayName)
    }

    deinit {
        observation.cancel()
    }

    private func apply(_ snapshot: [LogEntry], at index: Int) {
        latestSnapshots[index] = snapshot
        entries = Self.merged(latestSnapshots)
        invalidateEntryCache()
    }

    /// Flatten every store's snapshot into one oldest-first list. Each store's
    /// snapshot is already chronological; sorting by `date` interleaves them.
    private static func merged(_ snapshots: [[LogEntry]]) -> [LogEntry] {
        guard snapshots.count > 1 else { return snapshots.first ?? [] }
        return snapshots.flatMap(\.self).sorted { $0.date < $1.date }
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
        for store in stores {
            store.clear()
        }
        latestSnapshots = stores.map { $0.snapshot() }
        entries = Self.merged(latestSnapshots)
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
