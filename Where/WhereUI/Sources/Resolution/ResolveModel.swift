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

    /// Whether the source has published a scan or a failure. Until it
    /// has, `ResolutionView` shows a spinner rather than the "all clear" empty
    /// state — otherwise a populated tab (whose badge already scanned) would
    /// flash empty for the frame before this model's own `load` lands. Once true
    /// it stays true, so later re-scans update the list in place without a
    /// spinner flicker.
    public private(set) var hasLoaded = false

    private let services: WhereServices
    private let source: any ResolutionSource
    private static let logger = WhereLog.session(ResolveModelLog.self)

    public convenience init(services: WhereServices, preferences: WherePreferences) {
        self.init(
            services: services,
            source: ScannerResolutionSource(scanner: services.resolution, preferences: preferences),
        )
    }

    init(services: WhereServices, source: any ResolutionSource) {
        self.services = services
        self.source = source
        receive(source.resolutionState)
    }

    public func load(year: Int, primaryRegions: [Region]) async {
        let requestID = UUID()
        loadRequestID = requestID
        await source.refreshResolution(year: year, primaryRegions: primaryRegions)
        guard requestID == loadRequestID, !Task.isCancelled else { return }
        receive(source.resolutionState)
    }

    private func receive(_ state: ResolutionSourceState) {
        switch state {
            case .idle:
                break
            case let .loaded(scan):
                dataIssues = scan.issues
                reviews = scan.reviews
                loadError = nil
                hasLoaded = true
            case let .failed(error, previous):
                if let previous {
                    dataIssues = previous.issues
                    reviews = previous.reviews
                }
                loadError = error
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
            reviews = reviews.compactMap {
                $0.id == issue.id ? $0.dismissingProposal() : $0
            }
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
