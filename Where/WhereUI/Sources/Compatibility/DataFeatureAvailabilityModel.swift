import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// Presentation for one feature's data requirement. Observation never activates the feature.
@MainActor
@Observable
public final class DataFeatureAvailabilityModel {
    public enum State: Equatable, Sendable {
        case checking
        case available(DataCompatibilityActivationReview)
        case needsDeviceReview(DataCompatibilityActivationReview)
        case updateRequired(DataCompatibilityStatus)
        case verificationFailed(description: String)
    }

    public let requiredVersion: DataCompatibilityVersion
    public private(set) var state: State = .checking

    private let source: any DataCompatibilityReviewSource
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var observationID: UUID?

    private static let logger = WhereLog.root(CompatibilityPresentationLog.self)

    public init(
        requiring version: DataCompatibilityVersion,
        source: any DataCompatibilityReviewSource,
    ) {
        requiredVersion = version
        self.source = source
    }

    /// Observe for the owning surface's lifetime, usually in its `.task`.
    /// Subscribe before reading so a commit during the first check is not missed.
    public func observe() async {
        guard !Task.isCancelled else { return }
        let observationID = UUID()
        self.observationID = observationID
        let updates = source.updates()
        var refresh = startRefresh()
        defer {
            refresh.cancel()
            if self.observationID == observationID {
                self.observationID = nil
                invalidate()
            }
        }
        for await _ in updates {
            guard !Task.isCancelled, self.observationID == observationID else { return }
            refresh.cancel()
            refresh = startRefresh()
        }
    }

    /// Retry is read-only and supersedes any older check.
    public func refresh() async {
        let requestID = invalidate()
        await refresh(requestID: requestID)
    }

    private func startRefresh() -> Task<Void, Never> {
        let requestID = invalidate()
        return Task { await refresh(requestID: requestID) }
    }

    @discardableResult
    private func invalidate() -> UUID {
        requestID = UUID()
        state = .checking
        return requestID
    }

    private func refresh(requestID: UUID) async {
        guard !Task.isCancelled, self.requestID == requestID else { return }
        let next: State
        do {
            let review = try await source.reviewActivation(requiring: requiredVersion)
            next = review.requiresConfirmation ? .needsDeviceReview(review) : .available(review)
        } catch is CancellationError {
            return
        } catch let DataCompatibilityError.updateRequired(status) {
            next = .updateRequired(status)
        } catch {
            guard !Task.isCancelled, self.requestID == requestID else { return }
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            next = .verificationFailed(description: error.localizedDescription)
        }
        guard !Task.isCancelled, self.requestID == requestID else { return }
        state = next
    }
}
