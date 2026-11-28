import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct PlanningRegionButton: View {
    let region: Region
    let selectedRegion: Region?
    let model: PlanningRegionSelectionModel
    let onSelect: @MainActor (Region) async throws -> Void
    let dismiss: () -> Void
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Button {
            Task {
                if await model.select(region, commit: onSelect) {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
                Text(regionStyles.style(for: region).emoji)
                    .accessibilityHidden(true)
                Text(region.localizedName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if selectedRegion == region {
                    Image(systemSymbol: .checkmark)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(selectedRegion == region ? [.isSelected] : [])
    }
}

#if DEBUG
    #Preview("Region picker") {
        PlanningRegionPickerView.snapshotPreviews
    }
#endif
