import CoreGraphics

/// A staggered region lattice that preserves full membership and extends beyond the viewport.
enum LocationsBackgroundLayout {
    struct Cell: Identifiable {
        let id: Int
        let artworkIndex: Int
        let frame: CGRect
    }

    static func cells(count: Int, in size: CGSize, preferredCellSize: CGFloat) -> [Cell] {
        guard count > 0, size.width > 0, size.height > 0, preferredCellSize > 0 else {
            return []
        }
        var columns = max(1, Int(size.width / preferredCellSize))
        var rows = max(1, Int(size.height / preferredCellSize))
        while columns * rows < count {
            if size.width / CGFloat(columns + 1) > size.height / CGFloat(rows + 1) {
                columns += 1
            } else {
                rows += 1
            }
        }
        let side = min(size.width / (CGFloat(columns) + 0.5), size.height / CGFloat(rows))
        let coveringColumns = Int((size.width / side).rounded(.up))
        let coveringRows = Int((size.height / side).rounded(.up))
        var cells: [Cell] = []
        // Overscan every edge so the repeat can be clipped naturally.
        for row in -1 ... coveringRows {
            for column in -1 ... coveringColumns {
                let frame = CGRect(
                    x: (CGFloat(column) + (row.isMultiple(of: 2) ? 0 : 0.5)) * side,
                    y: CGFloat(row) * side,
                    width: side,
                    height: side,
                )
                let index = row * columns + column
                cells.append(Cell(
                    id: cells.count,
                    artworkIndex: (index % count + count) % count,
                    frame: frame,
                ))
            }
        }
        return cells
    }
}
