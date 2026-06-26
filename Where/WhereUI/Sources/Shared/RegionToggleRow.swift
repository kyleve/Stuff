import SwiftUI
import WhereCore

/// One region row in manual-day and relabel forms.
struct RegionToggleRow: View {
    @Bindable var item: RegionToggleItem

    var body: some View {
        Toggle(isOn: $item.isOn) {
            Label {
                Text(item.region.localizedName)
            } icon: {
                Text(item.region.style.emoji)
            }
        }
    }
}
