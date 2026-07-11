//
//  BContext+Stylesheet.swift
//  BroadwayCore
//

extension BContext {
    /// Resolves `type` from this context's stylesheet cache, returning a
    /// fallback instead of throwing so it can be read inline (e.g. a SwiftUI
    /// `body`) without a `try`.
    ///
    /// A failure here is a programmer error — a stylesheet whose `init(context:)`
    /// throws, or a dependency cycle — so it traps in debug via
    /// `assertionFailure` and degrades to `fallback` in release rather than
    /// silently succeeding. Stylesheets that only read traits/themes never throw
    /// and always take the resolved path.
    public func stylesheet<Stylesheet: BStylesheet>(
        _ type: Stylesheet.Type,
        fallback: @autoclosure () -> Stylesheet,
    ) -> Stylesheet {
        do {
            return try stylesheets.get(type)
        } catch {
            assertionFailure("Failed to resolve \(Stylesheet.self): \(error)")
            return fallback()
        }
    }
}
