import Foundation
import Observation
import RegionKit
import WhereCore

/// Scene-scoped observable state for the synced planned stay. Forecast math
/// remains a pure WhereCore derivation so future residency goals can compare
/// with the result without becoming persistence or UI policy.
@MainActor
@Observable
final class LocationForecastModel {
    struct PlannedStayLocationCheck: Equatable {
        enum Status: Equatable {
            case checking
            case accepted
            case outside
            case unavailable
        }

        let region: Region
        let driftThreshold: DriftThreshold
        let status: Status
    }

    /// The future slice of a planned stay that intersects a displayed year.
    struct PlannedInterval: Equatable {
        let region: Region
        let start: CalendarDay
        let end: CalendarDay

        var dayCount: Int {
            start.days(through: end).count
        }
    }

    private(set) var activePlannedStay: PlannedStay?
    private(set) var plannedStayLocationCheck: PlannedStayLocationCheck?

    private let services: WhereServices
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var plannedStayLocationCheckSequence: UInt64 = 0
    private static let logger = WhereLog.session(LocationForecastModelLog.self)

    init(
        services: WhereServices,
        calendar: Calendar,
        now: @escaping @Sendable () -> Date,
    ) {
        self.services = services
        self.calendar = calendar
        self.now = now
    }

    func refresh() async {
        do {
            let stay = try await services.plannedStays.active()
            if activePlannedStay != stay { activePlannedStay = stay }
        } catch {
            Self.logger { .loadFailed(description: error.localizedDescription) }
        }
    }

    func forecast(for region: Region, report: YearReport?) -> LocationForecast? {
        guard let report else { return nil }
        return LocationForecast.estimate(
            region: region,
            report: report,
            asOf: now(),
            calendar: calendar,
            plannedStay: activePlannedStay,
        )
    }

    /// Up to three present, named regions for the Locations-tab summary.
    /// Independent from `RegionRanking.primaryCount`, which still owns the two
    /// large cards.
    func leadingForecasts(report: YearReport?, limit: Int = 3) -> [LocationForecast] {
        guard let report else { return [] }
        return RegionRanking.ranked(report: report)
            .filter { $0.region != .other }
            .prefix(limit)
            .compactMap { forecast(for: $0.region, report: report) }
    }

    func isCurrent(_ region: Region, report: YearReport?) -> Bool {
        guard let report else { return false }
        let today = CalendarDay(from: now(), in: calendar)
        return report.days.first(where: { $0.day == today })?.regions.contains(region) == true
    }

    /// The user's planned region for a future calendar day. Today remains
    /// recorded presence; the projection begins tomorrow and includes the
    /// selected through-day.
    func plannedRegion(on day: CalendarDay) -> Region? {
        guard let stay = activePlannedStay else { return nil }
        let today = CalendarDay(from: now(), in: calendar)
        guard day > today, day <= stay.through else { return nil }
        return stay.region
    }

    /// The active stay when its future projection intersects `year`. A stay
    /// ending next year still occupies the rest of this year; a past report has
    /// no overlap because projections begin tomorrow.
    func plannedStay(intersecting year: Int) -> PlannedStay? {
        guard plannedInterval(intersecting: year) != nil else { return nil }
        return activePlannedStay
    }

    func plannedInterval(intersecting year: Int) -> PlannedInterval? {
        guard let stay = activePlannedStay else { return nil }
        let tomorrow = CalendarDay(from: now(), in: calendar).adding(days: 1)
        let firstDay = CalendarDay(year: year, month: 1, day: 1)
        let lastDay = CalendarDay.lastDay(ofYear: year)
        let projectedStart = max(tomorrow, firstDay)
        let projectedEnd = min(stay.through, lastDay)
        guard projectedStart <= projectedEnd else { return nil }
        return PlannedInterval(
            region: stay.region,
            start: projectedStart,
            end: projectedEnd,
        )
    }

    func departureDate(for region: Region) -> Date {
        guard let stay = activePlannedStay, stay.region == region else {
            return calendar.startOfDay(for: now())
        }
        return stay.through.startOfDay(in: calendar)
    }

    var minimumDepartureDate: Date {
        calendar.startOfDay(for: now())
    }

    func checkCurrentLocation(
        for region: Region,
        driftThreshold: DriftThreshold,
    ) async {
        let (sequence, overflow) = plannedStayLocationCheckSequence.addingReportingOverflow(1)
        precondition(!overflow, "Planned-stay location check sequence exhausted UInt64.")
        plannedStayLocationCheckSequence = sequence
        plannedStayLocationCheck = PlannedStayLocationCheck(
            region: region,
            driftThreshold: driftThreshold,
            status: .checking,
        )

        let result = await services.plannedStayLocation.status(
            for: region,
            driftThreshold: driftThreshold,
        )
        guard !Task.isCancelled, sequence == plannedStayLocationCheckSequence else { return }

        let status: PlannedStayLocationCheck.Status = switch result {
            case .accepted: .accepted
            case .outside: .outside
            case .unavailable: .unavailable
        }
        plannedStayLocationCheck = PlannedStayLocationCheck(
            region: region,
            driftThreshold: driftThreshold,
            status: status,
        )
    }

    func plannedStayLocationCheck(
        for region: Region,
        driftThreshold: DriftThreshold,
    ) -> PlannedStayLocationCheck? {
        guard plannedStayLocationCheck?.region == region,
              plannedStayLocationCheck?.driftThreshold == driftThreshold
        else {
            return nil
        }
        return plannedStayLocationCheck
    }

    func set(region: Region, through date: Date) async throws {
        let day = CalendarDay(from: date, in: calendar)
        do {
            try await services.plannedStays.set(region: region, through: day)
            activePlannedStay = PlannedStay(region: region, through: day)
        } catch {
            Self.logger { .saveFailed(description: error.localizedDescription) }
            throw error
        }
    }

    func clear() async throws {
        do {
            try await services.plannedStays.clear()
            activePlannedStay = nil
        } catch {
            Self.logger { .clearFailed(description: error.localizedDescription) }
            throw error
        }
    }
}

#if DEBUG
    extension LocationForecastModel {
        func setActivePlannedStay(_ stay: PlannedStay?) {
            activePlannedStay = stay
        }
    }
#endif
