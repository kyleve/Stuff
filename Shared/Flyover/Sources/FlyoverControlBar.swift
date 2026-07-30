import SwiftUI

/// Session-only controls that change the presentation traits of every frame.
struct FlyoverControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: stylesheet.controlBar.wideSpacing) {
                FlyoverViewModePicker(model: model)
                    .frame(width: stylesheet.controlBar.wideViewModeWidth)
                FlyoverZoomSlider(model: model)
                    .frame(width: stylesheet.controlBar.wideZoomWidth)
                FlyoverViewportMenu(model: model)
                FlyoverAppearanceMenu(model: model)
                Button(
                    "Reset All",
                    systemImage: "arrow.counterclockwise",
                    action: resetAll,
                )
            }

            FlyoverCompactControlBar(catalog: catalog, model: model)
        }
        .padding(.horizontal, stylesheet.controlBar.horizontalPadding)
        .padding(.vertical, stylesheet.controlBar.verticalPadding)
        .flyoverBarSurface()
    }

    private func resetAll() {
        model.resetAll(catalog)
    }
}
