import Observation
import RegionKit
import WhereCore

/// Holds the Location cards at the counts and order the user last saw until
/// their visible surface can release one coordinated reconciliation.
@MainActor
@Observable
final class LocationCardsPresentationModel {
    /// A live reversal between the same two headline regions.
    struct OvertakeEvent: Equatable {
        let sequence: Int
        let winner: Region
        let passedRegion: Region
        let motion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion
    }

    /// The measured rank-layout endpoints for one released overtake.
    struct OvertakeMovement: Equatable {
        enum Phase: Equatable {
            case pending
            case released(WhereStylesheet.LocationCardStackStyle.OvertakeMotion)
        }

        let sequence: Int
        let fromOrder: [Region]
        let toOrder: [Region]
        let phase: Phase

        var releasedMotion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion? {
            switch phase {
                case .pending:
                    nil
                case let .released(motion):
                    motion
            }
        }
    }

    /// Everything that decides whether SwiftUI should restart the card-surface
    /// reconciliation task.
    struct ReconciliationID: Hashable {
        let counts: [RegionDays]
        let year: Int
        let isVisible: Bool
    }

    private let preferences: WherePreferences
    private var lastSeenCounts: [Region: Int]?
    private var displayedCounts: [Region: Int]
    private var displayedOrder: [Region] = []
    private var isRankingSurfaceVisible = false
    private var reconciliationTarget: ReconciliationID?

    private(set) var year: Int
    private(set) var feedbackTrigger = 0
    private(set) var latestOvertake: OvertakeEvent?
    private(set) var overtakeMovement: OvertakeMovement?
    private(set) var overtakeTrigger = 0

    init(preferences: WherePreferences, year: Int) {
        self.preferences = preferences
        self.year = year
        let savedCounts = preferences.lastSeenLocationDayCounts(in: year)
        lastSeenCounts = savedCounts
        displayedCounts = savedCounts ?? [:]
    }

    /// Load another year's count baseline without marking its current report as
    /// seen. Its ranking begins quiet and is synchronized by the visible surface.
    func prepare(for year: Int) {
        guard year != self.year else { return }
        self.year = year
        let savedCounts = preferences.lastSeenLocationDayCounts(in: year)
        lastSeenCounts = savedCounts
        displayedCounts = savedCounts ?? [:]
        displayedOrder = []
        isRankingSurfaceVisible = false
        latestOvertake = nil
        overtakeMovement = nil
    }

    /// Registers the latest surface state before its keyed task waits. Becoming
    /// visible synchronizes order quietly; reports arriving during one visible
    /// session remain pending until reconciliation.
    func updateReconciliationTarget(_ target: ReconciliationID) {
        let wasVisible = isRankingSurfaceVisible
        let yearChanged = target.year != year
        prepare(for: target.year)
        reconciliationTarget = target

        guard target.isVisible else {
            isRankingSurfaceVisible = false
            overtakeMovement = nil
            return
        }

        isRankingSurfaceVisible = true
        if yearChanged || !wasVisible {
            displayedOrder = target.counts.map(\.region)
            overtakeMovement = nil
            for item in target.counts where displayedCounts[item.region] == nil {
                displayedCounts[item.region] = item.days
            }
            return
        }

        // Keep an in-flight movement intact. `reconciliationTarget` already
        // retains only this latest report; finishing the movement stages it
        // from the exact visual endpoint.
        guard overtakeMovement?.releasedMotion == nil else { return }
        stagePendingMovement(for: target)
    }

    /// Cards rendered before reconciliation retain the prior membership, count,
    /// and order. Initial and newly visible sessions use the current membership.
    func presented(_ current: [RegionDays]) -> [RegionDays] {
        let currentOrder = current.map(\.region)
        let order = displayedOrder.isEmpty ? currentOrder : displayedOrder
        let currentByRegion = Dictionary(uniqueKeysWithValues: current.map { ($0.region, $0) })

        return order.compactMap { region in
            guard let days = displayedCounts[region] ?? currentByRegion[region]?.days else {
                return nil
            }
            return RegionDays(
                region: region,
                days: days,
            )
        }
    }

