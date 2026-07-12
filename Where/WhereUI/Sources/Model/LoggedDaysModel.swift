import Foundation
import LogKit
import Observation
import WhereCore

/// View-scoped model backing the "logged days" sheet: loads the selected year's
/// manual entries (backfills and authoritative overrides) into a `LoadState` the
/// list renders, distinguishing a real list from a year with no manual entries
/// and an outright failure — never a silent empty list that reads like "nothing
/// logged" when the load actually failed.
@MainActor
@Observable
public final class LoggedDaysModel {
    /// Where the logged-days list is in its load lifecycle.
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded([DayPresence])
        /// The year genuinely holds no manual entries — distinct from a failure.
        case empty
        /// Loading failed; carries a user-presentable message.
        case failed(String)
    }

    public private(set) var loadState: LoadState = .idle

    private let services: WhereServices
    private static let logger = WhereLog.channel(.dayJournal)

    init(services: WhereServices) {
        self.services = services
    }

    /// Load (or reload) the manual days logged for `year`, newest first. Maps an
    /// empty result to `.empty` and a failure to `.failed(_)` + a logged warning,
    /// keeping the two honestly distinct.
    ///
    /// A reload while content is already shown (an edit committed, an entry
    /// deleted) keeps the current list on screen instead of flashing the loading
    /// view; the spinner only shows on the first load or after a failure.
    public func load(for year: Int) async {
        switch loadState {
            case .loaded, .empty:
                break
            case .idle, .loading, .failed:
                loadState = .loading
        }
        do {
            let days = try await services.reports.manualDays(inYear: year)
                .sorted { $0.date > $1.date }
            loadState = days.isEmpty ? .empty : .loaded(days)
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger.warning(
                "Failed to load logged days for \(year): \(error.localizedDescription)",
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
