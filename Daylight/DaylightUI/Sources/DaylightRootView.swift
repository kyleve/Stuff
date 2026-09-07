import BroadwayUI
import SwiftUI

public struct DaylightRootView: View {
    @State private var model: DaylightModel
    @Environment(\.scenePhase) private var scenePhase
    public init(model: DaylightModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        DaylightContentView(model: model)
            .broadwayRoot()
            .background { DaylightScreenConnection(connect: model.attachScreen) }
            .task(id: scenePhase) { await model.run(active: scenePhase == .active) }
    }
}

#if DEBUG
    #Preview { DaylightContentView(model: DaylightPreviewSupport.model()).broadwayRoot() }
#endif
