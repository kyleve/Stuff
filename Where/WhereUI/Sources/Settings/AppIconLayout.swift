import CoreGraphics

/// Container-relative sizing for the app-icon picker grid and the full-screen
/// preview. Both flex with the space they're given instead of using fixed point
/// sizes, and every result is clamped to a maximum (see `UIConstants.Size`) so
/// icons never grow unbounded on large displays like iPad.
enum AppIconLayout {
    /// Fewest grid columns, so phones keep the familiar two-up layout even when
    /// a single column could technically be wider.
    private static let minGridColumns = 2
    /// Target grid thumbnail edge used to decide how many columns fit. The
    /// realized size flexes around this and is capped at `appIconGridMax`.
    private static let idealGridIcon: CGFloat = 150

    /// Fractions of the container the large preview may occupy before the cap
    /// applies. Width leaves side margins; height leaves room for the small
    /// preview, the captions, and the appearance picker below.
    private static let previewLargeWidthFraction: CGFloat = 0.62
    private static let previewLargeHeightFraction: CGFloat = 0.4
    /// The small preview is a fraction of the large one so the size contrast
    /// reads clearly. Because the large size is already capped, this is too.
    private static let previewSmallRatio: CGFloat = 0.36

    /// Column count and per-thumbnail edge for the picker grid at `width`.
    static func gridMetrics(containerWidth width: CGFloat) -> AppIconGridMetrics {
        let spacing = UIConstants.Spacings.xxLarge
        let available = max(width - spacing * 2, 0)
        let columnsThatFit = Int((available + spacing) / (idealGridIcon + spacing))
        let columnCount = max(minGridColumns, columnsThatFit)
        let columnWidth = (available - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let iconSize = min(max(columnWidth, 0), UIConstants.Size.appIconGridMax)
        return AppIconGridMetrics(columnCount: columnCount, iconSize: iconSize)
    }

    /// Large and small preview edges for the full-screen preview at `size`.
    static func previewMetrics(containerSize size: CGSize) -> AppIconPreviewMetrics {
        let large = min(
            size.width * previewLargeWidthFraction,
            size.height * previewLargeHeightFraction,
            UIConstants.Size.appIconPreviewLargeMax,
        )
        let clampedLarge = max(large, 0)
        return AppIconPreviewMetrics(large: clampedLarge, small: clampedLarge * previewSmallRatio)
    }
}

/// Column count and per-thumbnail edge for the picker grid at a given width.
struct AppIconGridMetrics: Equatable {
    let columnCount: Int
    let iconSize: CGFloat
}

/// Large and small icon edges for the full-screen preview at a given size.
struct AppIconPreviewMetrics: Equatable {
    let large: CGFloat
    let small: CGFloat
}
