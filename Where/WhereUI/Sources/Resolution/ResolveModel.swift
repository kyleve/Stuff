import Foundation
import Observation
import PeriscopeCore
import RegionKit
import WhereCore

/// Mirrors the scene's coherent scan for correction navigation and dismiss actions.
/// Standalone consumers can load through the same Core scanner.
@MainActor
@Observable
public final class ResolveModel {
    /// Unresolved data-quality issues for the selected year, grouped and sorted
    /// by the scanner.
    public private(set) var dataIssues: [any DataIssue] = []
    public private(set) var reviews: [GPSCorrectionReview] = []
    public private(set) var loadError: String?
    private var loadRequestID = UUID()

    /// Whether the first scan has completed (or a fixture was seeded). Until it
    /// has, `ResolutionView` shows a spinner rather than the "all clear" empty
    /// state — otherwise a populated tab (whose badge already scanned) would
    /// flash empty for the frame before this model's own `load` lands. Once true
    /// it stays true, so later re-scans update the list in place without a
    /// spinner flicker.
    public private(set) var hasLoaded = false

    private let services: WhereServices
    private let preferences: WherePreferences
    private static let logger = WhereLog.session(ResolveModelLog.self)

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
        let requestID = UUID()
        loadRequestID = requestID
        do {
            let scan = try await services.resolution.scan(
                year: year,
                primaryRegions: primaryRegions,
                driftThresholdMeters: Double(preferences.driftThresholdMeters),
                force: false,
            )
            guard loadRequestID == requestID, !Task.isCancelled else { return }
            receive(scan: scan, error: nil)
        } catch is CancellationError {
            return
        } catch {
            guard loadRequestID == requestID, !Task.isCancelled else { return }
            loadError = error.localizedDescription
            // Surface the failure and keep the last good list rather than
            // silently blanking the tab (which would read as "all clear").
            Self.logger { .dataIssueScanFailed(description: error.localizedDescription) }
        }
        // Mark loaded even on failure so the view leaves the spinner (the error
        // was logged and the last good list preserved); a stuck spinner would be
        // its own bug.
        hasLoaded = true
    }

    func receive(scan: DataIssueScanResult?, error: String?) {
        #if DEBUG
            if isSeeded { return }
        #endif
        loadError = error
        if let scan {
            dataIssues = scan.issues
            reviews = scan.reviews
            hasLoaded = true
        } else if error != nil {
            hasLoaded = true
        }
    }

    var pendingReviews: [GPSCorrectionReview] {
        reviews.filter(\.isPending)
    }

    var completedReviews: [GPSCorrectionReview] {
        reviews.filter { !$0.isPending && $0.proposal == nil }
    }

    func review(for issue: any DataIssue) -> GPSCorrectionReview? {
        reviews.first { $0.id == issue.id }
    }

    public func dismiss(_ issue: any DataIssue) async {
        guard issue.isDismissible else { return }
        do {
            try await services.journal.dismissIssue(id: issue.id)
            // Optimistically drop the row for instant feedback; the committed
            // write pings the store-change signal, so the scene's `YearReportModel`
            // recomputes the badge count a beat later.
            dataIssues.removeAll { $0.id == issue.id }
            reviews.removeAll { $0.id == issue.id }
        } catch {
            Self.logger {
                .dismissFailed(
                    issueID: issue.id.storeURL.absoluteString,
                    description: error.localizedDescription,
                )
            }
        }
    }
}

#if DEBUG
    @_spi(Testing) extension ResolveModel {
        /// Inject issues for previews/tests without seeding raw samples. Marks the
        /// model seeded so a subsequent `load(...)` leaves the fixture in place.
        public func setReviews(_ reviews: [GPSCorrectionReview]) {
            self.reviews = reviews
            isSeeded = true
            hasLoaded = true
        }

        public func setDataIssues(_ issues: [any DataIssue]) {
            dataIssues = issues
            isSeeded = true
            hasLoaded = true
        }
    }
#endif
