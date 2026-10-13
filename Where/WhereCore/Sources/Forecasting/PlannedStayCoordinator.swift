import Foundation
import RegionKit

/// Persists independent travel plans and the home region used for unplanned days.
/// Each plan and the home choice resolve synced revisions through their own register.
public struct PlannedStayCoordinator: Sendable {
    public enum PlanningError: Error, Equatable, LocalizedError {
        case stayNotFound
        case stayAlreadyExists

        public var errorDescription: String? {
            switch self {
                case .stayNotFound:
                    String(localized: .planningErrorStayNotFound)
                case .stayAlreadyExists:
                    String(localized: .planningErrorStayAlreadyExists)
            }
        }
    }

    private let store: any WhereStore
    private let now: @Sendable () -> Date

    init(store: any WhereStore, now: @escaping @Sendable () -> Date) {
        self.store = store
        self.now = now
    }

    /// Read completed and upcoming plans with the home choice from one store snapshot.
    /// Reading never expires intent or changes recorded history.
    public func snapshot() async throws -> PlanningSnapshot {
        try await store.readSnapshot {
            let records = try await store.plannedStayRecords()
            let home = try await latestHomeRecord()
            let winners = Dictionary(grouping: records, by: \.stayID).values.compactMap {
                $0.max { PlannedStayRecord.newer($1, than: $0) }
            }
            let stays = winners.compactMap(\.value).sorted { lhs, rhs in
                if lhs.arrival.earliest != rhs.arrival.earliest {
                    return lhs.arrival.earliest < rhs.arrival.earliest
                }
                return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
            return PlanningSnapshot(stays: stays, homeRegion: home?.region)
        }
    }

    /// Persist a new draft with its stable identity. An identical retry is a no-op.
    public func create(_ stay: PlannedStay) async throws {
        try stay.validate()
        try await store.performInCurrentGeneration {
            if let latest = try await latestRecord(stayID: stay.id) {
                guard latest.value == stay else { throw PlanningError.stayAlreadyExists }
                return
            }
            try await write(stayID: stay.id, value: stay)
        }
    }

    /// An edit cannot recreate a plan deleted on another device while its editor was open.
    public func update(_ stay: PlannedStay) async throws {
        try stay.validate()
        try await store.performInCurrentGeneration {
            guard try await latestRecord(stayID: stay.id)?.value != nil else {
                throw PlanningError.stayNotFound
            }
            try await write(stayID: stay.id, value: stay)
        }
    }

    /// Keep a tombstone for this identity so delayed revisions cannot restore the deleted plan.
    public func delete(stayID: PlannedStay.ID) async throws {
        try await store.performInCurrentGeneration {
            try await write(stayID: stayID, value: nil)
        }
    }

    /// A nil home choice selects historical estimates for unplanned days.
    public func setHomeRegion(_ region: Region?) async throws {
        try await store.performInCurrentGeneration {
            let latest = try await latestHomeRecord()
            let record = try HomeRegionRecord(
                id: UUID(),
                region: region,
                updatedAt: nextTimestamp(after: latest?.updatedAt),
            )
            try await store.replaceHomeRegionRecord(with: record)
        }
    }

    private func latestRecord(stayID: PlannedStay.ID) async throws -> PlannedStayRecord? {
        try await store.plannedStayRecords().filter { $0.stayID == stayID }.max {
            PlannedStayRecord.newer($1, than: $0)
        }
    }

    private func latestHomeRecord() async throws -> HomeRegionRecord? {
        try await store.homeRegionRecords().max { HomeRegionRecord.newer($1, than: $0) }
    }

    private func write(stayID: PlannedStay.ID, value: PlannedStay?) async throws {
        let latest = try await latestRecord(stayID: stayID)
        let record = try PlannedStayRecord(
            id: UUID(),
            stayID: stayID,
            value: value,
            updatedAt: nextTimestamp(after: latest?.updatedAt),
        )
        try await store.replacePlannedStayRecord(with: record)
    }

    private func nextTimestamp(after previous: Date?) -> Date {
        let current = now()
        return previous.map { max(current, $0.addingTimeInterval(0.001)) } ?? current
    }
}
