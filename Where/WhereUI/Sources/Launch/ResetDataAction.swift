import SwiftUI

/// Environment action that triggers the app's "erase all data & reset"
/// teardown. `RootView` wires it to
/// `Launcher.reset(WhereLaunch.resetSequence(for:))`; screens hosted without a
/// launcher (previews, unit tests) get the default no-op.
///
/// This indirection (rather than reading the `Launcher` from the environment)
/// keeps the launcher a view-layer concern and stays safe when absent: a
/// required `@Environment(Launcher.self)` would trap when no launcher is
/// injected, whereas the default action simply does nothing.
struct ResetDataAction {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @MainActor func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    @Entry var resetData = ResetDataAction {}
}
