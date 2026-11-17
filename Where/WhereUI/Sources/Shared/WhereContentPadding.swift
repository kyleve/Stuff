import SwiftUI

/// Padding inside a screen's width limit. Native lists and forms own their row insets.
enum WhereContentPadding: Equatable {
    case standard
    case none
    case custom(EdgeInsets)

    func insets(standard: CGFloat) -> EdgeInsets {
        switch self {
            case .standard:
                EdgeInsets(top: standard, leading: standard, bottom: standard, trailing: standard)
            case .none:
                EdgeInsets()
            case let .custom(insets):
                insets
        }
    }
}
