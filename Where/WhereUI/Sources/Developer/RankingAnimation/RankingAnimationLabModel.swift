#if DEBUG
    import Observation
    import RegionKit
    import WhereCore

    /// Session-only fixture for repeatedly reversing the same two ranked cards
    /// through the production presentation coordinator.
    @MainActor
    @Observable
    final class RankingAnimationLabModel {
        static let year = 2026
        static let initialRanking = [
            RegionDays(region: .california, days: 128),
            RegionDays(region: .newYork, days: 127),
        ]

        private(set) var current: [RegionDays]
        private(set) var presentation: LocationCardsPresentationModel

        init() {
            current = Self.initialRanking
            presentation = Self.makePresentation()
        }

        func playNextOvertake() {
            guard current.count == RegionRanking.primaryCount else {
                assertionFailure("The ranking lab requires exactly two cards.")
                return
            }
            let nextWinner = current[1].region
            let winningDays = current[0].days + 1
            let updated = current.map { item in
                RegionDays(
                    region: item.region,
                    days: item.region == nextWinner ? winningDays : item.days,
                )
            }
            current = Region.rankedByDayCount(
                updated,
                days: \.days,
                region: \.region,
            )
        }

        private static func makePresentation() -> LocationCardsPresentationModel {
            let preferences = WherePreferences(store: InMemoryKeyValueStore())
            preferences.setLastSeenLocationDayCounts(
                Dictionary(uniqueKeysWithValues: initialRanking.map { ($0.region, $0.days) }),
                in: year,
            )
            return LocationCardsPresentationModel(preferences: preferences, year: year)
        }
    }
#endif
