import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct RegionColorButton: View {
    @Binding var appearance: RegionAppearance
    let token: RegionColorToken
    let style: WhereStylesheet.RegionPickerStyle

    var body: some View {
        let isSelected = appearance.color == token
        Button {
            appearance.color = token
        } label: {
            Circle()
                .fill(token.color)
                .frame(width: style.colorSwatchSize, height: style.colorSwatchSize)
                .overlay {
                    Circle()
                        .strokeBorder(
                            .primary,
                            lineWidth: isSelected ? style.colorSwatchSelectionRing : 0,
                        )
                }
                .overlay {
                    if isSelected {
                        Image(systemSymbol: .checkmark)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(token.selectionForeground)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WhereFormat.regionColorAccessibility(token))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
    #Preview { RegionCustomizeView.snapshotPreviews }
#endif
