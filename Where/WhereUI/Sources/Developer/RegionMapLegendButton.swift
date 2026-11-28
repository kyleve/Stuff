import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct RegionMapLegendButton: View {
    let group: RegionMapLegendGroup
    let isSelected: Bool
    let tint: Color
    let onSelect: (String?) -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Button {
            onSelect(isSelected ? nil : group.title)
        } label: {
            HStack(spacing: stylesheet.spacing.large) {
                Circle()
                    .fill(tint)
                    // Developer legend swatch — a fixed dev-tool size, not a themed token.
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text(group.title)
                Spacer()
                if group.outlineCount > 1 {
                    Text("\(group.outlineCount)")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                if isSelected {
                    Image(systemSymbol: .checkmark)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }
}

#if DEBUG
    #Preview { RegionMapView.snapshotPreviews }
#endif
