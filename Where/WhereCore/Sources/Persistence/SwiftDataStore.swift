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
/// ## Context strategy: main is read-only, writes use a per-`perform` peer
///
/// The actor's auto-generated `modelContext` (the "main" context) is
/// treated as **read-only**: every reader (`samples(in:)`,
/// `evidence(in:)`, ...) called outside a `perform { ... }` block
/// observes it, and any future SwiftUI `@Query` wired to the store
/// would observe it too.
///
/// Every outermost `perform` call spins up a fresh peer
/// `ModelContext(modelContainer)` and stashes it in `writerContext`
/// for the duration of the block. Mutating methods (`add(sample:)`,
/// `write(evidence:blob:)`, `setManualDay`, `clear(in:)`, and the
/// `EvidenceBlobStore` writers) trap if called outside a `perform`
/// body, and otherwise read/write through that peer. Reads issued
/// *inside* a `perform` also use the peer, so writes-within-the
/// transaction are visible to subsequent reads in the same block.
///
/// On outermost success the peer is `save()`d — that flushes the
/// batched writes to the persistent store, and the main context
/// picks the changes up on its next fetch. On outermost throw the
/// peer is discarded without saving, so a partial transaction
/// cleanly rolls back. Nested `perform` calls reuse the in-flight
/// peer so they coalesce into a single transaction.
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

        /// Build- and test-aware default suitable for app-level wiring.
        ///
        /// - When tests are running (detected via the
        ///   `XCTestConfigurationFilePath` env var, which both XCTest
        ///   and Swift Testing under `xcodebuild` / `swift test` set),
        ///   returns `.inMemory` so tests can't accidentally write
        ///   into the user's local on-disk store.
        /// - In debug app builds, returns `.localOnly` so iteration is
        ///   fast and CloudKit doesn't sync experimental records.
        /// - In release builds, returns `.cloudKit` for production
        ///   sync.
        ///
        /// Tests that want a specific mode (or that construct stores
        /// outside `WhereController`) should still pass `.inMemory`
        /// explicitly via `SwiftDataStore.inMemory()`.
        public static var `default`: Storage {
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                return .inMemory
            }
            #if DEBUG
                return .localOnly
            #else
                return .cloudKit
            #endif
        }
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

    /// App-wiring factory: builds a store for the given storage mode
    /// (defaulting to the build/test-aware `Storage.default`) and wraps
    /// it in a `SwiftDataStore`. The `@ModelActor`-generated
    /// `init(modelContainer:)` is not reachable from other modules, so
    /// this is the supported entry point for production wiring in the
    /// app/UI layer.
    public static func make(storage: Storage = .default) throws -> SwiftDataStore {
        let container = try makeContainer(storage: storage)
        return SwiftDataStore(modelContainer: container)
    }

    private static let logger = Logger(subsystem: "com.stuff.where", category: "SwiftDataStore")

    /// Peer `ModelContext` active for the duration of an outermost
    /// `perform { ... }` block. `nil` outside `perform`. See the
    /// type doc for the full context-strategy explanation.
    private var writerContext: ModelContext?

    public func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        // Nested call: a write transaction is already in flight on
        // this actor. Reuse its peer so nested writes coalesce into
        // the same save / discard decision; only the outermost
        // perform decides commit vs. rollback.
        if writerContext != nil {
            return try await block()
        }
        let peer = ModelContext(modelContainer)
        writerContext = peer
        do {
            let result = try await block()
            // Outermost success: save the peer, which propagates the
            // batched writes to the persistent store. The main
            // `modelContext` picks the changes up on its next fetch.
            try peer.save()
            writerContext = nil
            return result
        } catch {
            // Outermost throw: drop the peer. Without a save() call
            // its pending changes never reach the persistent store —
            // clean rollback of the entire transaction.
            writerContext = nil
            throw error
        }
    }

    /// The context mutating methods write to. Mutations are
    /// contract-required to run inside `perform { ... }`; calling
    /// them outside is a programmer error and traps so the broken
    /// contract surfaces immediately instead of silently no-op'ing
    /// the save.
    private func mutationContext() -> ModelContext {
        guard let writerContext else {
            preconditionFailure(
                "SwiftDataStore mutations must be called inside store.perform { ... }",
            )
        }
        return writerContext
    }

    /// The context read methods fetch from. Inside `perform`, reads
    /// use the in-flight peer so writes-within-the-transaction are
    /// visible to subsequent reads in the same block. Outside, reads
    /// observe the main `modelContext` (committed state only).
    private func readContext() -> ModelContext {
        writerContext ?? modelContext
    }

    public func add(sample: LocationSample) async throws {
        let context = mutationContext()
        let id = sample.id
        if let existing = try context.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate { $0.id == id }),
        ).first {
            existing.update(from: sample)
        } else {
            context.insert(SDLocationSample(value: sample))
        }
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        let context = readContext()
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
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func allSamples() async throws -> [LocationSample] {
        let context = readContext()
        var descriptor = FetchDescriptor<SDLocationSample>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func write(evidence: Evidence, blob: Data?) async throws {
        let context = mutationContext()
        let id = evidence.id
        if let existing = try context.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id }),
        ).first {
            // Treat `blob == nil` as "no change" so a metadata-only edit
            // (note, kind, region) does not wipe a previously stored
            // attachment. Callers that need to remove the blob explicitly
            // use `delete(for:)` from the `EvidenceBlobStore` API.
            existing.update(from: evidence, blob: blob ?? existing.blob)
        } else {
            context.insert(SDEvidence(value: evidence, blob: blob))
        }
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        let context = readContext()
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
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func allEvidence() async throws -> [Evidence] {
        let context = readContext()
        var descriptor = FetchDescriptor<SDEvidence>(sortBy: [SortDescriptor(\.capturedAt)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        let context = readContext()
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first?.blob
    }

    public func write(blob: Data, for id: UUID) async throws {
        let context = mutationContext()
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.blob = blob
    }

    public func read(for id: UUID) async throws -> Data? {
        try await evidenceBlob(for: id)
    }

    public func delete(for id: UUID) async throws {
        let context = mutationContext()
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.blob = nil
    }

    public func setManualDay(_ day: DayPresence) async throws {
        let context = mutationContext()
        let key = day.date
        if let existing = try context.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate { $0.dateKey == key }),
        ).first {
            existing.update(from: day)
        } else {
            context.insert(SDManualDay(value: day))
        }
    }

    public func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        let context = readContext()
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
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func allManualDays() async throws -> [DayPresence] {
        let context = readContext()
        var descriptor = FetchDescriptor<SDManualDay>(sortBy: [SortDescriptor(\.dateKey)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { record in
            let value = record.toValue()
            if value == nil { Self.logFault(forCorrupt: record) }
            return value
        }
    }

    public func clear(in interval: DateInterval) async throws {
        let context = mutationContext()
        let start = interval.start
        let end = interval.end
        let samples = try context.fetch(
            FetchDescriptor<SDLocationSample>(predicate: #Predicate {
                if let timestamp = $0.timestamp {
                    timestamp >= start && timestamp < end
                } else {
                    false
                }
            }),
        )
        for record in samples {
            context.delete(record)
        }
        let evidences = try context.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate {
                if let capturedAt = $0.capturedAt {
                    capturedAt >= start && capturedAt < end
                } else {
                    false
                }
            }),
        )
        for record in evidences {
            context.delete(record)
        }
        let manuals = try context.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate {
                if let dateKey = $0.dateKey {
                    dateKey >= start && dateKey < end
                } else {
                    false
                }
            }),
        )
        for record in manuals {
            context.delete(record)
        }
    }

    public func clearAll() async throws {
        let context = mutationContext()
        for sample in try context.fetch(FetchDescriptor<SDLocationSample>()) {
            context.delete(sample)
        }
        for evidence in try context.fetch(FetchDescriptor<SDEvidence>()) {
            context.delete(evidence)
        }
        for manual in try context.fetch(FetchDescriptor<SDManualDay>()) {
            context.delete(manual)
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
    /// `EvidenceContentType.discriminator` ("pdf", "image", "other", ...).
    /// Optional only because all SwiftData fields must be optional
    /// for CloudKit; the value-level `Evidence.contentType` is
    /// required, and `toValue()` falls back to `.other(nil)` for
    /// missing/unknown discriminators so legacy rows stay readable.
    var contentTypeDiscriminator: String?
    /// User-supplied label for `EvidenceContentType.other`. Nil for
    /// every other content type.
    var contentTypeOtherLabel: String?
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
        contentTypeDiscriminator = value.contentType.discriminator
        contentTypeOtherLabel = if case let .other(label) = value.contentType { label } else { nil }
        self.blob = blob
    }

    func toValue() -> Evidence? {
        guard let id, let kindRaw, let capturedAt else { return nil }
        let kind = EvidenceKind.fromDiscriminator(kindRaw, otherLabel: otherLabel) ?? .other(nil)
        let contentType = contentTypeDiscriminator
            .flatMap { EvidenceContentType.fromDiscriminator($0, otherLabel: contentTypeOtherLabel)
            }
            ?? .other(nil)
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
