import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model backing the "all evidence" sheet: loads the selected
/// year's evidence into a `LoadState` the list renders, distinguishing a real
/// list from an empty year and an outright failure (never a silent empty list
/// that reads like "no evidence" when the load actually failed).
@MainActor
@Observable
public final class EvidenceListModel {
    /// Where the evidence list is in its load lifecycle.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded([Evidence])
        /// The year genuinely holds no evidence — distinct from a failed load.
        case empty
        /// Loading failed; carries a user-presentable message.
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle

    private let services: WhereServices
    private static let logger = WhereLog.channel(.evidence)

    init(services: WhereServices) {
        self.services = services
    }

    /// Load (or reload) the evidence captured in `year`. Maps an empty result to
    /// `.empty` and a failure to `.failed(_)` + a logged warning, keeping the
    /// two honestly distinct.
    public func load(for year: Int) async {
        loadState = .loading
        do {
            let evidence = try await services.evidence.list(for: year)
            loadState = evidence.isEmpty ? .empty : .loaded(evidence)
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Failed to load evidence for \(year): \(error.localizedDescription)",
            )
        }
    }

    #if DEBUG
        /// Force a state for previews/tests without touching the store.
        func previewLoad(_ state: LoadState) {
            loadState = state
        }
    #endif
}
