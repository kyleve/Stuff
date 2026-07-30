import SwiftUI

/// The canvas zoom control, hidden while Flyover is in list mode.
struct FlyoverZoomSlider<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        if model.viewMode == .canvas {
            Slider(value: $model.zoom, in: 0.15 ... 1.25) {
                Text("Zoom")
            } minimumValueLabel: {
                Image(systemName: "minus.magnifyingglass")
            } maximumValueLabel: {
                Image(systemName: "plus.magnifyingglass")
            }
        }
    }
}
