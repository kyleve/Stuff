import Observation
import PeriscopeCore
import WhereCore

/// Presents pending-share failures without blocking otherwise compatible history.
@MainActor
@Observable
public final class WhereSharedEvidenceModel {
    public private(set) var failure: (any Error)?
    private static let logger = WhereLog.root(WhereLaunchLog.self)

    public var isShowingFailure: Bool {
        get { failure != nil }
        set { if !newValue { dismissFailure() } }
    }

    func dismissFailure() {
        failure = nil
    }

    func importPending(
        using services: WhereServices,
        compatibility: WhereDataCompatibilityModel,
        isCurrent: @MainActor () -> Bool,
    ) async {
        do {
            try await compatibility.importSharedEvidence(using: services)
            if isCurrent() { failure = nil }
        } catch {
            Self.logger.sharedEvidenceImportFailed(error: .restricted(.errorDetails, error))
            if isCurrent() { failure = error }
        }
    }
}
