import SFSafeSymbols
import SwiftUI

/// Device and orientation controls for device-sized Flyover screens.
struct FlyoverViewportMenu<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        Menu {
            Picker("Device", selection: $model.device) {
                ForEach(FlyoverDevice.allCases) { device in
                    Text(device.title)
                        .tag(device)
                }
            }
            Picker("Orientation", selection: $model.orientation) {
                ForEach(FlyoverOrientation.allCases) { orientation in
                    Text(orientation.title)
                        .tag(orientation)
                }
            }
        } label: {
            Label("Viewport", systemSymbol: .rectangleOnRectangle)
        }
    }
}
