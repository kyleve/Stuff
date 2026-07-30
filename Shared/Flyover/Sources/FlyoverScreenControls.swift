import SwiftUI

/// Variant selection, reset, and app-provided controls for one Flyover screen.
struct FlyoverScreenControls<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        @Bindable var state = model.state(for: screen)

        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if screen.variants.count > 1 {
                    Picker("Variant", selection: $state.variantID) {
                        ForEach(screen.variants, id: \.id) { variant in
                            Text(variant.title)
                                .tag(variant.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                ForEach(screen.controls, id: \.id) { control in
                    control.content
                }

                if let customControls = screen.customControls {
                    customControls
                }

                if model.previewedScreenID == screen.id {
                    Button("Pause Preview", systemImage: "pause.fill") {
                        model.pausePreview()
                    }
                    .buttonStyle(.borderless)
                }

                Button("Reset Frame", systemImage: "arrow.counterclockwise") {
                    model.reset(screen)
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: 126)
        .controlSize(.small)
    }
}
