import Foundation
import Observation
import RegionKit
import WhereCore

/// Scene-scoped mirror of the synced itinerary. Core owns date projections and
/// estimates; committed store changes are the only production refresh path.
@MainActor
@Observable
final class LocationForecastModel {
    private enum LoadState {
        case idle
        case loading(previous: PlanningSnapshot?)
        case loaded(PlanningSnapshot)
        case failed(previous: PlanningSnapshot?, message: String)

        var snapshot: PlanningSnapshot? {
            switch self {
                case .idle: nil
                case let .loading(previous), let .failed(previous, _): previous
                case let .loaded(snapshot): snapshot
            }
        }
    }

    private var loadState: LoadState = .idle
    private var refreshSequence: UInt64 = 0
    private let services: WhereServices
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private static let logger = WhereLog.session(LocationForecastModelLog.self)

    init(services: WhereServices, calendar: Calendar, now: @escaping @Sendable () -> Date) {
        self.services = services
        self.calendar = calendar
        self.now = now
    }

    var planning: PlanningSnapshot {
        loadState.snapshot ?? PlanningSnapshot(stays: [], homeRegion: nil)
    }

    var hasLoaded: Bool {
        loadState.snapshot != nil
    }

    var isLoading: Bool {
        if case .loading = loadState { return true }
        return false
    }

    var loadFailure: String? {
        guard case let .failed(_, message) = loadState else { return nil }
        return message
    }

    var today: CalendarDay {
        CalendarDay(from: now(), in: calendar)
    }

    func refresh() async {
        refreshSequence += 1
        let sequence = refreshSequence
        let previous = loadState.snapshot
        loadState = .loading(previous: previous)
        do {
            let snapshot = try await services.plannedStays.snapshot()
            guard !Task.isCancelled, sequence == refreshSequence else { return }
            loadState = .loaded(snapshot)
        } catch {
            guard !Task.isCancelled, sequence == refreshSequence else { return }
            Self.logger { .loadFailed(description: error.localizedDescription) }
            loadState = .failed(previous: previous, message: error.localizedDescription)
        }
    }

    func forecast(for region: Region, report: YearReport?) -> LocationForecast? {
        guard let report, hasLoaded else { return nil }
        return LocationForecast.estimate(
            region: region,
            report: report,
            asOf: now(),
            calendar: calendar,
            planning: planning,
        )
    }

    /// Explicit destinations and Home remain visible even before a recorded
    /// visit. Recorded card rankings remain independent of these estimates.
    func leadingForecasts(report: YearReport?) -> [LocationForecast] {
        guard let report else { return [] }
        var regions = Set(report.days.flatMap(\.regions))
        regions.formUnion(planning.stays.filter {
            $0.departure.latest > today && $0.arrival.earliest.year <= report.year
        }.map(\.region))
        if let home = planning.homeRegion { regions.insert(home) }
        regions.remove(.other)
        return Region.inCanonicalOrder(regions).compactMap {
            forecast(for: $0, report: report)
        }.sorted {
            if $0.estimatedTotalDays.upper != $1.estimatedTotalDays.upper {
                return $0.estimatedTotalDays.upper > $1.estimatedTotalDays.upper
            }
            return $0.region.rawValue < $1.region.rawValue
        }
    }

    func plannedPresence(on day: CalendarDay) -> PlanningDayPresence {
        planning.plannedPresence(on: day, asOf: today)
    }

    func plannedIntervals(intersecting year: Int) -> [PlannedStayInterval] {
        planning.stayIntervals(intersecting: year, asOf: today)
    }

    func homeIntervals(intersecting year: Int) -> [PlannedHomeInterval] {
        planning.homeIntervals(intersecting: year, asOf: today)
    }

    func plannedRegionSummaries(in month: CalendarMonth) -> [PlanningRegionSummary] {
        guard let first = month.days.first, let last = month.days.last else { return [] }
        let start = CalendarDay(from: first.date, in: calendar)
        let end = CalendarDay(from: last.date, in: calendar)
        return planning.regionSummaries(in: start ... end, asOf: today)
    }

    func create(stay: PlannedStay) async throws {
        do { try await services.plannedStays.create(stay) }
        catch {
            Self.logger { .saveFailed(description: error.localizedDescription) }
            throw error
        }
    }

    func update(stay: PlannedStay) async throws {
        do { try await services.plannedStays.update(stay) }
        catch {
            Self.logger { .saveFailed(description: error.localizedDescription) }
            throw error
        }
    }

    func delete(stayID: PlannedStay.ID) async throws {
        do { try await services.plannedStays.delete(stayID: stayID) }
        catch {
            Self.logger { .clearFailed(description: error.localizedDescription) }
            throw error
        }
    }

    func setHomeRegion(_ region: Region?) async throws {
        do { try await services.plannedStays.setHomeRegion(region) }
        catch {
            Self.logger { .saveFailed(description: error.localizedDescription) }
            throw error
        }
    }
}

#if DEBUG
    extension LocationForecastModel {
        @_spi(Testing) public func setPlanning(_ planning: PlanningSnapshot) {
            loadState = .loaded(planning)
        }
    }
#endif
