import Foundation
import RegionKit
import WhereCore

/// A complete, mutually exclusive classification of every calendar day in one
/// year, shared by the Your Year breakdown and heatmap visualizations.
struct YearOverview {
    /// One day in the year and the single state it can display as.
    struct Day: Hashable, Identifiable {
        enum Kind: Hashable {
            case region(Region)
            case multipleLocations([Region])
            case unrecorded
            case remaining

            var sliceID: Slice.ID {
                switch self {
                    case let .region(region): .region(region)
                    case .multipleLocations: .multipleLocations
                    case .unrecorded: .unrecorded
                    case .remaining: .remaining
                }
            }

            var isRecorded: Bool {
                switch self {
                    case .region, .multipleLocations: true
                    case .unrecorded, .remaining: false
                }
            }
        }

        let id: CalendarDay
        let kind: Kind
    }

    /// One mutually exclusive donut segment. Region segments are followed by
    /// the special categories in a stable order.
    struct Slice: Hashable, Identifiable {
        enum ID: Hashable {
            case region(Region)
            case multipleLocations
            case unrecorded
            case remaining
        }

        let id: ID
        let days: Int
    }

    let year: Int
    let days: [Day]
    let slices: [Slice]
    let regions: [Region]
    let recordedDayCount: Int

    private let daysByID: [CalendarDay: Day]

    var dayCount: Int {
        days.count
    }

    init(report: YearReport, referenceDate: Date, calendar: Calendar) {
        year = report.year
        let referenceDay = CalendarDay(from: referenceDate, in: calendar)
        let presenceByDay = Dictionary(
            uniqueKeysWithValues: report.days.map { ($0.day, $0) },
        )

        let classifiedDays = CalendarDay.yearRange(report.year).lowerBound
            .days(through: CalendarDay.yearRange(report.year).upperBound)
            .map { day in
                Day(id: day, kind: Self.kind(
                    for: day,
                    presence: presenceByDay[day],
                    referenceDay: referenceDay,
                ))
            }

        days = classifiedDays
        daysByID = Dictionary(uniqueKeysWithValues: classifiedDays.map { ($0.id, $0) })
        regions = Region.inCanonicalOrder(Set(classifiedDays.flatMap { day -> [Region] in
            switch day.kind {
                case let .region(region): return [region]
                case let .multipleLocations(regions): return regions
                case .unrecorded, .remaining: return []
            }
        }))
        recordedDayCount = classifiedDays.count(where: { $0.kind.isRecorded })
        slices = Self.makeSlices(from: classifiedDays)
    }

    func day(month: Int, dayOfMonth: Int) -> Day? {
        daysByID[CalendarDay(year: year, month: month, day: dayOfMonth)]
    }

    private static func kind(
        for day: CalendarDay,
        presence: DayPresence?,
        referenceDay: CalendarDay,
    ) -> Day.Kind {
        // A future entry is not elapsed time. Keeping it Remaining makes the
        // overview honest even if malformed/imported data contains one.
        guard day <= referenceDay else { return .remaining }

        let regions = Region.inCanonicalOrder(presence?.regions ?? [])
        if let region = regions.first, regions.count == 1 {
            return .region(region)
        }
        if regions.count > 1 {
            return .multipleLocations(regions)
        }

        // Today is still in progress; existing missing-day rules likewise wait
        // until tomorrow before treating it as an unrecorded day.
        return day == referenceDay ? .remaining : .unrecorded
    }

    private static func makeSlices(from days: [Day]) -> [Slice] {
        var totals: [Slice.ID: Int] = [:]
        for day in days {
            totals[day.kind.sliceID, default: 0] += 1
        }

        let regionSlices = totals.compactMap { id, count -> Slice? in
            guard case .region = id, count > 0 else { return nil }
            return Slice(id: id, days: count)
        }.sorted { lhs, rhs in
            if lhs.days != rhs.days { return lhs.days > rhs.days }
            guard case let .region(lhsRegion) = lhs.id,
                  case let .region(rhsRegion) = rhs.id
            else {
                return false
            }
            return Region.declarationOrder[lhsRegion, default: 0]
                < Region.declarationOrder[rhsRegion, default: 0]
        }

        let specialOrder: [Slice.ID] = [.multipleLocations, .unrecorded, .remaining]
        let specialSlices = specialOrder.compactMap { id -> Slice? in
            guard let count = totals[id], count > 0 else { return nil }
            return Slice(id: id, days: count)
        }
        return regionSlices + specialSlices
    }
}
