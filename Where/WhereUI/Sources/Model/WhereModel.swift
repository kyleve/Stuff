import Foundation
import Observation
import WhereCore

/// Observable view-model bridging the SwiftUI layer to the `WhereController`
/// actor. Owns the selected year, the loaded `YearReport`, and the GPS /
/// permission state, and funnels every mutation through the controller so the
/// views stay free of persistence and CoreLocation details.
@MainActor
@Observable
public final class WhereModel {
    /// Where the current year's data is in its load lifecycle. `failed`
    /// carries a user-presentable message.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var selectedYear: Int
    public private(set) var report: YearReport?
    public private(set) var loadState: LoadState = .idle
    public private(set) var isTracking = false

    /// Set when a location-permission request comes back denied/restricted,
    /// so the UI can offer to open Settings.
    public var permissionDenied = false

    private var controller: WhereController?

    /// Primary/secondary split of the current report, or an empty ranking
    /// while nothing is loaded.
    public var ranking: RegionRanking {
        guard let report else { return RegionRanking(primary: [], secondary: []) }
        return RegionRanking(report: report)
    }

    /// Total distinct days with any tracked presence in the loaded year.
    public var trackedDayCount: Int {
        report?.days.count ?? 0
    }

    /// Number of calendar days in the selected year (365, or 366 in a leap
    /// year). Region cards scale their ambient progress bar against this rather
    /// than a hardcoded 365.
    public var daysInSelectedYear: Int {
        let calendar = Calendar.current
        guard
            let midYear = calendar.date(from: DateComponents(
                year: selectedYear,
                month: 6,
                day: 15,
            )),
            let range = calendar.range(of: .day, in: .year, for: midYear)
        else { return 365 }
        return range.count
    }

    public static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    public init(selectedYear: Int = WhereModel.currentYear) {
        self.selectedYear = selectedYear
    }

    /// Preview/test seam: inject an already-built controller (and optionally a
    /// preloaded report) so SwiftUI previews and unit tests skip the live
    /// SwiftData + CoreLocation wiring.
    public init(
        controller: WhereController,
        report: YearReport? = nil,
        selectedYear: Int = WhereModel.currentYear,
    ) {
        self.controller = controller
        self.report = report
        self.selectedYear = selectedYear
        loadState = report == nil ? .idle : .loaded
    }

    /// Build the production controller (SwiftData + CoreLocation) on first
    /// appearance, then load the selected year. Safe to call repeatedly; the
    /// controller is only built once.
    public func start() async {
        if controller == nil {
            do {
                let store = try SwiftDataStore.make()
                controller = WhereController(
                    store: store,
                    locationSource: CoreLocationSource(),
                )
            } catch {
                loadState = .failed(error.localizedDescription)
                return
            }
        }
        await refresh()
    }

    public func select(year: Int) async {
        guard year != selectedYear else { return }
        selectedYear = year
        // Drop the previous year's report so views fall back to their loading
        // state instead of rendering stale data under the new year's label.
        report = nil
        await refresh()
    }

    public func refresh() async {
        guard let controller else { return }
        loadState = .loading
        do {
            report = try await controller.yearReport(for: selectedYear)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func setManualDay(date: Date, regions: Set<Region>) async {
        guard let controller else { return }
        do {
            try await controller.addManualDay(date: date, regions: regions)
            await refresh()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func setManualDays(from start: Date, through end: Date, regions: Set<Region>) async {
        guard let controller else { return }
        do {
            try await controller.addManualDays(from: start, through: end, regions: regions)
            await refresh()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    public func requestPermission() async {
        guard let controller else { return }
        do {
            try await controller.requestLocationPermission()
            permissionDenied = false
        } catch {
            // Both `LocationPermissionDeniedError` and any unexpected failure
            // mean we don't have Always access, so route the user to Settings.
            permissionDenied = true
        }
    }

    /// Turn on background tracking. Confirms (and, if needed, requests)
    /// location permission first, and only reports `isTracking` once GPS is
    /// actually running — otherwise the toggle would read "on" while
    /// CoreLocation silently produces nothing. On denial the Settings alert is
    /// surfaced and tracking stays off.
    public func startTracking() async {
        guard let controller else { return }
        do {
            try await controller.requestLocationPermission()
            permissionDenied = false
        } catch {
            permissionDenied = true
            isTracking = false
            return
        }
        await controller.startGPS()
        isTracking = true
    }

    public func stopTracking() async {
        guard let controller else { return }
        await controller.stopGPS()
        isTracking = false
    }

    public func clearSelectedYear() async {
        guard let controller else { return }
        do {
            try await controller.clearYear(selectedYear)
            await refresh()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
