import SwiftUI

extension View {
    /// Starts an independent content scope at a pushed or presented destination.
    /// The width policy still inherits. Do not use this to allow roots inside one scroller.
    func whereScreenBoundary() -> some View {
        environment(\.isInsideWhereContentRoot, false)
    }
}
