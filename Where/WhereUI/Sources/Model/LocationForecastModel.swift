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
    private(set) var activePlannedStay: PlannedStay?

    private let services: WhereServices
    private let calendar: Calendar
    private let now: @Sendable () -> Date
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

    func departureDate(for region: Region) -> Date {
        guard let stay = activePlannedStay, stay.region == region else {
            return calendar.startOfDay(for: now())
        }
        return stay.through.startOfDay(in: calendar)
    }

    var minimumDepartureDate: Date {
        calendar.startOfDay(for: now())
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
