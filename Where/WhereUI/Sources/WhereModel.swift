import Foundation
import Observation
import WhereCore

/// Drives `RootView`: owns the `WhereController`, the selected calendar
/// year, and the async load of that year's `YearReport`.
///
/// Two construction paths:
/// - `init()` — the app entry point. The production controller
///   (`WhereController.live()`) is built lazily on first `load()` so
///   constructing the view never touches SwiftData / CoreLocation.
/// - `init(controller:)` — tests and previews inject a controller wired
///   to an in-memory store and a `ScriptedLocationSource`.
@MainActor
@Observable
public final class WhereModel {
    public enum LoadState: Sendable {
        case loading
        case loaded(YearReport)
        case failed(String)
    }

    public private(set) var state: LoadState = .loading
    public private(set) var year: Int

    private var controller: WhereController?

    public init(year: Int = WhereModel.currentYear) {
        self.year = year
    }

    public init(controller: WhereController, year: Int = WhereModel.currentYear) {
        self.year = year
        self.controller = controller
    }

    public static var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    public func load() async {
        state = .loading
        do {
            let report = try await resolveController().yearReport(for: year)
            state = .loaded(report)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func selectYear(_ newYear: Int) async {
        guard newYear != year else { return }
        year = newYear
        await load()
    }

    /// Lazily build (and cache) the production controller on first use.
    /// The injected initializer populates `controller` up front, so this
    /// only constructs `live()` for the app entry point.
    private func resolveController() throws -> WhereController {
        if let controller { return controller }
        let made = try WhereController.live()
        controller = made
        return made
    }
}
