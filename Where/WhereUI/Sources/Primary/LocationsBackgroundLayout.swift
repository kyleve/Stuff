import CoreGraphics

/// A staggered field that repeats small sets and fits every member of large sets.
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
        // Keep every original cell fully visible, then extend the repeat past both edges.
        let width = size.width / (CGFloat(columns) + 0.5)
        let height = size.height / CGFloat(rows)
        return (0 ..< rows).flatMap { row in
            (-1 ... columns).map { column in
                let index = row * columns + column
                return Cell(
                    id: row * (columns + 2) + column + 1,
                    artworkIndex: (index % count + count) % count,
                    frame: CGRect(
                        x: (CGFloat(column) + (row.isMultiple(of: 2) ? 0 : 0.5)) * width,
                        y: CGFloat(row) * height,
                        width: width,
                        height: height,
                    ),
                )
            }
        }
    }
}
