import CoreGraphics

/// Limits expensive live screen trees while preserving a complete canvas.
struct FlyoverCanvasRenderPlan<ScreenID: Hashable> {
    static var maximumLiveScreenCount: Int {
        6
    }

    let zoom: Double
    let visibleRect: CGRect
    let screenFrames: [ScreenID: CGRect]

    var liveScreenIDs: Set<ScreenID> {
        guard visibleRect.isEmpty == false else {
            return []
        }
        let candidates = screenFrames
            .filter { visibleCanvasRect.intersects($0.value) }
            .sorted { lhs, rhs in
                let lhsDistance = squaredDistance(
                    from: lhs.value.center,
                    to: visibleCanvasRect.center,
                )
                let rhsDistance = squaredDistance(
                    from: rhs.value.center,
                    to: visibleCanvasRect.center,
                )
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.value.minY != rhs.value.minY {
                    return lhs.value.minY < rhs.value.minY
                }
                return lhs.value.minX < rhs.value.minX
            }

        return Set(candidates.prefix(Self.maximumLiveScreenCount).map(\.key))
    }

    func shouldDisplay(_ frame: CGRect) -> Bool {
        visibleCanvasRect
            .insetBy(dx: -400, dy: -700)
            .intersects(frame)
    }

    private var visibleCanvasRect: CGRect {
        guard visibleRect.isEmpty == false else {
            return CGRect(x: 0, y: 0, width: 1200, height: 1200)
        }
        let scale = max(zoom, 0.01)
        return CGRect(
            x: visibleRect.minX / scale,
            y: visibleRect.minY / scale,
            width: visibleRect.width / scale,
            height: visibleRect.height / scale,
        )
    }

    private func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let x = lhs.x - rhs.x
        let y = lhs.y - rhs.y
        return x * x + y * y
    }
}

extension CGRect {
    fileprivate var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
