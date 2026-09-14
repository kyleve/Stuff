import Foundation
import PortholeCore

public enum PortholeOperationStatus: Sendable, Equatable, Codable {
    case started
    case succeeded(PortholeValue)
    case failed(String)
    case uncertain
}

public struct PortholeOperationRecord: Sendable, Equatable, Codable, Identifiable {
    public let invocation: PortholeInvocation
    public var status: PortholeOperationStatus
    public var id: UUID {
        invocation.id
    }

    public init(invocation: PortholeInvocation, status: PortholeOperationStatus) {
        self.invocation = invocation
        self.status = status
    }
}

/// Durable receipts prevent retries from repeating a potentially completed mutation.
public actor PortholeOperationJournal {
    private struct Document: Codable {
        let version: Int
        let records: [PortholeOperationRecord]
    }

    private let url: URL?
    private var records: [UUID: PortholeOperationRecord] = [:]
    private var loaded = false

    #if DEBUG
        private var lookupBarrier: (@Sendable () async -> Void)?

        @_spi(Testing)
        public func setLookupBarrier(_ barrier: (@Sendable () async -> Void)?) {
            lookupBarrier = barrier
        }
    #endif

    public init(url: URL?) {
        self.url = url
    }

    public func record(for operationID: UUID) async throws -> PortholeOperationRecord? {
        try load()
        let record = records[operationID]
        #if DEBUG
            if let lookupBarrier { await lookupBarrier() }
        #endif
        return record
    }

    public func allRecords() throws -> [PortholeOperationRecord] {
        try load()
        return records.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func write(_ record: PortholeOperationRecord) throws {
        try load()
        var next = records
        next[record.id] = record
        if let url {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Document(version: 1, records: Array(next.values)))
            try data.write(to: url, options: .atomic)
        }
        records = next
    }

    private func load() throws {
        guard !loaded else { return }
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            loaded = true
            return
        }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
        guard document.version == 1 else {
            throw PortholeError.unsupported("Operation journal version \(document.version)")
        }
        var restored: [UUID: PortholeOperationRecord] = [:]
        for var record in document.records {
            guard restored[record.id] == nil else {
                throw PortholeError.operationConflict
            }
            if record.status == .started { record.status = .uncertain }
            restored[record.id] = record
        }
        records = restored
        loaded = true
    }
}
