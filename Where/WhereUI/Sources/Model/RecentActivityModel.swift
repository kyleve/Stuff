import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model for the "last 24 hours" on-device summary. Mirrors the
/// `RecentActivitySummarizer` output into a `LoadState` the sheet renders,
/// distinguishing a real summary from an empty window, an unavailable model,
/// and an outright failure so the UI can respond to each honestly.
@MainActor
@Observable
public final class RecentActivityModel {
    /// Where the summary is in its load lifecycle.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded(String)
        /// The window held no tracked locations — distinct from a blank summary.
        case empty
        /// The on-device model can't run; carries the reason so the UI can guide
        /// the user (e.g. enable Apple Intelligence).
        case unavailable(ActivitySummaryUnavailableReason)
        /// Generation failed; carries a user-presentable message.
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle

    private let services: WhereServices
    private static let logger = WhereLog.channel(.recentActivitySummarizer)

    init(services: WhereServices) {
        self.services = services
    }

    /// Generate (or regenerate) the summary. Maps an unavailable model and a
    /// generation failure to distinct states and logs both — never a silent
    /// empty result that reads like success.
    public func load() async {
        loadState = .loading
        do {
            switch try await services.recentActivity.summary() {
                case let .summary(text):
                    loadState = .loaded(text)
                case .empty:
                    loadState = .empty
            }
        } catch let error as ActivitySummaryUnavailableError {
            loadState = .unavailable(error.reason)
            Self.logger.warning(
                "Recent-activity summary unavailable: \(String(describing: error.reason))",
            )
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Recent-activity summary failed: \(error.localizedDescription)",
            )
        }
    }

    #if DEBUG
        /// Force a state for previews/tests without running the generator.
        func previewLoad(_ state: LoadState) {
            loadState = state
        }
    #endif
}
