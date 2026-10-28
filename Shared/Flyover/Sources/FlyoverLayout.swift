import CoreGraphics

/// Places catalog groups horizontally and their screens by graph depth.
@MainActor
struct FlyoverLayout<ScreenID: Hashable> {
    let catalog: FlyoverCatalog<ScreenID>
    let style: FlyoverStylesheet.LayoutStyle

    func resolve() -> FlyoverLayoutResult<ScreenID> {
        precondition(
            style.maximumAutomaticRowsPerColumn > 0,
            "A Flyover automatic column must allow at least one row.",
        )

        let card = style.cardSize
        var screenFrames: [ScreenID: CGRect] = [:]
        var groupFrames: [FlyoverGroupID: CGRect] = [:]
        var depthBands: [FlyoverDepthBand] = []
        var groupOriginX = style.canvasPadding
        var maximumHeight: CGFloat = 0
        var initialCanvasSize: CGSize?

        for group in catalog.groups {
            let depths = graphDepths(in: group)
            let unlinkedDepth = (depths.values.max() ?? 0) + 1
            var occupied = Set<FlyoverPosition>()
            for screen in group.screens {
                if let position = screen.position {
                    occupied.insert(position)
                }
            }
            var resolvedPositions: [ScreenID: FlyoverPosition] = [:]

            for screen in group.screens {
                if let position = screen.position {
                    resolvedPositions[screen.id] = position
                }
            }

            let automaticScreens = Dictionary(
                grouping: group.screens.filter { $0.position == nil },
                by: { depths[$0.id] ?? unlinkedDepth },
            )
            var depthColumnRanges: [Int: ClosedRange<Int>] = [:]
            var nextAutomaticColumn = 0

            for depth in automaticScreens.keys.sorted() {
                guard let screens = automaticScreens[depth] else {
                    continue
                }

                var column = max(depth, nextAutomaticColumn)
                let firstColumn = column
                var row = 0

                for screen in screens {
                    while true {
                        if row == style.maximumAutomaticRowsPerColumn {
                            column += 1
                            row = 0
                        }

                        let position = FlyoverPosition(column: column, row: row)
                        row += 1
                        guard occupied.insert(position).inserted else {
                            continue
                        }

                        resolvedPositions[screen.id] = position
                        break
                    }
                }

                depthColumnRanges[depth] = firstColumn ... column
                nextAutomaticColumn = column + 1
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
            for depth in depthColumnRanges.keys.sorted() {
                guard let columns = depthColumnRanges[depth] else {
                    continue
                }
                let firstCardX = groupFrame.minX + style.groupPadding
                    + CGFloat(columns.lowerBound) * (card.width + style.horizontalSpacing)
                let lastCardMaxX = groupFrame.minX + style.groupPadding
                    + CGFloat(columns.upperBound) * (card.width + style.horizontalSpacing)
                    + card.width
                let frame = CGRect(
                    x: firstCardX - style.depthBandHorizontalInset,
                    y: groupFrame.minY + style.groupHeaderHeight + style.depthBandTopInset,
                    width: lastCardMaxX - firstCardX + style.depthBandHorizontalInset * 2,
                    height: groupFrame.height
                        - style.groupHeaderHeight
                        - style.depthBandTopInset
                        - style.depthBandBottomInset,
                )
                depthBands.append(FlyoverDepthBand(
                    id: FlyoverDepthBand.ID(
                        group: group.id,
                        kind: depth == unlinkedDepth ? .unlinked : .route(depth: depth),
                    ),
                    frame: frame,
                ))
            }
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
            depthBands: depthBands,
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

        return depths
    }
}
