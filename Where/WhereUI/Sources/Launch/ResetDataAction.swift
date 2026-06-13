import SwiftUI

/// Environment action that triggers the app's "erase all data & reset"
/// teardown. `RootView` wires it to
/// `LifecycleRunner.reset(WhereLaunch.resetSequence(for:))`; screens hosted
/// without a runner (previews, unit tests) get the default no-op.
///
/// This indirection (rather than reading the `LifecycleRunner` from the
/// environment) keeps the runner a view-layer concern and stays safe when
/// absent: a required `@Environment(LifecycleRunner.self)` would trap when no
/// runner is injected, whereas the default action simply does nothing.
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
