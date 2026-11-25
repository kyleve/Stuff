import SwiftUI

extension StrokeStyle {
    /// Rounded joins keep sharp bends in coastlines within half a stroke width of the boundary.
    static func regionOutline(lineWidth: CGFloat) -> Self {
        Self(lineWidth: lineWidth, lineJoin: .round)
    }
}
