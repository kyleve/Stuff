import Foundation
import SwiftData

extension SwiftDataStore {
    func versionedSamples(generationID: WhereDataGenerationID) throws -> [LocationSample] {
        try admittingCompatibility {
            var samples: [LocationSample] = []
            let index = try versionedHistoryIndex()
            if let permit = DataAccessPermit.current {
                try permit.validate()
                for major in index.recordMajors {
                    try permit.policy.validate(requiredMajor: major)
                    guard major <= permit.requiredMajor else {
                        throw DataCompatibilityError.verificationRequired
                    }
                }
            }
            for record in try index.records(
                in: generationID,
                policy: VersionedLocationSample.storagePolicy,
            ) {
                guard record.dataGenerationID == generationID,
                      record.kind == VersionedLocationSample.kind else { continue }
                try samples.append(VersionedLocationSample.decode(record))
            }
            return samples
        }
    }

    /// The observation UUID identifies immutable raw evidence across both storage contracts.
    /// Identical deliveries coalesce; differing provenance must not depend on arrival order.
    static func mergeSampleDeliveries(_ samples: [LocationSample]) throws -> [LocationSample] {
        var unique: [UUID: LocationSample] = [:]
        for sample in samples {
            if let old = unique[sample.id], old != sample {
                throw RecordingPersistenceError.conflictingImmutableRecord(id: sample.id)
            }
            unique[sample.id] = sample
        }
        return unique.values.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func deleteVersionedSamples(
        in context: ModelContext,
        generationID: WhereDataGenerationID,
        interval: DateInterval,
    ) throws -> Set<UUID> {
        var matched: [SDVersionedHistoryRecord] = []
        var sampleIDs: Set<UUID> = []
        for row in try context.fetch(FetchDescriptor<SDVersionedHistoryRecord>()) {
            guard let data = row.envelope else { throw DataCompatibilityError.incompleteRecord }
            let record = try VersionedHistoryRecord.admit(
                data,
                policy: VersionedLocationSample.storagePolicy,
            )
            guard record.dataGenerationID == generationID,
                  record.kind == VersionedLocationSample.kind else { continue }
            let sample = try VersionedLocationSample.decode(record)
            if sample.timestamp >= interval.start, sample.timestamp < interval.end {
                matched.append(row)
                sampleIDs.insert(sample.id)
            }
        }
        guard !matched.isEmpty else { return [] }
        try persistCompatibilityFloor(0, in: context)
        for row in matched {
            context.delete(row)
        }
        return sampleIDs
    }
}
