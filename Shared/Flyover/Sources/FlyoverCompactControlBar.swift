import SwiftUI

/// A width-constrained bottom bar that preserves every global control.
struct FlyoverCompactControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: stylesheet.controlBar.compactSpacing) {
                FlyoverViewModePicker(model: model)
                    .frame(width: stylesheet.controlBar.compactViewModeWidth)
                FlyoverZoomSlider(model: model)
                    .frame(width: stylesheet.controlBar.compactZoomWidth)
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
