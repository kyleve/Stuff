import CoreGraphics

/// A square lattice of regions interleaved with rosettes on the half-step diagonals.
enum LocationsBackgroundLayout {
    enum Motif: Equatable {
        case region(Int)
        case rosette
    }

    struct Cell: Identifiable {
        let id: Int
        let motif: Motif
        let frame: CGRect
    }

    static func cells(count: Int, in size: CGSize, preferredCellSize: CGFloat) -> [Cell] {
        guard count >= 0, size.width > 0, size.height > 0, preferredCellSize > 0 else {
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
        let side = min(size.width / CGFloat(columns), size.height / CGFloat(rows))
        let visibleColumns = max(1, Int((size.width / side).rounded(.down)))
        let coveringColumns = Int((size.width / side).rounded(.up))
        let coveringRows = Int((size.height / side).rounded(.up))
        var cells: [Cell] = []
        // Overscan every edge so both halves of the diagonal repeat can be clipped naturally.
        for row in -1 ... coveringRows {
            for column in -1 ... coveringColumns {
                let frame = CGRect(
                    x: CGFloat(column) * side,
                    y: CGFloat(row) * side,
                    width: side,
                    height: side,
                )
                if count > 0 {
                    let index = row * visibleColumns + column
                    cells.append(Cell(
                        id: cells.count,
                        motif: .region((index % count + count) % count),
                        frame: frame,
                    ))
                }
                cells.append(Cell(
                    id: cells.count,
                    motif: .rosette,
                    frame: frame.offsetBy(dx: side / 2, dy: side / 2),
                ))
            }
        }
        return cells
    }
}