    /// Whether releasing `target` now will be a live two-card reversal.
    func willOvertake(_ target: ReconciliationID) -> Bool {
        guard target == reconciliationTarget,
              target.isVisible,
              isRankingSurfaceVisible,
              target.year == year
        else { return false }
        let currentOrder = target.counts.map(\.region)
        return overtakeMovement?.fromOrder == displayedOrder
            && overtakeMovement?.toOrder == currentOrder
            && overtakeMovement?.phase == .pending
            && isReversal(from: displayedOrder, to: currentOrder)
    }

    /// Advances counts and order to the report, persists the presentation, and
    /// emits one feedback trigger for an increased count or live overtake.
    @discardableResult
    func reconcile(
        _ target: ReconciliationID,
        overtakeMotion: WhereStylesheet.LocationCardStackStyle.OvertakeMotion,
    ) -> OvertakeEvent? {
        guard target == reconciliationTarget,
              target.isVisible,
              isRankingSurfaceVisible,
              target.year == year
        else { return nil }
        // A newer report can finish its 500 ms gate while the prior overtake
        // is still moving. It must wait at the model boundary too, so an early
        // caller cannot clear the active frames.
        guard overtakeMovement?.releasedMotion == nil else { return nil }
        let current = target.counts
        let isOvertake = willOvertake(target)

        let currentCounts = Dictionary(uniqueKeysWithValues: current.map { item in
            (item.region, item.days)
        })
        let shouldProvideCountFeedback = current.contains { item in
            guard let previousDays = lastSeenCounts?[item.region] else { return false }
            return previousDays < item.days
        }

        let event: OvertakeEvent?
        if isOvertake,
           let movement = overtakeMovement,
           let winner = current.first?.region,
           let passedRegion = displayedOrder.first
        {
            let overtake = OvertakeEvent(
                sequence: movement.sequence,
                winner: winner,
                passedRegion: passedRegion,
                motion: overtakeMotion,
            )
            event = overtake
            latestOvertake = overtake
            overtakeTrigger = overtake.sequence
            overtakeMovement = OvertakeMovement(
                sequence: overtake.sequence,
                fromOrder: movement.fromOrder,
                toOrder: movement.toOrder,
                phase: .released(overtakeMotion),
            )
        } else {
            event = nil
            overtakeMovement = nil
            displayedOrder = current.map(\.region)
        }

        if displayedCounts != currentCounts {
            displayedCounts = currentCounts
        }
        if lastSeenCounts != currentCounts {
            preferences.setLastSeenLocationDayCounts(currentCounts, in: target.year)
            lastSeenCounts = currentCounts
        }
        if shouldProvideCountFeedback || event != nil {
            feedbackTrigger += 1
        }
        return event
    }

    /// Commits the real semantic rank after the authored layout reaches the
    /// same visual endpoint. A stale completion cannot finish a newer overtake.
    func finishOvertakeMovement(sequence: Int) {
        guard let movement = overtakeMovement,
              movement.sequence == sequence,
              movement.releasedMotion != nil
        else { return }
        displayedOrder = movement.toOrder
        overtakeMovement = nil
        guard let target = reconciliationTarget,
              target.isVisible,
              isRankingSurfaceVisible,
              target.year == year
        else { return }
        stagePendingMovement(for: target)
    }

    private func stagePendingMovement(for target: ReconciliationID) {
        let currentOrder = target.counts.map(\.region)
        overtakeMovement = isReversal(from: displayedOrder, to: currentOrder)
            ? OvertakeMovement(
                sequence: overtakeTrigger + 1,
                fromOrder: displayedOrder,
                toOrder: currentOrder,
                phase: .pending,
            )
            : nil
    }

    private func isReversal(from oldOrder: [Region], to newOrder: [Region]) -> Bool {
        newOrder.count == RegionRanking.primaryCount
            && oldOrder.count == RegionRanking.primaryCount
            && Set(newOrder) == Set(oldOrder)
            && newOrder != oldOrder
    }
}
