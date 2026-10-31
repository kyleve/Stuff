import CoreGraphics
import SwiftUI

/// Container geometry in one coordinate space. Insets belong to independent physical edges.
/// Reserved-region frames already include the system's margins.
struct AdaptiveHistoryGeometry: Equatable {
    struct Insets: Equatable {
        var top: CGFloat
        var left: CGFloat
        var bottom: CGFloat
        var right: CGFloat

        static let zero = Self(top: 0, left: 0, bottom: 0, right: 0)
    }

    struct Region: Equatable {
        enum Kind: Equatable {
            case division
            case occlusion
        }

        var kind: Kind
        var frame: CGRect
        var isActive: Bool
    }

    var bounds: CGRect
    var insets: Insets
    var regions: [Region]
    var layoutDirection: LayoutDirection

    var contentBounds: CGRect {
        CGRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom),
        )
    }

    /// A custom floating surface occupies one clear rectangle nearest its preferred point.
    /// Division margins and camera regions are removed before choosing that rectangle.
    func unobstructedBounds(near point: CGPoint) -> CGRect {
        var candidates = [contentBounds]
        for region in regions where region.isActive {
            candidates = candidates.flatMap { area -> [CGRect] in
                guard area.intersects(region.frame) else { return [area] }
                let gap = area.intersection(region.frame)
                return [
                    CGRect(
                        x: area.minX,
                        y: area.minY,
                        width: area.width,
                        height: gap.minY - area.minY,
                    ),
                    CGRect(
                        x: area.minX,
                        y: gap.maxY,
                        width: area.width,
                        height: area.maxY - gap.maxY,
                    ),
                    CGRect(
                        x: area.minX,
                        y: area.minY,
                        width: gap.minX - area.minX,
                        height: area.height,
                    ),
                    CGRect(
                        x: gap.maxX,
                        y: area.minY,
                        width: area.maxX - gap.maxX,
                        height: area.height,
                    ),
                ].filter { $0.width > 0 && $0.height > 0 }
            }
        }
        func distance(to area: CGRect) -> CGFloat {
            let x = max(area.minX - point.x, 0, point.x - area.maxX)
            let y = max(area.minY - point.y, 0, point.y - area.maxY)
            return x * x + y * y
        }
        return candidates.min { left, right in
            let leftDistance = distance(to: left)
            let rightDistance = distance(to: right)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            return left.width * left.height > right.width * right.height
        } ?? .zero
    }

    /// GeometryReader proposes the safe content area. Expand it to the container's
    /// bounds without subtracting its safe-area insets a second time.
    init(proxy: GeometryProxy, layoutDirection: LayoutDirection) {
        self.layoutDirection = layoutDirection
        let safeArea = proxy.safeAreaInsets
        insets = Insets(
            top: safeArea.top,
            left: layoutDirection == .leftToRight ? safeArea.leading : safeArea.trailing,
            bottom: safeArea.bottom,
            right: layoutDirection == .leftToRight ? safeArea.trailing : safeArea.leading,
        )
        bounds = CGRect(
            x: -insets.left,
            y: -insets.top,
            width: proxy.size.width + insets.left + insets.right,
            height: proxy.size.height + insets.top + insets.bottom,
        )
        regions = proxy.reservedRegions(
            kind: .division,
            options: .includeInactive,
            layoutDirectionBehavior: .fixed,
        )
        .map { Region(kind: .division, frame: $0.frame, isActive: $0.isActive) }
        regions += proxy.reservedRegions(
            kind: .occlusion,
            options: .includeInactive,
            layoutDirectionBehavior: .fixed,
        )
        .map { Region(kind: .occlusion, frame: $0.frame, isActive: $0.isActive) }
    }

    init(bounds: CGRect, insets: Insets, regions: [Region], layoutDirection: LayoutDirection) {
        self.bounds = bounds
        self.insets = insets
        self.regions = regions
        self.layoutDirection = layoutDirection
    }
}
