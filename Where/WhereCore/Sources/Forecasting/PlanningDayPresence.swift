import Foundation
import RegionKit

/// Explicit intent and Home assumptions remain separate from measured presence.
public struct PlanningDayPresence: Hashable, Sendable {
    public struct HomeAssumption: Hashable, Sendable {
        public let region: Region
        public let certainty: PlanningCertainty
    }

    public enum Membership: Hashable, Sendable {
        case planned(PlanningCertainty)
        case homeAssumed(PlanningCertainty)
    }

    public let certainRegions: Set<Region>
    /// Includes certain regions as well as those reached by longer intervals.
    public let possibleRegions: Set<Region>
    public let homeAssumption: HomeAssumption?

    /// Effective region certainty for presentation. When an uncertain Home
    /// plan is the only possible explicit presence, Home still covers the day
    /// in every scenario. Raw fields retain the separate sources of that coverage.
    public func membership(in region: Region) -> Membership? {
        if certainRegions.contains(region) { return .planned(.certain) }
        if homeAssumption?.region == region, possibleRegions == [region] {
            return .homeAssumed(.certain)
        }
        if possibleRegions.contains(region) { return .planned(.possible) }
        guard let homeAssumption, homeAssumption.region == region else { return nil }
        return .homeAssumed(homeAssumption.certainty)
    }
}
