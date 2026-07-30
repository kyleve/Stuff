import SwiftUI

/// A width-constrained bottom bar that preserves every global control.
struct FlyoverCompactControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                FlyoverViewModePicker(model: model)
                    .frame(width: 160)
                FlyoverZoomSlider(model: model)
                    .frame(width: 180)
                FlyoverViewportMenu(model: model)
                    .labelStyle(.iconOnly)
                FlyoverAppearanceMenu(model: model)
                    .labelStyle(.iconOnly)
                Button(
                    "Reset All",
                    systemImage: "arrow.counterclockwise",
                    action: resetAll,
                )
                .labelStyle(.iconOnly)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func resetAll() {
        model.resetAll(catalog)
    }
}
