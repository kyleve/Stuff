import CoreGraphics

/// Container-relative sizing for the app-icon picker grid and the full-screen
/// preview. Both flex with the space they're given instead of using fixed point
/// sizes, and every result is clamped to a maximum (see `WhereStylesheet.Size`) so
/// icons never grow unbounded on large displays like iPad.
enum AppIconLayout {
    /// Fewest grid columns, so phones keep the familiar two-up layout even when
    /// a single column could technically be wider.
    private static let minGridColumns = 2
    /// Target grid thumbnail edge used to decide how many columns fit. The
    /// realized size flexes around this and is capped at `appIconGridMax`.
    private static let idealGridIcon: CGFloat = 150

    /// Fractions of the page the slide-up preview icon may occupy before the
    /// cap applies. Width leaves side margins; height keeps the panel (icon plus
    /// its name, hint, and the Set button) to a reasonable share of the screen.
    private static let previewIconWidthFraction: CGFloat = 0.5
    private static let previewIconHeightFraction: CGFloat = 0.3

    /// Column count and per-thumbnail edge for the picker grid at `width`.
    static func gridMetrics(containerWidth width: CGFloat) -> AppIconGridMetrics {
        let spacing = WhereStylesheet.default.spacing.xxLarge
        let available = max(width - spacing * 2, 0)
        let columnsThatFit = Int((available + spacing) / (idealGridIcon + spacing))
        let columnCount = max(minGridColumns, columnsThatFit)
        let columnWidth = (available - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let iconSize = min(max(columnWidth, 0), WhereStylesheet.default.size.appIconGridMax)
        return AppIconGridMetrics(columnCount: columnCount, iconSize: iconSize)
    }

    /// Edge for the slide-up preview icon given the page `size` it appears over.
    static func previewIconSize(containerSize size: CGSize) -> CGFloat {
        let bounded = min(
            size.width * previewIconWidthFraction,
            size.height * previewIconHeightFraction,
            WhereStylesheet.default.size.appIconPreviewLargeMax,
        )
        return max(bounded, 0)
    }
}

/// Column count and per-thumbnail edge for the picker grid at a given width.
struct AppIconGridMetrics: Equatable {
    let columnCount: Int
    let iconSize: CGFloat
}
