import CoreGraphics

/// Fits every silhouette in separate cells without increasing the card height.
/// The largest square-cell grid wins; incomplete final rows are centered.
enum ElsewhereArtworkLayout {
    static func frames(count: Int, in size: CGSize, gap: CGFloat) -> [CGRect] {
        guard count > 0, size.width > 0, size.height > 0 else { return [] }
        var columns = 1
        var bestSide: CGFloat = 0
        for candidate in 1 ... count {
            let rows = (count + candidate - 1) / candidate
            let side = min(size.width / CGFloat(candidate), size.height / CGFloat(rows))
            if side > bestSide {
                bestSide = side
                columns = candidate
            }
        }
        let rows = (count + columns - 1) / columns
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)
        let inset = min(max(0, gap) / 2, bestSide / 4)
        return (0 ..< count).map { index in
            let row = index / columns
            let column = index % columns
            let rowCount = min(columns, count - row * columns)
            let startX = (size.width - CGFloat(rowCount) * cellWidth) / 2
            return CGRect(
                x: startX + CGFloat(column) * cellWidth + inset,
                y: CGFloat(row) * cellHeight + inset,
                width: cellWidth - inset * 2,
                height: cellHeight - inset * 2,
            )
        }
    }
}
