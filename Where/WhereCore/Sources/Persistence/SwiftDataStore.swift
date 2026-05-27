import Foundation
import os
import SwiftData

/// CloudKit-synced `WhereStore` backed by SwiftData. The `@Model` types are
/// kept `private`-ish (only the `@ModelActor`-isolated container sees them)
/// so callers never accidentally touch a SwiftData record outside the
/// actor's context.
///
/// Evidence blob bytes use `@Attribute(.externalStorage)` so CloudKit can
/// chunk them as `CKAsset`s.
///
/// Every `@Model` field is `Optional` with no placeholder default. SwiftData's
/// CloudKit mirror requires nullable or defaulted properties, and we picked
/// nullable so "field absent" is distinguishable from "field is a sentinel
/// value". `toValue()` is therefore allowed to return `nil` when a record is
/// missing mandatory state; readers `compactMap` and log a fault rather than
/// crashing on partial data.
///
/// Persistence saves happen at the `perform { ... }` boundary, not after each
/// mutation. Mutating methods stage changes in `modelContext`; the outermost
/// `perform` flushes them via `modelContext.save()`.
@ModelActor
public actor SwiftDataStore: WhereStore, EvidenceBlobStore {
    /// Backing storage for a `SwiftDataStore`. CloudKit mode is the
    /// production default; the other two are for tests and local
    /// development.
    public enum Storage: Sendable {
        /// In-memory only. No disk, no CloudKit. Test/preview default.
        case inMemory
        /// On-disk SwiftData store with CloudKit sync disabled.
        case localOnly
        /// On-disk SwiftData store backed by the user's private
        /// CloudKit database. Production default.
        case cloudKit
    }

    public static func makeContainer(storage: Storage) throws -> ModelContainer {
        let schema = Schema([
            SDLocationSample.self,
            SDEvidence.self,
            SDManualDay.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storage == .inMemory,
            cloudKitDatabase: storage == .cloudKit ? .automatic : .none,
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Convenience for tests and SwiftUI previews: builds an
    /// `.inMemory` container and wraps it in a `SwiftDataStore`. Each
    /// call returns an independent store with its own backing
    /// container, so callers get a clean slate per use without any
    /// shared state to reset.
    public static func inMemory() throws -> SwiftDataStore {
        let container = try makeContainer(storage: .inMemory)
        return SwiftDataStore(modelContainer: container)
    }

    private static let logger = Logger(subsystem: "com.stuff.where", category: "SwiftDataStore")

    /// `perform { ... }` re-entry counter. The outermost block (depth == 1
    /// at exit) is the one that calls `modelContext.save()`; nested blocks
    /// just run and let the outer save flush their staged changes.
    private var performDepth = 0

    public func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        performDepth += 1
        let result: T
        do {
            result = try await block()
        } catch {
            performDepth -= 1
            throw error
        }
        let wasOutermost = performDepth == 1
        performDepth -= 1
        if wasOutermost {
            try modelContext.save()
        }
        return result
    }

    public func addSample(_ sample: LocationSample) async throws {
        let id = sample.id
        if let existing = try modelContext.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate { $0.id == id }),
        ).first {
            existing.update(from: sample)
        } else {
            modelContext.insert(SDLocationSample(value: sample))
        }
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDLocationSample>(
            predicate: #Predicate {
                if let timestamp = $0.timestamp {
                    timestamp >= start && timestamp < end
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.timestamp)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func allSamples() async throws -> [LocationSample] {
        var descriptor = FetchDescriptor<SDLocationSample>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func write(evidence: Evidence, blob: Data?) async throws {
        let id = evidence.id
        if let existing = try modelContext.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id }),
        ).first {
            // Treat `blob == nil` as "no change" so a metadata-only edit
            // (note, kind, region) does not wipe a previously stored
            // attachment. Callers that need to remove the blob explicitly
            // use `delete(for:)` from the `EvidenceBlobStore` API.
            existing.update(from: evidence, blob: blob ?? existing.blob)
        } else {
            modelContext.insert(SDEvidence(value: evidence, blob: blob))
        }
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDEvidence>(
            predicate: #Predicate {
                if let capturedAt = $0.capturedAt {
                    capturedAt >= start && capturedAt < end
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.capturedAt)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.blob
    }

    public func write(blob: Data, for id: UUID) async throws {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.blob = blob
    }

    public func read(for id: UUID) async throws -> Data? {
        try await evidenceBlob(for: id)
    }

    public func delete(for id: UUID) async throws {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.blob = nil
    }

    public func setManualDay(_ day: DayPresence) async throws {
        let key = day.date
        if let existing = try modelContext.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate { $0.dateKey == key }),
        ).first {
            existing.update(from: day)
        } else {
            modelContext.insert(SDManualDay(value: day))
        }
    }

    public func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDManualDay>(
            predicate: #Predicate {
                if let dateKey = $0.dateKey {
                    dateKey >= start && dateKey < end
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.dateKey)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func clear(in interval: DateInterval) async throws {
        let start = interval.start
        let end = interval.end
        let samples = try modelContext.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate {
                if let timestamp = $0.timestamp {
                    timestamp >= start && timestamp < end
                } else {
                    false
                }
            }),
        )
        for record in samples {
            modelContext.delete(record)
        }
        let evidences = try modelContext.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate {
                if let capturedAt = $0.capturedAt {
                    capturedAt >= start && capturedAt < end
                } else {
                    false
                }
            }),
        )
        for record in evidences {
            modelContext.delete(record)
        }
        let manuals = try modelContext.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate {
                if let dateKey = $0.dateKey {
                    dateKey >= start && dateKey < end
                } else {
                    false
                }
            }),
        )
        for record in manuals {
            modelContext.delete(record)
        }
    }

    private static func logFault<Record>(forCorrupt _: Record) {
        logger.fault(
            "Dropped corrupt SwiftData record of type \(String(describing: Record.self), privacy: .public)",
        )
    }
}

