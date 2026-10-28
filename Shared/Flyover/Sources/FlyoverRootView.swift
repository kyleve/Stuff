import SFSafeSymbols
import SwiftUI

/// Flyover's Broadway-rooted content and presentation routing.
struct FlyoverRootView<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        Group {
            if catalog.isValid {
                FlyoverOverview(catalog: catalog, model: model)
            } else {
                ContentUnavailableView(
                    "Invalid Flyover Catalog",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(
                        "\(catalog.validationIssues.count) structural issue(s) must be fixed.",
                    ),
                )
            }
        }
        .background(stylesheet.canvas.background)
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
