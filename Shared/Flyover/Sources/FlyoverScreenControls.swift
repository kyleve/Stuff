import SFSafeSymbols
import SwiftUI

/// Variant selection, reset, and app-provided controls for one Flyover screen.
struct FlyoverScreenControls<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.screenControls

        ScrollView {
            VStack(alignment: .leading, spacing: style.spacing) {
                FlyoverVariantPicker(screen: screen, model: model)

                ForEach(screen.controls, id: \.id) { control in
                    control.content
                }

                if let customControls = screen.customControls {
                    customControls
                }

                if model.previewedScreenID == screen.id {
                    Button("Pause Preview", systemSymbol: .pauseFill) {
                        model.pausePreview()
                    }
                    .buttonStyle(.borderless)
                }

                Button("Reset Frame", systemSymbol: .arrowCounterclockwise) {
                    model.reset(screen)
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(style.padding)
        }
        .frame(maxHeight: style.maximumHeight)
        .controlSize(style.controlSize)
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
