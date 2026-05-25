import Foundation
import SwiftData
import WhereCore

/// CloudKit-synced `WhereStore` backed by SwiftData. The `@Model` types are
/// kept `private`-ish (only the `@ModelActor`-isolated container sees them)
/// so callers never accidentally touch a SwiftData record outside the
/// actor's context.
///
/// Evidence blob bytes use `@Attribute(.externalStorage)` so CloudKit can
/// chunk them as `CKAsset`s.
@ModelActor
public actor SwiftDataStore: WhereStore, EvidenceBlobStore {
    public static func makeContainer(
        inMemory: Bool = false,
        useCloudKit: Bool = true,
    ) throws -> ModelContainer {
        let schema = Schema([
            SDLocationSample.self,
            SDEvidence.self,
            SDManualDay.self,
        ])
        let cloudKit: ModelConfiguration.CloudKitDatabase = useCloudKit ? .automatic : .none
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: cloudKit,
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    public func addSample(_ sample: LocationSample) async throws {
        let model = SDLocationSample(
            id: sample.id,
            timestamp: sample.timestamp,
            latitude: sample.coordinate.latitude,
            longitude: sample.coordinate.longitude,
            horizontalAccuracy: sample.horizontalAccuracy,
            sourceRaw: sample.source.rawValue,
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDLocationSample>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\.timestamp)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func allSamples() async throws -> [LocationSample] {
        var descriptor = FetchDescriptor<SDLocationSample>(sortBy: [SortDescriptor(\.timestamp)])
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func addEvidence(_ evidence: Evidence, blob: Data?) async throws {
        let id = evidence.id
        let existing = try modelContext.fetch(
            FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id }),
        )
        for record in existing {
            modelContext.delete(record)
        }
        let model = SDEvidence(
            id: evidence.id,
            kindRaw: evidence.kind.rawValue,
            capturedAt: evidence.capturedAt,
            note: evidence.note,
            regionRaw: evidence.region?.rawValue,
            blob: blob,
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDEvidence>(
            predicate: #Predicate { $0.capturedAt >= start && $0.capturedAt < end },
            sortBy: [SortDescriptor(\.capturedAt)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first?.blob
    }

    public func write(_ blob: Data, for id: UUID) async throws {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.blob = blob
        try modelContext.save()
    }

    public func read(for id: UUID) async throws -> Data? {
        try await evidenceBlob(for: id)
    }

    public func delete(for id: UUID) async throws {
        let descriptor = FetchDescriptor<SDEvidence>(predicate: #Predicate { $0.id == id })
        guard let record = try modelContext.fetch(descriptor).first else { return }
        record.blob = nil
        try modelContext.save()
    }

    public func setManualDay(_ day: DayPresence) async throws {
        let key = day.date
        let existing = try modelContext.fetch(
            FetchDescriptor<SDManualDay>(predicate: #Predicate { $0.dateKey == key }),
        )
        for record in existing {
            modelContext.delete(record)
        }
        let model = SDManualDay(
            dateKey: day.date,
            regionRaws: day.regions.map(\.rawValue).sorted(),
        )
        modelContext.insert(model)
        try modelContext.save()
    }

    public func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        let start = interval.start
        let end = interval.end
        var descriptor = FetchDescriptor<SDManualDay>(
            predicate: #Predicate { $0.dateKey >= start && $0.dateKey < end },
            sortBy: [SortDescriptor(\.dateKey)],
        )
        descriptor.includePendingChanges = true
        return try modelContext.fetch(descriptor).map { $0.toValue() }
    }

    public func clear(in interval: DateInterval) async throws {
        let start = interval.start
        let end = interval.end
        let samples = try modelContext.fetch(
            FetchDescriptor<SDLocationSample>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            ),
        )
        for record in samples {
            modelContext.delete(record)
        }
        let evidences = try modelContext.fetch(
            FetchDescriptor<SDEvidence>(
                predicate: #Predicate { $0.capturedAt >= start && $0.capturedAt < end },
            ),
        )
        for record in evidences {
            modelContext.delete(record)
        }
        let manuals = try modelContext.fetch(
            FetchDescriptor<SDManualDay>(
                predicate: #Predicate { $0.dateKey >= start && $0.dateKey < end },
            ),
        )
        for record in manuals {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}

// MARK: - SwiftData models (internal)

@Model
final class SDLocationSample {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var sourceRaw: String

    init(
        id: UUID,
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        sourceRaw: String,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.sourceRaw = sourceRaw
    }

    func toValue() -> LocationSample {
        LocationSample(
            id: id,
            timestamp: timestamp,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: horizontalAccuracy,
            source: SampleSource(rawValue: sourceRaw) ?? .manual,
        )
    }
}

@Model
final class SDEvidence {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var capturedAt: Date
    var note: String?
    var regionRaw: String?
    @Attribute(.externalStorage) var blob: Data?

    init(
        id: UUID,
        kindRaw: String,
        capturedAt: Date,
        note: String?,
        regionRaw: String?,
        blob: Data?,
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.capturedAt = capturedAt
        self.note = note
        self.regionRaw = regionRaw
        self.blob = blob
    }

    func toValue() -> Evidence {
        Evidence(
            id: id,
            kind: EvidenceKind(rawValue: kindRaw) ?? .other,
            capturedAt: capturedAt,
            region: regionRaw.flatMap { Region(rawValue: $0) },
            note: note,
        )
    }
}

@Model
final class SDManualDay {
    @Attribute(.unique) var dateKey: Date
    var regionRaws: [String]

    init(dateKey: Date, regionRaws: [String]) {
        self.dateKey = dateKey
        self.regionRaws = regionRaws
    }

    func toValue() -> DayPresence {
        DayPresence(
            date: dateKey,
            regions: Set(regionRaws.compactMap { Region(rawValue: $0) }),
        )
    }
}