// MARK: - SwiftData models (internal)

@Model
final class SDLocationSample {
    var id: UUID?
    var timestamp: Date?
    var latitude: Double?
    var longitude: Double?
    var horizontalAccuracy: Double?
    /// Discriminator string from `SampleSource.discriminator`.
    var sourceRaw: String?
    /// Populated only when `sourceRaw == "evidenceImplied"`.
    var evidenceId: UUID?
    /// Populated only when `sourceRaw == "evidenceImplied"`. Stores the
    /// `EvidenceKind.discriminator` of the originating evidence; the
    /// `.other` label is not preserved here (fetch the `Evidence` row
    /// for that).
    var evidenceKindRaw: String?

    init() {}

    convenience init(value: LocationSample) {
        self.init()
        update(from: value)
    }

    func update(from value: LocationSample) {
        id = value.id
        timestamp = value.timestamp
        latitude = value.coordinate.latitude
        longitude = value.coordinate.longitude
        horizontalAccuracy = value.horizontalAccuracy
        sourceRaw = value.source.discriminator
        evidenceId = value.source.evidenceId
        evidenceKindRaw = value.source.evidenceKind?.discriminator
    }

    func toValue() -> LocationSample? {
        guard let id, let timestamp, let latitude, let longitude else { return nil }
        let source = SampleSource.fromDiscriminator(
            sourceRaw ?? SampleSource.manual.discriminator,
            evidenceId: evidenceId,
            evidenceKindRaw: evidenceKindRaw,
        ) ?? .manual
        return LocationSample(
            id: id,
            timestamp: timestamp,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: horizontalAccuracy ?? 0,
            source: source,
        )
    }
}

@Model
final class SDEvidence {
    var id: UUID?
    /// `EvidenceKind.discriminator` ("planeTicket", "other", etc.).
    var kindRaw: String?
    /// User-supplied label for the `.other` catch-all. Nil for every
    /// other kind.
    var otherLabel: String?
    var capturedAt: Date?
    var note: String?
    var regionRaw: String?
    /// `EvidenceContentType.rawValue` if the attached blob's media type
    /// has been classified. Optional because old rows pre-date the
    /// schema and unclassified rows are still readable.
    var contentTypeRaw: String?
    @Attribute(.externalStorage) var blob: Data?

    init() {}

    convenience init(value: Evidence, blob: Data?) {
        self.init()
        update(from: value, blob: blob)
    }

    func update(from value: Evidence, blob: Data?) {
        id = value.id
        kindRaw = value.kind.discriminator
        otherLabel = if case let .other(label) = value.kind { label } else { nil }
        capturedAt = value.capturedAt
        note = value.note
        regionRaw = value.region?.rawValue
        contentTypeRaw = value.contentType?.rawValue
        self.blob = blob
    }

    func toValue() -> Evidence? {
        guard let id, let kindRaw, let capturedAt else { return nil }
        let kind = EvidenceKind.fromDiscriminator(kindRaw, otherLabel: otherLabel) ?? .other(nil)
        let contentType = contentTypeRaw.flatMap { EvidenceContentType(rawValue: $0) }
        return Evidence(
            id: id,
            kind: kind,
            capturedAt: capturedAt,
            region: regionRaw.flatMap { Region(rawValue: $0) },
            note: note,
            contentType: contentType,
        )
    }
}

@Model
final class SDManualDay {
    var dateKey: Date?
    var regionRaws: [String]?

    init() {}

    convenience init(value: DayPresence) {
        self.init()
        update(from: value)
    }

    func update(from value: DayPresence) {
        dateKey = value.date
        regionRaws = value.regions.map(\.rawValue).sorted()
    }

    func toValue() -> DayPresence? {
        guard let dateKey else { return nil }
        return DayPresence(
            date: dateKey,
            regions: Set((regionRaws ?? []).compactMap { Region(rawValue: $0) }),
        )
    }
}
