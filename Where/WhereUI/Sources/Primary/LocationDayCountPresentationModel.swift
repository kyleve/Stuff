import Observation
import RegionKit
import WhereCore

/// Holds the Location cards at the counts the user last saw until their visible
/// card surface can reconcile to the current report and signal the change once.
@MainActor
@Observable
final class LocationDayCountPresentationModel {
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
    private(set) var year: Int
    private(set) var feedbackTrigger = 0

    init(preferences: WherePreferences, year: Int) {
        self.preferences = preferences
        self.year = year
        let savedCounts = preferences.lastSeenLocationDayCounts(in: year)
        lastSeenCounts = savedCounts
        displayedCounts = savedCounts ?? [:]
    }

    /// Load another year's baseline without marking its current report as seen.
    /// `LocationsView` calls this while a year change is happening on another
    /// tab, so the saved values are ready before the cards become visible.
    func prepare(for year: Int) {
        guard year != self.year else { return }
        self.year = year
        let savedCounts = preferences.lastSeenLocationDayCounts(in: year)
        lastSeenCounts = savedCounts
        displayedCounts = savedCounts ?? [:]
    }

    /// The card value to render before the visible surface reconciles. A card
    /// absent from the previous snapshot starts at its current value rather than
    /// inventing a zero the user never saw.
    func presented(_ current: RegionDays) -> RegionDays {
        RegionDays(
            region: current.region,
            days: displayedCounts[current.region] ?? current.days,
        )
    }

    /// When the cards are visible, advance them to the report, persist that
    /// presentation, and emit one feedback trigger if any comparable saved value
    /// increased. Hidden or obscured surfaces leave their baseline untouched.
    func reconcile(_ current: [RegionDays], in year: Int, isVisible: Bool) {
        guard isVisible else { return }
        prepare(for: year)

        let currentCounts = Dictionary(uniqueKeysWithValues: current.map { item in
            (item.region, item.days)
        })
        let shouldProvideFeedback = current.contains { item in
            guard let previousDays = lastSeenCounts?[item.region] else { return false }
            return previousDays < item.days
        }

        if displayedCounts != currentCounts {
            displayedCounts = currentCounts
        }
        if lastSeenCounts != currentCounts {
            preferences.setLastSeenLocationDayCounts(currentCounts, in: year)
            lastSeenCounts = currentCounts
        }
        if shouldProvideFeedback {
            feedbackTrigger += 1
        }
    }
}
