import CoreGraphics

/// Partitions graph coordinates into bounded drawing surfaces without gaps or overlaps.
struct FlyoverConnectorTilePlan {
    /// A rendering budget, independent of the graph's appearance or current zoom.
    /// At 3× display scale and the maximum 1.25× zoom, each edge stays below 4096 pixels.
    static let maximumDimension: CGFloat = 1024

    struct Tile: Identifiable, Equatable {
        struct ID: Hashable {
            let column: Int
            let row: Int
        }

        let id: ID
        let frame: CGRect
    }

    let canvasSize: CGSize

    var tiles: [Tile] {
        precondition(canvasSize.width.isFinite && canvasSize.height.isFinite)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return []
        }

        let columns = Int(ceil(canvasSize.width / Self.maximumDimension))
        let rows = Int(ceil(canvasSize.height / Self.maximumDimension))

        return (0 ..< rows).flatMap { row in
            (0 ..< columns).map { column in
                let origin = CGPoint(
                    x: CGFloat(column) * Self.maximumDimension,
                    y: CGFloat(row) * Self.maximumDimension,
                )
                return Tile(
                    id: Tile.ID(column: column, row: row),
                    frame: CGRect(
                        origin: origin,
                        size: CGSize(
                            width: min(Self.maximumDimension, canvasSize.width - origin.x),
                            height: min(Self.maximumDimension, canvasSize.height - origin.y),
                        ),
                    ),
                )
            }
        }
    }
}
