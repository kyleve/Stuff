import BroadwayUI
import SwiftUI

/// A developer browser for every registered state and navigation relationship in an app.
public struct FlyoverView<ScreenID: Hashable>: View {
    private let catalog: FlyoverCatalog<ScreenID>
    @State private var model: FlyoverModel<ScreenID>

    public init(catalog: FlyoverCatalog<ScreenID>) {
        self.catalog = catalog
        _model = State(initialValue: FlyoverModel(catalog: catalog))
    }

    init(catalog: FlyoverCatalog<ScreenID>, model: FlyoverModel<ScreenID>) {
        self.catalog = catalog
        _model = State(initialValue: model)
    }

    public var body: some View {
        FlyoverRootView(catalog: catalog, model: model)
            .broadwayRoot()
    }
}
