import Foundation
import WhereCore

public actor FileLocationSampleRepository: LocationSampleRepository {
    private let calendar: Calendar
    private let store: JSONFileStore<[LocationSample]>
    private let seedRecords: [LocationSample]

    public init(
        calendar: Calendar = .current,
        fileURL: URL,
        seedRecords: [LocationSample] = [],
    ) {
        self.calendar = calendar
        store = JSONFileStore(fileURL: fileURL)
        self.seedRecords = seedRecords
    }

    public func availableYears() async -> [Int] {
        let years = Set(records().map { calendar.component(.year, from: $0.timestamp) })
        return years.sorted()
    }

    public func samples(in year: Int) async -> [LocationSample] {
        records()
            .filter { calendar.component(.year, from: $0.timestamp) == year }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func upsert(_ samples: [LocationSample]) async {
        var merged = Dictionary(uniqueKeysWithValues: records().map { ($0.id, $0) })
        for sample in samples {
            merged[sample.id] = sample
        }

        let ordered = merged.values.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.timestamp < rhs.timestamp
        }
        store.save(ordered)
    }

    public func removeAll() async {
        store.save([])
    }

    private func records() -> [LocationSample] {
        store.load(defaultValue: seedRecords)
    }
}
