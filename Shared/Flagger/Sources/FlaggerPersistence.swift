import Foundation
import SwiftData

@ModelActor
actor FlaggerPersistence {
    struct Commit {
        let sequence: UInt64
        let value: JSONValue?
    }

    private var sequence: UInt64 = 0

    func load() throws -> [FlagID: JSONValue] {
        let rows = try modelContext.fetch(FetchDescriptor<FlagOverride>())
        return try Dictionary(uniqueKeysWithValues: rows.map { row in
            try (
                FlagID(rawValue: row.key),
                JSONDecoder().decode(JSONValue.self, from: row.value)
            )
        })
    }

    func persist(_ value: JSONValue?, for id: FlagID) throws -> Commit {
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

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        sequence += 1
        return Commit(sequence: sequence, value: value)
    }
}
