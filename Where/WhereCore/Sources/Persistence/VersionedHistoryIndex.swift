import Foundation

/// An actor-owned index for one pinned store operation. Headers are read before any envelope
/// body, and each body is decoded at most once. It must never outlive its transaction or snapshot.
final class VersionedHistoryIndex {
    private struct Key: Hashable {
        let generationID: WhereDataGenerationID
        let recordID: VersionedHistoryRecord.ID
    }

    private enum Delivery {
        case record(VersionedHistoryRecord)
        case conflict

        func value() throws -> VersionedHistoryRecord {
            switch self {
                case let .record(record): record
                case .conflict: throw DataCompatibilityError.conflictingRecord
            }
        }
    }

    private final class Decoded {
        var records: [Key: Delivery]
        init(records: [Key: Delivery]) {
            self.records = records
        }
    }

    private enum Storage {
        case encoded([Data])
        case decoded(Decoded)
    }

    private var storage: Storage
    private(set) var recordMajors: Set<UInt>

    init(envelopes: [Data]) throws {
        storage = .encoded(envelopes)
        recordMajors = try Set(envelopes.map {
            try JSONDecoder().decode(VersionedHistoryRecord.Header.self, from: $0).semantics.major
        })
    }

    func records(
        in generationID: WhereDataGenerationID,
        policy: DataCompatibilityPolicy,
    ) throws -> [VersionedHistoryRecord] {
        // Delayed conflicts in erased generations stay inert. Their major headers still protect
        // the account, but their identities cannot poison the current generation's history.
        try prepare(policy: policy).records.filter { $0.key.generationID == generationID }
            .map { try $0.value.value() }
    }

    func record(
        with recordID: VersionedHistoryRecord.ID,
        generationID: WhereDataGenerationID,
        policy: DataCompatibilityPolicy,
    ) throws -> VersionedHistoryRecord? {
        try prepare(policy: policy).records[Key(generationID: generationID, recordID: recordID)]?
            .value()
    }

    /// Called only after the store has staged the corresponding immutable envelope.
    func didInsert(_ record: VersionedHistoryRecord) {
        guard case let .decoded(decoded) = storage else {
            preconditionFailure("Admission and collision checks must precede insertion.")
        }
        decoded
            .records[Key(generationID: record.dataGenerationID, recordID: record.id)] =
            .record(record)
        recordMajors.insert(record.semantics.major)
    }

    private func prepare(policy: DataCompatibilityPolicy) throws -> Decoded {
        for major in recordMajors.sorted() {
            try policy.validate(requiredMajor: major)
        }
        let envelopes: [Data]
        switch storage {
            case let .decoded(decoded): return decoded
            case let .encoded(pending): envelopes = pending
        }
        var values: [Key: Delivery] = [:]
        for envelope in envelopes {
            // Every header above has already passed admission. The payload remains opaque here.
            let record = try JSONDecoder().decode(VersionedHistoryRecord.self, from: envelope)
            try record.scope.validate()
            let key = Key(generationID: record.dataGenerationID, recordID: record.id)
            if let previous = values[key] {
                switch previous {
                    case let .record(old) where old == record: break
                    case .record, .conflict: values[key] = .conflict
                }
            } else {
                values[key] = .record(record)
            }
        }
        let decoded = Decoded(records: values)
        storage = .decoded(decoded)
        return decoded
    }
}
