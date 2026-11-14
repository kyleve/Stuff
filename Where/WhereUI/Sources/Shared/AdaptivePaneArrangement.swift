import CoreGraphics

/// Chooses a layout from available space and active reserved regions, without device or angle
/// checks.
enum AdaptivePaneArrangement: Equatable {
    struct Panes: Equatable {
        var detail: CGRect
        var controls: CGRect
    }

    case compact
    case columns
    case tabletop(Panes)

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
        if let division = divisions.first(where: { $0.frame.width > $0.frame.height }) {
            let gap = division.frame.intersection(content)
            let detail = avoidingOcclusions(
                CGRect(
                    x: content.minX,
                    y: content.minY,
                    width: content.width,
                    height: max(0, gap.minY - content.minY),
                ),
                geometry: geometry,
            )
            let controls = avoidingOcclusions(
                CGRect(
                    x: content.minX,
                    y: gap.maxY,
                    width: content.width,
                    height: max(0, content.maxY - gap.maxY),
                ),
                geometry: geometry,
            )
            guard detail.height >= style.minimumPaneHeight,
                  controls.height >= style.minimumPaneHeight,
                  detail.width >= style.minimumDetailWidth,
                  controls.width >= style.minimumControlsWidth
            else { return .compact }
            return .tabletop(Panes(detail: detail, controls: controls))
        }

        if let division = divisions.first {
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

    /// A rectangular pane uses the largest clear rectangle around an occlusion.
    /// Edge occlusions already outside the content safe area do not reduce it again.
    private static func avoidingOcclusions(
        _ pane: CGRect,
        geometry: AdaptivePaneGeometry,
    ) -> CGRect {
        geometry.regions.reduce(pane) { available, region in
            guard region.isActive, region.kind == .occlusion,
                  available.intersects(region.frame)
            else { return available }
            let blocked = available.intersection(region.frame)
            let above = CGRect(
                x: available.minX,
                y: available.minY,
                width: available.width,
                height: max(0, blocked.minY - available.minY),
            )
            return [
                CGRect(
                    x: available.minX,
                    y: blocked.maxY,
                    width: available.width,
                    height: max(0, available.maxY - blocked.maxY),
                ),
                CGRect(
                    x: available.minX,
                    y: available.minY,
                    width: max(0, blocked.minX - available.minX),
                    height: available.height,
                ),
                CGRect(
                    x: blocked.maxX,
                    y: available.minY,
                    width: max(0, available.maxX - blocked.maxX),
                    height: available.height,
                ),
            ].reduce(above) { largest, candidate in
                candidate.width * candidate.height > largest.width * largest.height
                    ? candidate : largest
            }
        }
    }
}
