import BroadwayCore
import Observation

/// Session state shared by a screen's overview card and focused inspector.
@MainActor
@Observable
final class FlyoverFrameState {
    var variantID: FlyoverVariantID
    var resetTrigger = EventTrigger()

    init(variantID: FlyoverVariantID) {
        self.variantID = variantID
    }
}
