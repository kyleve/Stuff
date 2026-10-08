import RegionKit
import WhereCore

/// Orders explicit stays and inferred Home gaps without merging saved identities.
enum PlanningTimelineItem: Hashable, Identifiable {
    enum ID: Hashable {
        case stay(PlannedStay.ID)
        case home(PlannedHomeInterval)
    }

    case stay(PlannedStayInterval)
    case home(PlannedHomeInterval)

    var id: ID {
        switch self {
            case let .stay(interval): .stay(interval.stayID)
            case let .home(interval): .home(interval)
        }
    }

    var region: Region {
        switch self {
            case let .stay(interval): interval.region
            case let .home(interval): interval.region
        }
    }

    var start: CalendarDay {
        switch self {
            case let .stay(interval): interval.start
            case let .home(interval): interval.start
        }
    }

    var end: CalendarDay {
        switch self {
            case let .stay(interval): interval.end
            case let .home(interval): interval.end
        }
    }

    var dayCount: DayBounds {
        switch self {
            case let .stay(interval): interval.dayCount
            case let .home(interval): interval.dayCount
        }
    }

    var membership: PlanningDayPresence.Membership {
        switch self {
            case let .stay(interval): .planned(interval.dayCount.isExact ? .certain : .possible)
            case let .home(interval): .homeAssumed(interval.certainty)
        }
    }

    static func items(planning: PlanningSnapshot, year: Int, today: CalendarDay) -> [Self] {
        let stays = planning.stayIntervals(intersecting: year, asOf: today).map(Self.stay)
        let homes = planning.homeIntervals(intersecting: year, asOf: today).map(Self.home)
        return (stays + homes).sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.region != $1.region { return $0.region.rawValue < $1.region.rawValue }
            switch ($0, $1) {
                case let (.stay(first), .stay(second)):
                    return first.stayID.rawValue.uuidString < second.stayID.rawValue.uuidString
                case (.stay, .home): return true
                case (.home, .stay): return false
                case (.home, .home): return $0.end < $1.end
            }
        }
    }
}
