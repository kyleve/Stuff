import SwiftUI

/// A developer browser for every registered state and navigation relationship in an app.
public struct FlyoverView<ScreenID: Hashable>: View {
    private let catalog: FlyoverCatalog<ScreenID>
    @State private var model: FlyoverModel<ScreenID>

    public init(catalog: FlyoverCatalog<ScreenID>) {
        self.catalog = catalog
        _model = State(initialValue: FlyoverModel(catalog: catalog))
    }

    public var body: some View {
        @Bindable var model = model

        Group {
            if catalog.isValid {
                FlyoverOverview(catalog: catalog, model: model)
            } else {
                ContentUnavailableView(
                    "Invalid Flyover Catalog",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "\(catalog.validationIssues.count) structural issue(s) must be fixed.",
                    ),
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if catalog.isValid {
                FlyoverControlBar(catalog: catalog, model: model)
            }
        }
        .fullScreenCover(item: $model.focusedSelection) { selection in
            if let screen = catalog.screen(id: selection.id) {
                FlyoverFocusedView(screen: screen, model: model)
            }
        }
    }
}
