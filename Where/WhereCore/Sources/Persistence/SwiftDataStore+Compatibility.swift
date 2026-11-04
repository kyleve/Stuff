import Foundation
import SwiftData

extension SwiftDataStore {
    public func dataCompatibilityState() async throws -> DataCompatibilityStoreState {
        try Self.compatibilityState(in: readContext())
    }

    static func compatibilityState(in context: ModelContext) throws -> DataCompatibilityStoreState {
        let requirements = try context.fetch(FetchDescriptor<SDDataCompatibilityRequirement>())
        var requiredMajor: UInt = 0
        for requirement in requirements {
            guard let value = requirement.requiredMajor, let major = UInt(exactly: value) else {
                throw DataCompatibilityError.incompleteRecord
            }
            requiredMajor = max(requiredMajor, major)
        }
        var recordMajors: Set<UInt> = []
        for record in try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>()) {
            guard let data = record.envelope else { throw DataCompatibilityError.incompleteRecord }
            let header = try JSONDecoder().decode(VersionedHistoryRecord.Header.self, from: data)
            recordMajors.insert(header.semantics.major)
        }
        return try .init(
            persistedRequiredMajor: requirements.isEmpty ? nil : requiredMajor,
            recordMajors: recordMajors,
            hasLegacyHistory: hasLegacyHistory(in: context),
        )
    }

    private static func hasLegacyHistory(in context: ModelContext) throws -> Bool {
        func contains<T: PersistentModel>(_: T.Type) throws -> Bool {
            var descriptor = FetchDescriptor<T>()
            descriptor.fetchLimit = 1
            return try context.fetchCount(descriptor) > 0
        }
        for type in inspectorModelTypes {
            if type == SDDataCompatibilityRequirement.self || type == SDVersionedHistoryRecord
                .self { continue }
            if try contains(type) { return true }
        }
        return false
    }

    public func raiseRequiredDataMajor(_ major: UInt) async throws {
        let context = mutationContext()
        let state = try Self.compatibilityState(in: context)
        let nextMajor = max(major, state.requiredMajor)
        if let persisted = state.persistedRequiredMajor, persisted >= nextMajor { return }
        guard let stored = Int64(exactly: nextMajor) else {
            throw DataCompatibilityError.incompleteRecord
        }
        let row = SDDataCompatibilityRequirement()
        row.requiredMajor = stored
        context.insert(row)
    }

    public func versionedHistoryRecords(policy: DataCompatibilityPolicy) async throws
        -> [VersionedHistoryRecord]
    {
        let context = readContext()
        try Self.compatibilityState(in: context).validate(policy: policy)
        let generation = try await dataGeneration().id
        var records: [VersionedHistoryRecord.ID: VersionedHistoryRecord] = [:]
        for row in try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>()) {
            guard let data = row.envelope else { throw DataCompatibilityError.incompleteRecord }
            let value = try VersionedHistoryRecord.admit(data, policy: policy)
            guard value.dataGenerationID == generation else { continue }
            if let old = records[value.id],
               old != value { throw DataCompatibilityError.conflictingRecord }
            records[value.id] = value
        }
        return records.values.sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
    }

    public func addVersionedHistoryRecord(_ record: VersionedHistoryRecord) async throws {
        let context = mutationContext()
        guard record.dataGenerationID == mutationGenerationID() else {
            throw RecordingPersistenceError.dataGenerationChanged
        }
        for row in try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>()) {
            guard let data = row.envelope else { throw DataCompatibilityError.incompleteRecord }
            let existing = try JSONDecoder().decode(VersionedHistoryRecord.self, from: data)
            guard existing.id == record.id,
                  existing.dataGenerationID == record.dataGenerationID else { continue }
            guard existing == record else { throw DataCompatibilityError.conflictingRecord }
            return
        }
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(record)
        context.insert(row)
    }
}

/// Global immutable floors survive reset and replace-import. Concurrent appends merge by max.
@Model
final class SDDataCompatibilityRequirement {
    var requiredMajor: Int64?
    init() {}
}

/// The version and payload travel in one CloudKit field. A partial field is an admission failure.
@Model
final class SDVersionedHistoryRecord {
    var envelope: Data?
    init() {}
}
