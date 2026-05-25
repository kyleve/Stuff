import Foundation
import WhereCore

/// In-memory `WhereStore` for tests and SwiftUI previews. Not persisted,
/// not synced; thread-safe by virtue of being an actor.
public actor InMemoryStore: WhereStore {
    private var samples: [LocationSample] = []
    private var evidences: [(evidence: Evidence, blob: Data?)] = []
    private var manualDayByDate: [Date: DayPresence] = [:]

    public init() {}

    public func addSample(_ sample: LocationSample) async throws {
        samples.append(sample)
    }

    public func samples(in interval: DateInterval) async throws -> [LocationSample] {
        samples
            .filter { interval.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func allSamples() async throws -> [LocationSample] {
        samples.sorted { $0.timestamp < $1.timestamp }
    }

    public func addEvidence(_ evidence: Evidence, blob: Data?) async throws {
        // Treat `blob == nil` as "no change" so a metadata edit does not wipe
        // an existing attachment; mirrors `SwiftDataStore.addEvidence`.
        let preserved = blob ?? evidences.first { $0.evidence.id == evidence.id }?.blob
        evidences.removeAll { $0.evidence.id == evidence.id }
        evidences.append((evidence, preserved))
    }

    public func evidence(in interval: DateInterval) async throws -> [Evidence] {
        evidences
            .filter { interval.contains($0.evidence.capturedAt) }
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
            .filter { interval.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    public func clear(in interval: DateInterval) async throws {
        samples.removeAll { interval.contains($0.timestamp) }
        evidences.removeAll { interval.contains($0.evidence.capturedAt) }
        for date in manualDayByDate.keys where interval.contains(date) {
            manualDayByDate.removeValue(forKey: date)
        }
    }
}
