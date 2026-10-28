import SwiftUI
import WhereCore

/// One region row in manual-day and relabel forms.
struct RegionToggleRow: View {
    @Bindable var item: RegionToggleItem

    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        Toggle(isOn: $item.isOn) {
            Label {
                Text(item.region.localizedName)
            } icon: {
                Text(regionStyles.style(for: item.region).emoji)
            }
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            RegionToggleRow(item: RegionToggleItem(region: .california, isOn: true))
            RegionToggleRow(item: RegionToggleItem(region: .newYork, isOn: false))
        }
        .whereBroadwayRoot()
    }
#endif
