import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model for the Resolve tab: the full list of unresolved
/// data-quality issues for the selected year, plus the dismiss action. Owned as
/// `@State` by `ResolutionView`, so it's created when the Resolve tab is first
/// shown and torn down with it.
///
/// The tab-bar badge *count* lives on the scene-scoped `ReportModel` instead
/// (it must render before this tab is ever materialized); this model owns the
/// list the screen shows. `ResolutionView` drives `load(year:primaryRegions:)`
/// from a `.task(id:)` keyed on the report's `dataIssueScanInputs`, so the list
/// re-scans on appear, on any committed write, on a year switch, and on a
/// drift-threshold change — all while sharing the scanner's cache with the badge
/// recount.
@MainActor
@Observable
public final class ResolveModel {
    /// Unresolved data-quality issues for the selected year, grouped and sorted
    /// by the scanner.
    public private(set) var dataIssues: [any DataIssue] = []

    private let services: WhereServices
    private let preferences: WherePreferences
    private static let logger = WhereLog.channel(.session)

    #if DEBUG
        /// Set by the `@_spi(Testing)` seeder so `load(...)` doesn't clobber
        /// preview/test fixtures with an empty scan of a store that has no raw
        /// samples. Never compiled into release.
        private var isSeeded = false
    #endif

    public init(services: WhereServices, preferences: WherePreferences) {
        self.services = services
        self.preferences = preferences
    }

    /// Scan for data issues in `year`. Uses the cached scan (shared with the
    /// badge recount) unless the store has changed since. `primaryRegions`
    /// tunes the border-drift relabel suggestions.
    public func load(year: Int, primaryRegions: [Region]) async {
        #if DEBUG
            if isSeeded { return }
        #endif
        do {
            let issues = try await services.resolution.issues(
                year: year,
                primaryRegions: primaryRegions,
                driftThresholdMeters: Double(preferences.driftThresholdMeters),
                force: false,
            )
            dataIssues = issues
        } catch {
            // Surface the failure and keep the last good list rather than
            // silently blanking the tab (which would read as "all clear").
            Self.logger.warning(
                "Failed to scan for data issues: \(error.localizedDescription)",
            )
        }
    }

    public func dismiss(_ issue: any DataIssue) async {
        guard issue.isDismissible else { return }
        do {
            try await services.journal.dismissIssue(key: issue.id.storageKey)
            // Optimistically drop the row for instant feedback; the committed
            // write pings the store-change signal, so the scene's `ReportModel`
            // recomputes the badge count a beat later.
            dataIssues.removeAll { $0.id == issue.id }
        } catch {
            Self.logger.warning(
                "Failed to dismiss data issue \(issue.id.storageKey): \(error.localizedDescription)",
            )
        }
    }
}

#if DEBUG
    @_spi(Testing) extension ResolveModel {
        /// Inject issues for previews/tests without seeding raw samples. Marks the
        /// model seeded so a subsequent `load(...)` leaves the fixture in place.
        public func setDataIssues(_ issues: [any DataIssue]) {
            dataIssues = issues
            isSeeded = true
        }
    }
#endif
