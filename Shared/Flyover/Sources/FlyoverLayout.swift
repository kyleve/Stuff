import CoreGraphics

/// Places catalog screens by graph depth while preserving registration order.
@MainActor
struct FlyoverLayout<ScreenID: Hashable> {
    static var cardSize: CGSize {
        CGSize(width: 300, height: 650)
    }

    let catalog: FlyoverCatalog<ScreenID>

    func resolve() -> FlyoverLayoutResult<ScreenID> {
        let card = Self.cardSize
        let horizontalSpacing: CGFloat = 100
        let verticalSpacing: CGFloat = 90
        let groupPadding: CGFloat = 60
        let groupSpacing: CGFloat = 120
        var screenFrames: [ScreenID: CGRect] = [:]
        var groupFrames: [FlyoverGroupID: CGRect] = [:]
        var groupOriginY: CGFloat = 40
        var maximumWidth: CGFloat = 0

        for group in catalog.groups {
            let depths = graphDepths(in: group)
            var occupied = Set<FlyoverPosition>()
            for screen in group.screens {
                if let position = screen.position {
                    occupied.insert(position)
                }
            }
            var nextRows: [Int: Int] = [:]
            var resolvedPositions: [ScreenID: FlyoverPosition] = [:]

            for screen in group.screens {
                if let position = screen.position {
                    resolvedPositions[screen.id] = position
                    nextRows[position.column] = max(
                        nextRows[position.column, default: 0],
                        position.row + 1,
                    )
                    continue
                }

                let column = depths[screen.id, default: 0]
                var row = nextRows[column, default: 0]
                while occupied.contains(FlyoverPosition(column: column, row: row)) {
                    row += 1
                }
                let position = FlyoverPosition(column: column, row: row)
                occupied.insert(position)
                resolvedPositions[screen.id] = position
                nextRows[column] = row + 1
            }

            let maximumColumn = resolvedPositions.values.map(\.column).max() ?? 0
            let maximumRow = resolvedPositions.values.map(\.row).max() ?? 0
            let groupWidth = groupPadding * 2
                + CGFloat(maximumColumn + 1) * card.width
                + CGFloat(maximumColumn) * horizontalSpacing
            let groupHeight = groupPadding * 2
                + CGFloat(maximumRow + 1) * card.height
                + CGFloat(maximumRow) * verticalSpacing
                + 44
            let groupFrame = CGRect(
                x: 40,
                y: groupOriginY,
                width: groupWidth,
                height: groupHeight,
            )
            groupFrames[group.id] = groupFrame

            for screen in group.screens {
                guard let position = resolvedPositions[screen.id] else {
                    continue
                }
                let origin = CGPoint(
                    x: groupFrame.minX + groupPadding
                        + CGFloat(position.column) * (card.width + horizontalSpacing),
                    y: groupFrame.minY + groupPadding + 44
                        + CGFloat(position.row) * (card.height + verticalSpacing),
                )
                screenFrames[screen.id] = CGRect(origin: origin, size: card)
            }

            maximumWidth = max(maximumWidth, groupFrame.maxX)
            groupOriginY = groupFrame.maxY + groupSpacing
        }

        return FlyoverLayoutResult(
            screenFrames: screenFrames,
            groupFrames: groupFrames,
            canvasSize: CGSize(
                width: maximumWidth + 40,
                height: max(groupOriginY - groupSpacing + 40, 1),
            ),
        )
    }

    private func graphDepths(in group: FlyoverGroup<ScreenID>) -> [ScreenID: Int] {
        let ids = Set(group.screens.map(\.id))
        var depths: [ScreenID: Int] = [group.root: 0]
        var frontier = [group.root]

        while frontier.isEmpty == false {
            let source = frontier.removeFirst()
            let nextDepth = depths[source, default: 0] + 1
            for transition in catalog.transitions
                where transition.source == source && ids.contains(transition.destination)
            {
                if depths[transition.destination] == nil {
                    depths[transition.destination] = nextDepth
                    frontier.append(transition.destination)
                }
            }
        }

        let disconnectedDepth = (depths.values.max() ?? 0) + 1
        for screen in group.screens where depths[screen.id] == nil {
            depths[screen.id] = disconnectedDepth
        }
        return depths
    }
}
