import CoreGraphics

/// Resolves bounded canvas zoom levels for width-first and whole-graph framing.
struct FlyoverCanvasZoomPlan {
    let canvasSize: CGSize
    let availableSize: CGSize

    var widthZoom: Double {
        clamped(horizontalScale)
    }

    var allZoom: Double {
        clamped(min(horizontalScale, verticalScale))
    }

    private var horizontalScale: Double {
        Double(max(availableSize.width - 32, 1) / max(canvasSize.width, 1))
    }

    private var verticalScale: Double {
        Double(max(availableSize.height - 32, 1) / max(canvasSize.height, 1))
    }

    private func clamped(_ zoom: Double) -> Double {
        min(max(zoom, 0.15), 1)
    }
}
