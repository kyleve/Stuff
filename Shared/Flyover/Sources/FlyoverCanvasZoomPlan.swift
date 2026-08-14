import CoreGraphics

/// Resolves bounded canvas zoom levels and scroll positions for canvas framing.
struct FlyoverCanvasZoomPlan {
    let canvasSize: CGSize
    let availableSize: CGSize
    let edgeInset: CGFloat

    var widthZoom: Double {
        clamped(horizontalScale)
    }

    var allZoom: Double {
        clamped(min(horizontalScale, verticalScale))
    }

    func contentOffset(
        preservingViewportCenterIn visibleRect: CGRect,
        from oldZoom: Double,
        to newZoom: Double,
    ) -> CGPoint {
        let oldScale = CGFloat(max(oldZoom, 0.01))
        let newScale = CGFloat(max(newZoom, 0.01))
        let canvasCenter = CGPoint(
            x: visibleRect.midX / oldScale,
            y: visibleRect.midY / oldScale,
        )
        let maximumOffset = CGPoint(
            x: max(canvasSize.width * newScale - visibleRect.width, 0),
            y: max(canvasSize.height * newScale - visibleRect.height, 0),
        )

        return CGPoint(
            x: clamped(
                canvasCenter.x * newScale - visibleRect.width / 2,
                maximum: maximumOffset.x,
            ),
            y: clamped(
                canvasCenter.y * newScale - visibleRect.height / 2,
                maximum: maximumOffset.y,
            ),
        )
    }

    private var horizontalScale: Double {
        Double(max(availableSize.width - edgeInset * 2, 1) / max(canvasSize.width, 1))
    }

    private var verticalScale: Double {
        Double(max(availableSize.height - edgeInset * 2, 1) / max(canvasSize.height, 1))
    }

    private func clamped(_ zoom: Double) -> Double {
        min(max(zoom, 0.15), 1)
    }

    private func clamped(_ offset: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(offset, 0), maximum)
    }
}
