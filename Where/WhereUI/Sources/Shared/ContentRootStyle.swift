import CoreGraphics

extension WhereStylesheet {
    /// Point limits for centered scroll content, including its existing padding.
    struct ContentRootStyle: Equatable {
        var regularMaximumWidth: CGFloat = 600
        var wideMaximumWidth: CGFloat = 900
        var standardPadding: CGFloat = 16

        func maximumWidth(for width: WhereContentWidth) -> CGFloat {
            switch width {
                case .regular: regularMaximumWidth
                case .wide: wideMaximumWidth
                case .fluid: .infinity
            }
        }
    }
}
