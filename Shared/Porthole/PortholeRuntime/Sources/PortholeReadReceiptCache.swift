import Foundation
import PortholeCore

/// Read retries reuse recent results without turning subscriptions into durable history.
/// Both record count and encoded bytes bound this FIFO cache. Oversized receipts are not retained.
struct PortholeReadReceiptCache {
    private struct Entry {
        let record: PortholeOperationRecord
        let encodedBytes: Int
    }

    private let maximumCount: Int
    private let maximumBytes: Int
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private(set) var encodedBytes = 0
    var count: Int {
        entries.count
    }

    init(maximumCount: Int, maximumBytes: Int) {
        precondition(maximumCount > 0 && maximumBytes > 0)
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    func record(for operationID: UUID) -> PortholeOperationRecord? {
        entries[operationID]?.record
    }

    mutating func insert(_ record: PortholeOperationRecord) throws {
        let bytes = try JSONEncoder().encode(record).count
        remove(operationID: record.id)
        guard bytes <= maximumBytes else { return }
        while entries.count >= maximumCount || encodedBytes > maximumBytes - bytes {
            guard let oldest = order.first
            else { preconditionFailure("Read receipt accounting is inconsistent") }
            remove(operationID: oldest)
        }
        entries[record.id] = Entry(record: record, encodedBytes: bytes)
        order.append(record.id)
        encodedBytes += bytes
    }

    mutating func remove(scope: PortholeScopeToken) {
        for operationID in order where entries[operationID]?.record.invocation.scope == scope {
            remove(operationID: operationID)
        }
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        encodedBytes = 0
    }

    private mutating func remove(operationID: UUID) {
        guard let entry = entries.removeValue(forKey: operationID) else { return }
        encodedBytes -= entry.encodedBytes
        order.removeAll { $0 == operationID }
    }
}
