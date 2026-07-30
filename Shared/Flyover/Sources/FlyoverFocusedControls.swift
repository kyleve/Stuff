import SwiftUI

/// Local controls repeated beneath a focused, interactive screen.
struct FlyoverFocusedControls<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: stylesheet.controlBar.focusedSpacing) {
                FlyoverFocusedVariantPicker(screen: screen, model: model)

                ForEach(screen.controls, id: \.id) { control in
                    control.content
                        .frame(minWidth: stylesheet.controlBar.focusedControlMinimumWidth)
                }

                if let customControls = screen.customControls {
                    customControls
                }

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    model.reset(screen)
                }
            }
            .padding(.horizontal, stylesheet.controlBar.horizontalPadding)
            .padding(.vertical, stylesheet.controlBar.verticalPadding)
        }
        .flyoverBarSurface()
    }
}
