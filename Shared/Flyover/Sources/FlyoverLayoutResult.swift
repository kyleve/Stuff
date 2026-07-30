import CoreGraphics

/// The deterministic geometry produced for one Flyover canvas.
struct FlyoverLayoutResult<ScreenID: Hashable> {
    let screenFrames: [ScreenID: CGRect]
    let groupFrames: [FlyoverGroupID: CGRect]
    let canvasSize: CGSize
}
