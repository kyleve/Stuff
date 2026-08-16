import Foundation
import Observation
import PeriscopeCore
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
    private static let logger = WhereLog.root(LoggedDaysModelLog.self)

    #if DEBUG
        /// A preview-declared state is already the final fixture; observing its
        /// empty backing store would replace it as soon as the view appears.
        private var isPreviewStatePinned = false
    #endif

    init(services: WhereServices) {
        self.services = services
    }

    /// Load the year's manual days, then keep the list in sync by reloading on
    /// every committed store change — an add, edit, or delete from this screen
    /// or anywhere (the single read-refresh signal, `dataChangeUpdates()`). Runs
    /// until the calling `.task` is cancelled (the sheet closes).
    public func observe(year: Int) async {
        #if DEBUG
            guard isPreviewStatePinned == false else { return }
        #endif
        await load(for: year)
        for await _ in services.dataChangeUpdates() {
            await load(for: year)
        }
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
                .sorted { $0.day > $1.day }
            loadState = days.isEmpty ? .empty : .loaded(days)
        } catch {
            loadState = .failed(error.localizedDescription)
            Self.logger.loadFailed(
                year: .restricted(.domainValue, year),
                description: .restricted(.errorDetails, error.localizedDescription),
            )
        }
    }

    #if DEBUG
        /// Force a state for previews/tests without touching the store.
        func previewLoad(_ state: LoadState) {
            loadState = state
            isPreviewStatePinned = true
        }
    #endif
}
