import Observation

/// Session state shared by a screen's overview card and focused inspector.
@MainActor
@Observable
final class FlyoverFrameState {
    var variantID: FlyoverVariantID
    var generation = 0

    init(variantID: FlyoverVariantID) {
        self.variantID = variantID
    }
}
