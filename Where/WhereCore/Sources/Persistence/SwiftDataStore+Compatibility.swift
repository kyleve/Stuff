import Foundation
import SwiftData

extension SwiftDataStore {
    struct CompatibilityMetadata {
        let persistedRequiredMajor: UInt?
        let hasLegacyHistory: Bool

        func state(recordMajors: Set<UInt>) -> DataCompatibilityStoreState {
            .init(
                persistedRequiredMajor: persistedRequiredMajor,
                recordMajors: recordMajors,
                hasLegacyHistory: hasLegacyHistory,
            )
        }
    }

    /// Reset and Replace erase the outgoing generation's user payloads. Decode only the stable
    /// generation header; an unknown control body is not necessary to identify its storage scope.
    static func deleteVersionedHistoryRecords(
        in context: ModelContext,
        belongingTo generationID: WhereDataGenerationID,
    ) throws {
        let rows = try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>())
        // A record may arrive before its shared floor. Retain that observed requirement before
        // deleting the only payload that currently establishes it.
        if !rows.isEmpty { try persistCompatibilityFloor(0, in: context) }
        for row in rows {
            guard let data = row.envelope else { throw DataCompatibilityError.incompleteRecord }
            let header = try JSONDecoder().decode(
                VersionedHistoryRecord.GenerationHeader.self,
                from: data,
            )
            if header.dataGenerationID == generationID { context.delete(row) }
        }
    }

    public func dataCompatibilityState() async throws -> DataCompatibilityStoreState {
        let state = try indexedCompatibilityState()
        #if DEBUG
            let completion = compatibilityReadCompletion
            compatibilityReadCompletion = nil
            await completion?()
        #endif
        return state
    }

    static func compatibilityState(in context: ModelContext) throws -> DataCompatibilityStoreState {
        // This fresh scan is deliberately retained for the physical-save admission check and
        // destructive operations. It must not reuse an earlier transaction's cached headers.
        var recordMajors: Set<UInt> = []
        for record in try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>()) {
            guard let data = record.envelope else { throw DataCompatibilityError.incompleteRecord }
            let header = try JSONDecoder().decode(VersionedHistoryRecord.Header.self, from: data)
            recordMajors.insert(header.semantics.major)
        }
        return try compatibilityMetadata(in: context).state(recordMajors: recordMajors)
    }

    func indexedCompatibilityState() throws -> DataCompatibilityStoreState {
        let majors = try versionedHistoryIndex().recordMajors
        return try operationCompatibilityMetadata().state(recordMajors: majors)
    }

    static func compatibilityMetadata(in context: ModelContext) throws -> CompatibilityMetadata {
        let requirements = try context.fetch(FetchDescriptor<SDDataCompatibilityRequirement>())
        var requiredMajor: UInt = 0
        for requirement in requirements {
            guard let value = requirement.requiredMajor, let major = UInt(exactly: value) else {
                throw DataCompatibilityError.incompleteRecord
            }
            requiredMajor = max(requiredMajor, major)
        }
        return try .init(
            persistedRequiredMajor: requirements.isEmpty ? nil : requiredMajor,
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
        try Self.persistCompatibilityFloor(major, in: mutationContext())
    }

    static func persistCompatibilityFloor(_ major: UInt, in context: ModelContext) throws {
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
        try indexedCompatibilityState().validate(policy: policy)
        let generation = try await dataGeneration().id
        return try versionedHistoryIndex().records(in: generation, policy: policy)
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
    }

    public func addVersionedHistoryRecord(_ record: VersionedHistoryRecord) async throws {
        try record.scope.validate()
        let policy = DataAccessPermit.current?.policy ?? VersionedLocationSample.storagePolicy
        try policy.validate(requiredMajor: record.semantics.major)
        let context = versionedMutationContext()
        guard record.dataGenerationID == mutationGenerationID() else {
            throw RecordingPersistenceError.dataGenerationChanged
        }
        let index = try versionedHistoryIndex()
        if let existing = try index.record(
            with: record.id,
            generationID: record.dataGenerationID,
            policy: policy,
        ) {
            guard existing == record else { throw DataCompatibilityError.conflictingRecord }
            return
        }
        let row = SDVersionedHistoryRecord()
        row.envelope = try JSONEncoder().encode(record)
        context.insert(row)
        index.didInsert(record)
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
