import CoreGraphics

/// Places catalog groups horizontally and their screens by graph depth.
@MainActor
struct FlyoverLayout<ScreenID: Hashable> {
    let catalog: FlyoverCatalog<ScreenID>
    let style: FlyoverStylesheet.LayoutStyle

    func resolve() -> FlyoverLayoutResult<ScreenID> {
        let card = style.cardSize
        var screenFrames: [ScreenID: CGRect] = [:]
        var groupFrames: [FlyoverGroupID: CGRect] = [:]
        var groupOriginX = style.canvasPadding
        var maximumHeight: CGFloat = 0
        var initialCanvasSize: CGSize?

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
            let groupWidth = style.groupPadding * 2
                + CGFloat(maximumColumn + 1) * card.width
                + CGFloat(maximumColumn) * style.horizontalSpacing
            let groupHeight = style.groupPadding * 2
                + CGFloat(maximumRow + 1) * card.height
                + CGFloat(maximumRow) * style.verticalSpacing
                + style.groupHeaderHeight
            let groupFrame = CGRect(
                x: groupOriginX,
                y: style.canvasPadding,
                width: groupWidth,
                height: groupHeight,
            )
            groupFrames[group.id] = groupFrame
            if initialCanvasSize == nil {
                initialCanvasSize = CGSize(
                    width: groupFrame.maxX + style.canvasPadding,
                    height: groupFrame.maxY + style.canvasPadding,
                )
            }

            for screen in group.screens {
                guard let position = resolvedPositions[screen.id] else {
                    continue
                }
                let origin = CGPoint(
                    x: groupFrame.minX + style.groupPadding
                        + CGFloat(position.column) * (card.width + style.horizontalSpacing),
                    y: groupFrame.minY + style.groupPadding + style.groupHeaderHeight
                        + CGFloat(position.row) * (card.height + style.verticalSpacing),
                )
                screenFrames[screen.id] = CGRect(origin: origin, size: card)
            }

            maximumHeight = max(maximumHeight, groupFrame.maxY)
            groupOriginX = groupFrame.maxX + style.groupSpacing
        }

        guard let initialCanvasSize else {
            preconditionFailure("A Flyover layout requires at least one group.")
        }

        return FlyoverLayoutResult(
            screenFrames: screenFrames,
            groupFrames: groupFrames,
            initialCanvasSize: initialCanvasSize,
            canvasSize: CGSize(
                width: max(groupOriginX - style.groupSpacing + style.canvasPadding, 1),
                height: maximumHeight + style.canvasPadding,
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
