import SFSafeSymbols
import SwiftUI

/// Device and orientation controls for device-sized Flyover screens.
struct FlyoverViewportMenu<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        Menu {
            FlyoverOptionsPicker(
                title: "Device",
                choices: FlyoverDevice.allCases,
                selection: $model.device,
                label: \.title,
            )
            FlyoverOptionsPicker(
                title: "Orientation",
                choices: FlyoverOrientation.allCases,
                selection: $model.orientation,
                label: \.title,
            )
        } label: {
            Label("Viewport", systemSymbol: .rectangleOnRectangle)
        }
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
