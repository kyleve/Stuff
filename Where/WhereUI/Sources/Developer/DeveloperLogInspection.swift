import PeriscopeCore
import SwiftUI
#if DEBUG
    import PeriscopeTools
#endif

extension View {
    /// Make this view inspectable in Periscope's "log view mode" in debug
    /// builds, and a no-op in release. Wraps PeriscopeTools' `logInspectable(_:)`
    /// so production call sites stay clean and the tools code path compiles out
    /// of release entirely.
    ///
    /// With the developer overlay's Log View Mode on, wrapped views gain a badge
    /// that opens the newest events in `log`'s scope subtree — e.g. wrap an
    /// evidence row in `WhereLog.evidence` to see everything logged under it.
    @ViewBuilder
    func debugLogInspectable(_ log: Log<some LogScopeDefinition>) -> some View {
        #if DEBUG
            logInspectable(log)
        #else
            self
        #endif
    }
}
