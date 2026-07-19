import Foundation
import Observation
import PeriscopeCore
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

    /// The look-back window the summary covers. The sheet's segmented control
    /// binds to this directly; changing it triggers a fresh `load()`.
    public var window: RecentActivityWindow = .day

    private let services: WhereServices
    private static let logger = WhereLog.recentActivity(RecentActivityModelLog.self)

    init(services: WhereServices) {
        self.services = services
    }

    /// Generate (or regenerate) the summary for the selected `window`. Maps an
    /// unavailable model and a generation failure to distinct states and logs
    /// both — never a silent empty result that reads like success.
    public func load() async {
        loadState = .loading
        do {
            switch try await services.recentActivity.summary(for: window) {
                case let .summary(text):
                    loadState = .loaded(text)
                case .empty:
                    loadState = .empty
            }
        } catch let error as ActivitySummaryUnavailableError {
            loadState = .unavailable(error.reason)
            Self.logger { .summaryUnavailable(reason: String(describing: error.reason)) }
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger { .summaryFailed(description: error.localizedDescription) }
        }
    }

    #if DEBUG
        /// Force a state for previews/tests without running the generator.
        func previewLoad(_ state: LoadState) {
            loadState = state
        }
    #endif
}
