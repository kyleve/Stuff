import SwiftUI

/// Local controls repeated beneath a focused, interactive screen.
struct FlyoverFocusedControls<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                FlyoverFocusedVariantPicker(screen: screen, model: model)

                ForEach(screen.controls, id: \.id) { control in
                    control.content
                        .frame(minWidth: 160)
                }

                if let customControls = screen.customControls {
                    customControls
                }

                Button("Reset", systemImage: "arrow.counterclockwise") {
                    model.reset(screen)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .controlSize(.small)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
