import CoreGraphics

/// Chooses a layout from available space and active reserved regions, without device or angle
/// checks.
enum AdaptivePaneArrangement: Equatable {
    case compact
    case columns

    static func resolve(
        geometry: AdaptivePaneGeometry,
        style: WhereStylesheet.AdaptivePaneStyle,
    ) -> Self {
        guard style.panes == .multiple else { return .compact }
        let content = geometry.contentBounds
        guard content.width >= style.minimumDetailWidth,
              content.height >= style.minimumPaneHeight
        else { return .compact }

        let divisions = geometry.regions.filter {
            $0.isActive && $0.kind == .division && $0.frame.intersects(content)
        }
        guard divisions.count <= 1 else { return .compact }
        if let division = divisions.first(where: { $0.frame.height >= $0.frame.width }) {
            let gap = division.frame.intersection(content)
            let controlsWidth = geometry.layoutDirection == .leftToRight
                ? gap.minX - content.minX : content.maxX - gap.maxX
            let detailWidth = geometry.layoutDirection == .leftToRight
                ? content.maxX - gap.maxX : gap.minX - content.minX
            guard controlsWidth >= style.minimumControlsWidth,
                  detailWidth >= style.minimumDetailWidth
            else { return .compact }
        } else {
            guard content.width >= style.minimumControlsWidth + style.minimumDetailWidth
            else { return .compact }
        }
        return .columns
    }
}
