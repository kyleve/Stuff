import RegionKit
import SwiftUI

/// Moves ranked Location cards between measured vertical positions without
/// changing their semantic source order.
struct LocationCardRankingLayout: Layout {
    /// Identifies a child by its domain region instead of its structural slot.
    /// Primary rankings never contain `.other`, so it is a safe missing-key
    /// sentinel for this layout.
    struct RegionLayoutValueKey: LayoutValueKey {
        static let defaultValue = Region.other
    }

    /// One card's identity and measured size, kept together so unequal card
    /// heights cannot drift away from their regions during interpolation.
    struct MeasuredChild: Equatable {
        let region: Region
        let size: CGSize
    }

    let spacing: CGFloat
    let fromOrder: [Region]
    let toOrder: [Region]
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGSize {
        let children = measuredChildren(proposal: proposal, subviews: subviews)
        return CGSize(
            width: children.map(\.size.width).max() ?? 0,
            height: Self.stackHeight(children: children, spacing: spacing),
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) {
        let childProposal = ProposedViewSize(width: bounds.width, height: nil)
        let children = measuredChildren(proposal: childProposal, subviews: subviews)
        let yOrigins = Self.interpolatedYOrigins(
            children: children,
            spacing: spacing,
            fromOrder: fromOrder,
            toOrder: toOrder,
            progress: progress,
        )

        // Iterate the unchanged source collection. Only each child's visual
        // origin moves, so VoiceOver and focus follow the caller's rank order.
        for (index, subview) in subviews.enumerated() {
            let size = children[index].size
            subview.place(
                at: CGPoint(
                    x: bounds.midX - size.width / 2,
                    y: bounds.minY + yOrigins[index],
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(size),
            )
        }
    }

    /// Returns one y-origin for each child in the original semantic order.
    /// The two endpoint orders use the same measured region heights.
    static func interpolatedYOrigins(
        children: [MeasuredChild],
        spacing: CGFloat,
        fromOrder: [Region],
        toOrder: [Region],
        progress: CGFloat,
    ) -> [CGFloat] {
        let semanticOrder = children.map(\.region)
        assert(Set(semanticOrder).count == semanticOrder.count)

        let heights = Dictionary(
            children.map { ($0.region, $0.size.height) },
            uniquingKeysWith: { first, _ in first },
        )
        let sourceOrder = normalizedOrder(fromOrder, fallback: semanticOrder)
        let destinationOrder = normalizedOrder(toOrder, fallback: semanticOrder)
        let sourceOrigins = origins(order: sourceOrder, heights: heights, spacing: spacing)
        let destinationOrigins = origins(
            order: destinationOrder,
            heights: heights,
            spacing: spacing,
        )

        return semanticOrder.map { region in
            let source = sourceOrigins[region] ?? 0
            let destination = destinationOrigins[region] ?? source
            return source + (destination - source) * progress
        }
    }

    private static func normalizedOrder(
        _ preferred: [Region],
        fallback: [Region],
    ) -> [Region] {
        let available = Set(fallback)
        var included: Set<Region> = []
        var result: [Region] = []

        for region in preferred
            where available.contains(region) && included.insert(region).inserted
        {
            result.append(region)
        }
        for region in fallback where included.insert(region).inserted {
            result.append(region)
        }
        return result
    }

    private static func origins(
        order: [Region],
        heights: [Region: CGFloat],
        spacing: CGFloat,
    ) -> [Region: CGFloat] {
        var result: [Region: CGFloat] = [:]
        var nextY: CGFloat = 0

        for (index, region) in order.enumerated() {
            result[region] = nextY
            nextY += heights[region] ?? 0
            if index < order.count - 1 {
                nextY += spacing
            }
        }
        return result
    }

    private static func stackHeight(
        children: [MeasuredChild],
        spacing: CGFloat,
    ) -> CGFloat {
        let gaps = max(0, children.count - 1)
        return children.reduce(0) { $0 + $1.size.height } + CGFloat(gaps) * spacing
    }

    private func measuredChildren(
        proposal: ProposedViewSize,
        subviews: Subviews,
    ) -> [MeasuredChild] {
        subviews.map { subview in
            MeasuredChild(
                region: subview[RegionLayoutValueKey.self],
                size: subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)),
            )
        }
    }
}

extension View {
    /// Gives a ranked-card layout child a stable domain identity.
    func locationCardRankingRegion(_ region: Region) -> some View {
        layoutValue(key: LocationCardRankingLayout.RegionLayoutValueKey.self, value: region)
    }
}
