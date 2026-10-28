import SwiftUI

/// Switches between Flyover's graph canvas and linear list.
struct FlyoverOverview<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        switch model.viewMode {
            case .canvas:
                FlyoverCanvasView(catalog: catalog, model: model)
            case .list:
                FlyoverListView(catalog: catalog, model: model)
        }
    }
}
