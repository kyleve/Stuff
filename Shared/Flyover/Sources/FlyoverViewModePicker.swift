import SwiftUI

/// The canvas/list segmented control shared by both bottom-bar layouts.
struct FlyoverViewModePicker<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        Picker("View", selection: $model.viewMode) {
            ForEach(FlyoverViewMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}
