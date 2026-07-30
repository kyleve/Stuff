import SwiftUI

/// Session-only controls that change the presentation traits of every frame.
struct FlyoverControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                FlyoverViewModePicker(model: model)
                    .frame(width: 220)
                FlyoverZoomSlider(model: model)
                    .frame(width: 240)
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
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func resetAll() {
        model.resetAll(catalog)
    }
}
