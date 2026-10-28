import CoreGraphics
import SwiftUI

/// Reduces a year's raw projected GPS fixes to a stable, spatially distributed
/// constellation suitable for a small card silhouette.
enum RegionLocationConstellationLayout {
    struct Point: Hashable {
        let position: CGPoint
        let horizontalAccuracy: Double
    }

    private struct Cell: Hashable, Comparable {
        let row: Int
        let column: Int

        static func < (lhs: Cell, rhs: Cell) -> Bool {
            if lhs.row != rhs.row { return lhs.row < rhs.row }
            return lhs.column < rhs.column
        }
    }

    private struct Candidate {
        var point: Point
        var sampleCount: Int
    }

    /// Keeps the most accurate fix per visual cell. If the constellation still
    /// exceeds its cap, frequently sampled cells win and ties follow geography
    /// (top-to-bottom, then leading-to-trailing) for deterministic snapshots.
    static func selectedPoints(
        from points: [Point],
        inside path: Path,
        gridResolution: Int,
        maximumCount: Int,
    ) -> [Point] {
        let bounds = path.boundingRect
        guard
            points.isEmpty == false,
            bounds.width > 0,
            bounds.height > 0,
            gridResolution > 0,
            maximumCount > 0
        else { return [] }

        var candidates: [Cell: Candidate] = [:]
        for point in points where path.contains(point.position) {
            let normalizedX = (point.position.x - bounds.minX) / bounds.width
            let normalizedY = (point.position.y - bounds.minY) / bounds.height
            let cell = Cell(
                row: min(gridResolution - 1, max(0, Int(normalizedY * CGFloat(gridResolution)))),
                column: min(
                    gridResolution - 1,
                    max(0, Int(normalizedX * CGFloat(gridResolution))),
                ),
            )
            if var candidate = candidates[cell] {
                candidate.sampleCount += 1
                if point.horizontalAccuracy < candidate.point.horizontalAccuracy {
                    candidate.point = point
                }
                candidates[cell] = candidate
            } else {
                candidates[cell] = Candidate(point: point, sampleCount: 1)
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.value.sampleCount != rhs.value.sampleCount {
                    return lhs.value.sampleCount > rhs.value.sampleCount
                }
                return lhs.key < rhs.key
            }
            .prefix(maximumCount)
            .map(\.value.point)
    }
}
