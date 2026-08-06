import Foundation
import RegionKit

/// Reads and writes the single CloudKit-synced planned-stay register.
public struct PlannedStayCoordinator: Sendable {
    private let store: any WhereStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(store: any WhereStore, calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    /// The active stay as of the injected clock. An expired value is replaced
    /// with a tombstone before returning so every device converges on “cleared.”
    public func active() async throws -> PlannedStay? {
        guard let record = try await latestRecord() else { return nil }
        guard let stay = record.value else { return nil }
        let today = CalendarDay(from: now(), in: calendar)
        guard stay.through < today else { return stay }
        return try await expireIfLatest(record, asOf: today)
    }

    /// Replace any prior intent with a stay through the inclusive day.
    public func set(region: Region, through: CalendarDay) async throws {
        try await write(value: PlannedStay(region: region, through: through))
    }

    /// Clear the active stay with a synced tombstone.
    public func clear() async throws {
        try await write(value: nil)
    }

    private func latestRecord() async throws -> PlannedStayRecord? {
        try await store.plannedStayRecords().max { lhs, rhs in
            PlannedStayRecord.newer(rhs, than: lhs)
        }
    }

    /// Clear `expiredRecord` only if it is still the winning revision. The
    /// transactional re-read prevents a stale `active()` read from erasing a
    /// newer stay saved while that read was suspended, and returns that newer
    /// stay so the caller cannot replace it with stale `nil` state.
    func expireIfLatest(
        _ expiredRecord: PlannedStayRecord,
        asOf today: CalendarDay,
    ) async throws -> PlannedStay? {
        try await store.perform {
            guard let latest = try await latestRecord() else { return nil }
            guard latest == expiredRecord else {
                guard let stay = latest.value, stay.through >= today else { return nil }
                return stay
            }
            guard let stay = expiredRecord.value, stay.through < today else { return nil }
            let tombstone = PlannedStayRecord(
                id: UUID(),
                value: nil,
                updatedAt: max(now(), expiredRecord.updatedAt.addingTimeInterval(0.001)),
            )
            try await store.replacePlannedStayRecord(with: tombstone)
            return nil
        }
    }

    private func write(value: PlannedStay?) async throws {
        let record = PlannedStayRecord(id: UUID(), value: value, updatedAt: now())
        try await store.perform {
            try await store.replacePlannedStayRecord(with: record)
        }
    }
}
