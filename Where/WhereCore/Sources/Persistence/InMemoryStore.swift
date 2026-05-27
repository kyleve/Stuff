import Foundation

/// In-memory `WhereStore` for tests and SwiftUI previews. Not persisted,
/// not synced; thread-safe by virtue of being an actor.
public actor InMemoryStore: WhereStore {
    private var samples: [LocationSample] = []
    private var evidences: [(evidence: Evidence, blob: Data?)] = []
    private var manualDayByDate: [Date: DayPresence] = [:]

    public init() {}

    public func perform<T: Sendable>(
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        // No save phase here — everything is in-memory and writes are
        // immediately visible. The block exists for protocol parity
        // with `SwiftDataStore`, where the save happens at this
        // boundary.
        try await block()
    }

    public func addSample(_ sample: LocationSample) async throws {
        samples.append(sample)
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        samples
            .filter { Self.halfOpen(interval, contains: $0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func allSamples() async throws -> [LocationSample] {
        samples.sorted { $0.timestamp < $1.timestamp }
    }

    public func write(evidence: Evidence, blob: Data?) async throws {
        // Treat `blob == nil` as "no change" so a metadata edit does not wipe
        // an existing attachment; mirrors `SwiftDataStore.write(evidence:blob:)`.
        let preserved = blob ?? evidences.first { $0.evidence.id == evidence.id }?.blob
        evidences.removeAll { $0.evidence.id == evidence.id }
        evidences.append((evidence, preserved))
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        evidences
            .filter { Self.halfOpen(interval, contains: $0.evidence.capturedAt) }
            .map(\.evidence)
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    public func evidenceBlob(for id: UUID) async throws -> Data? {
        evidences.first { $0.evidence.id == id }?.blob
    }

    public func setManualDay(_ day: DayPresence) async throws {
        manualDayByDate[day.date] = day
    }

    public func manualDays(in interval: DateInterval) async throws -> [DayPresence] {
        manualDayByDate.values
            .filter { Self.halfOpen(interval, contains: $0.date) }
            .sorted { $0.date < $1.date }
    }

    public func clear(in interval: DateInterval) async throws {
        samples.removeAll { Self.halfOpen(interval, contains: $0.timestamp) }
        evidences.removeAll { Self.halfOpen(interval, contains: $0.evidence.capturedAt) }
        for date in manualDayByDate.keys where Self.halfOpen(interval, contains: date) {
            manualDayByDate.removeValue(forKey: date)
        }
    }

    /// Half-open `[start, end)` containment, matching `SwiftDataStore`'s
    /// predicate semantics (and what `DayAggregator.yearInterval` produces).
    /// `DateInterval.contains(_:)` is closed on both ends, which would
    /// double-count the first instant of the next year when callers query a
    /// year interval.
    private static func halfOpen(_ interval: DateInterval, contains date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}
