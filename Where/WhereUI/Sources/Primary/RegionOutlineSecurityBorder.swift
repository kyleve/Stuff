import RegionKit
import SwiftUI

/// Repeats cached micro-fidelity region silhouettes around an inset rounded
/// perimeter, like the microprinted security border on a passport page.
struct RegionOutlineSecurityBorder: View {
    let paths: [Path]
    let tint: Color
    let cornerRadius: CGFloat
    let inset: CGFloat
    let glyphSize: CGFloat
    let spacing: CGFloat
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            let artwork = paths.compactMap { path -> Artwork? in
                let bounds = path.boundingRect
                guard !path.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
                return Artwork(
                    path: path,
                    bounds: bounds,
                    scale: min(glyphSize / bounds.width, glyphSize / bounds.height),
                )
            }
            guard !artwork.isEmpty else { return }

            for (index, placement) in Self.placements(
                in: size,
                cornerRadius: cornerRadius,
                inset: inset,
                spacing: spacing,
            ).enumerated() {
                guard let artworkIndex = Self.artworkIndex(
                    at: index,
                    artworkCount: artwork.count,
                ) else { continue }
                let item = artwork[artworkIndex]
                var stamp = context
                stamp.translateBy(x: placement.center.x, y: placement.center.y)
                stamp.rotate(by: .radians(placement.rotation))
                stamp.scaleBy(x: item.scale, y: item.scale)
                stamp.translateBy(x: -item.bounds.midX, y: -item.bounds.midY)
                stamp.fill(item.path, with: .color(tint.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Evenly spaced tangent-aligned placements around a clockwise rounded
    /// perimeter, starting on its top edge. Kept deterministic for snapshots.
    static func placements(
        in size: CGSize,
        cornerRadius: CGFloat,
        inset: CGFloat,
        spacing: CGFloat,
    ) -> [Placement] {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0, spacing > 0 else { return [] }

        let radius = min(
            max(0, cornerRadius - inset),
            min(rect.width, rect.height) / 2,
        )
        let horizontalLength = max(0, rect.width - radius * 2)
        let verticalLength = max(0, rect.height - radius * 2)
        let cornerLength = .pi * radius / 2
        let perimeter = horizontalLength * 2 + verticalLength * 2 + cornerLength * 4
        guard perimeter > 0 else { return [] }

        let count = max(4, Int(perimeter / spacing))
        var placements: [Placement] = []
        placements.reserveCapacity(count)
        for index in 0 ..< count {
            let distance = perimeter * CGFloat(index) / CGFloat(count)
            placements.append(placement(
                at: distance,
                in: rect,
                radius: radius,
                horizontalLength: horizontalLength,
                verticalLength: verticalLength,
                cornerLength: cornerLength,
            ))
        }
        return placements
    }

    /// Cycles the supplied artwork in its source order around the perimeter.
    static func artworkIndex(at placementIndex: Int, artworkCount: Int) -> Int? {
        guard placementIndex >= 0, artworkCount > 0 else { return nil }
        return placementIndex % artworkCount
    }

    private static func placement(
        at distance: CGFloat,
        in rect: CGRect,
        radius: CGFloat,
        horizontalLength: CGFloat,
        verticalLength: CGFloat,
        cornerLength: CGFloat,
    ) -> Placement {
        var remaining = distance

        if remaining < horizontalLength {
            return Placement(
                center: CGPoint(x: rect.minX + radius + remaining, y: rect.minY),
                rotation: 0,
            )
        }
        remaining -= horizontalLength

        if remaining < cornerLength, radius > 0 {
            return cornerPlacement(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: -.pi / 2,
                distance: remaining,
            )
        }
        remaining -= cornerLength

        if remaining < verticalLength {
            return Placement(
                center: CGPoint(x: rect.maxX, y: rect.minY + radius + remaining),
                rotation: .pi / 2,
            )
        }
        remaining -= verticalLength

        if remaining < cornerLength, radius > 0 {
            return cornerPlacement(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: 0,
                distance: remaining,
            )
        }
        remaining -= cornerLength

        if remaining < horizontalLength {
            return Placement(
                center: CGPoint(x: rect.maxX - radius - remaining, y: rect.maxY),
                rotation: .pi,
            )
        }
        remaining -= horizontalLength

        if remaining < cornerLength, radius > 0 {
            return cornerPlacement(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .pi / 2,
                distance: remaining,
            )
        }
        remaining -= cornerLength

        if remaining < verticalLength {
            return Placement(
                center: CGPoint(x: rect.minX, y: rect.maxY - radius - remaining),
                rotation: -.pi / 2,
            )
        }
        remaining -= verticalLength

        return cornerPlacement(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .pi,
            distance: remaining,
        )
    }

    private static func cornerPlacement(
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        distance: CGFloat,
    ) -> Placement {
        guard radius > 0 else {
            return Placement(center: center, rotation: startAngle + .pi / 2)
        }
        let angle = startAngle + distance / radius
        return Placement(
            center: CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius,
            ),
            rotation: angle + .pi / 2,
        )
    }

    struct Placement: Equatable {
        let center: CGPoint
        let rotation: Double
    }

    private struct Artwork {
        let path: Path
        let bounds: CGRect
        let scale: CGFloat
    }
}

#if DEBUG
    #Preview {
        RegionOutlineSecurityBorderPreview()
            .padding()
    }

    private struct RegionOutlineSecurityBorderPreview: View {
        @State private var path = Path()
        private let cache = RegionOutlinePathCache()

        var body: some View {
            let card = WhereStylesheet.default.card.regular
            if let style = card.regionShape?.securityBorder {
                RegionOutlineSecurityBorder(
                    paths: [path],
                    tint: .orange,
                    cornerRadius: card.cornerRadius,
                    inset: style.inset,
                    glyphSize: style.glyphSize,
                    spacing: style.spacing,
                    opacity: style.opacity,
                )
                .frame(width: 320, height: 180)
                .background(
                    .orange.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: card.cornerRadius),
                )
                .task {
                    path = await cache.path(for: .newYork, resolution: .micro)
                }
            }
        }
    }
#endif
