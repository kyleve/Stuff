import Foundation
import WhereCore

public actor FileManualLogEntryRepository: ManualLogEntryRepository {
    private let calendar: Calendar
    private let store: JSONFileStore<[ManualLogEntry]>
    private let seedRecords: [ManualLogEntry]

    public init(
        calendar: Calendar = .current,
        fileURL: URL,
        seedRecords: [ManualLogEntry] = [],
    ) {
        self.calendar = calendar
        store = JSONFileStore(fileURL: fileURL)
        self.seedRecords = seedRecords
    }

    public func availableYears() async -> [Int] {
        let years = Set(records().map { calendar.component(.year, from: $0.timestamp) })
        return years.sorted()
    }

    public func entries(in year: Int) async -> [ManualLogEntry] {
        records()
            .filter { calendar.component(.year, from: $0.timestamp) == year }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func save(_ entry: ManualLogEntry) async {
        var merged = Dictionary(uniqueKeysWithValues: records().map { ($0.id, $0) })
        merged[entry.id] = entry
        let ordered = merged.values.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.timestamp < rhs.timestamp
        }
        store.save(ordered)
    }

    public func delete(id: UUID) async {
        store.save(records().filter { $0.id != id })
    }

    private func records() -> [ManualLogEntry] {
        store.load(defaultValue: seedRecords)
    }
}
