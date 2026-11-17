import SwiftUI

/// Shared diagnostics keep the release pass-through path available to hosted tests.
struct WhereContentRootDiagnostics {
    #if DEBUG
        var report: @MainActor @Sendable (String) -> Void = { assertionFailure($0) }
    #endif

    @MainActor func reportNesting() {
        #if DEBUG
            report(
                "Do not nest Where content or screen roots. Start a new scope at navigation and sheet destinations with whereScreenBoundary().",
            )
        #endif
    }
}

extension EnvironmentValues {
    @Entry var whereContentRootDiagnostics = WhereContentRootDiagnostics()
}

#if DEBUG
    extension View {
        /// Replaces only the debug diagnostic so tests can exercise the release fallback.
        @_spi(Testing) public func whereContentRootAssertionHandler(
            _ report: @escaping @MainActor @Sendable (String) -> Void,
        ) -> some View {
            environment(\.whereContentRootDiagnostics, WhereContentRootDiagnostics(report: report))
        }
    }
#endif
