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
    private var overtakeSequence = 0
    private var winnerTriggers: [Region: Int] = [:]

    private(set) var year: Int
    private(set) var feedbackTrigger = 0
    private(set) var latestOvertake: OvertakeEvent?

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
            return
        }

        isRankingSurfaceVisible = true
        guard yearChanged || !wasVisible else { return }
        displayedOrder = target.counts.map(\.region)
        for item in target.counts where displayedCounts[item.region] == nil {
            displayedCounts[item.region] = item.days
        }
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
        return currentOrder.count == RegionRanking.primaryCount
            && displayedOrder.count == RegionRanking.primaryCount
            && Set(currentOrder) == Set(displayedOrder)
            && currentOrder != displayedOrder
    }

    /// Advances counts and order to the report, persists the presentation, and
    /// emits one feedback trigger for an increased count or live overtake.
    @discardableResult
    func reconcile(_ target: ReconciliationID) -> OvertakeEvent? {
        guard target == reconciliationTarget,
              target.isVisible,
              isRankingSurfaceVisible,
              target.year == year
        else { return nil }
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
        if isOvertake, let winner = current.first?.region, let passedRegion = displayedOrder.first {
            overtakeSequence += 1
            winnerTriggers[winner, default: 0] += 1
            event = OvertakeEvent(
                sequence: overtakeSequence,
                winner: winner,
                passedRegion: passedRegion,
            )
            latestOvertake = event
        } else {
            event = nil
        }

        displayedOrder = current.map(\.region)
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

    /// A region-local trigger that changes only when that region wins. Losing a
    /// later overtake must not replay the previous winner's keyframes.
    func overtakeTrigger(for region: Region) -> Int {
        winnerTriggers[region, default: 0]
    }
}
