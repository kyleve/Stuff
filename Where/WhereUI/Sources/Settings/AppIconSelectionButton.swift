import SFSafeSymbols
import SwiftUI

struct AppIconSelectionButton: View {
    let option: AppIconOption
    let iconSize: CGFloat
    let isSelected: Bool
    // Dim this cell's icon while its own panel is up so the grid reads as
    // backgrounded without fully hiding the icon already enlarged in the
    // panel. It fades back as the panel slides away (the flip rides the same
    // `.snappy` animation that drives `preview`).
    let isPreviewing: Bool
    let select: () -> Void

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let appIcon = stylesheet.appIcon
        Button {
            select()
        } label: {
            VStack(spacing: appIcon.cellSpacing) {
                AppIconImage(name: option.previewImageName, size: iconSize)
                    .opacity(isPreviewing ? appIcon.backgroundedCellOpacity : 1)

                HStack(spacing: appIcon.cellLabelSpacing) {
                    if isSelected {
                        Image(systemSymbol: .checkmarkCircleFill)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(option.displayName)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(option.displayName)
        .accessibilityValue(isSelected ? String(localized: .appIconCurrent) : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
    #Preview { AppIconSelectionButtonPreview() }

    private struct AppIconSelectionButtonPreview: View {
        var body: some View {
            if let option = AppIconModel.preview().selectedOption {
                AppIconSelectionButton(
                    option: option,
                    iconSize: 100,
                    isSelected: true,
                    isPreviewing: false,
                    select: {},
                )
                .whereBroadwayRoot()
            }
        }
    }
#endif
