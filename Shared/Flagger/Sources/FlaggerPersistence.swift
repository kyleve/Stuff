import Foundation
import SwiftData

@ModelActor
actor FlaggerPersistence {
    struct StoreSnapshot {
        let revision: UInt64
        let values: [FlagID: JSONValue]
    }

    private var revision: UInt64 = 0

    func load() throws -> StoreSnapshot {
        try snapshot()
    }

    func remove(_ ids: Set<FlagID>) throws -> StoreSnapshot {
        guard ids.isEmpty == false else { return try snapshot() }
        let rows = try modelContext.fetch(FetchDescriptor<FlagOverride>())
        for row in rows where ids.contains(FlagID(rawValue: row.key)) {
            modelContext.delete(row)
        }
        return try saveAndSnapshot()
    }

    func persist(_ value: JSONValue?, for id: FlagID) throws -> StoreSnapshot {
        let key = id.rawValue
        var descriptor = FetchDescriptor<FlagOverride>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        let existing = try modelContext.fetch(descriptor).first

        if let value {
            let data = try JSONEncoder.flagger.encode(value)
            if let existing {
                existing.value = data
            } else {
                modelContext.insert(FlagOverride(key: key, value: data))
            }
        } else if let existing {
            modelContext.delete(existing)
        }

        return try saveAndSnapshot()
    }

    private func snapshot() throws -> StoreSnapshot {
        let rows = try modelContext.fetch(FetchDescriptor<FlagOverride>())
        let values = try Dictionary(uniqueKeysWithValues: rows.map { row in
            try (
                FlagID(rawValue: row.key),
                JSONDecoder().decode(JSONValue.self, from: row.value)
            )
        })
        return StoreSnapshot(revision: revision, values: values)
    }

    private func saveAndSnapshot() throws -> StoreSnapshot {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        revision += 1
        return try snapshot()
    }
}
