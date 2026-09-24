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
        // Half a cell of extra horizontal space keeps staggered rows inside the viewport.
        let width = size.width / (CGFloat(columns) + 0.5)
        let height = size.height / CGFloat(rows)
        return (0 ..< columns * rows).map { index in
            let row = index / columns
            let column = index % columns
            return Cell(
                id: index,
                artworkIndex: index % count,
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
