import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

struct RegionPickerRegionRow: View {
    let region: Region
    let includesCountryCode: Bool
    let model: RegionPickerModel

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let style = regionStyles.style(for: region)
        let selected = model.draft.isSelected(region)
        let codeLabel = model.code(for: region).map { code in
            includesCountryCode ? "\(code.country) · \(code.subdivision)" : code.subdivision
        }
        Button {
            withAnimation(stylesheet.regionPicker.selectionAnimation) {
                model.draft.toggle(region)
            }
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
                Text(style.emoji)
                    .accessibilityHidden(true)
                LabeledContent {
                    if let codeLabel {
                        Text(verbatim: codeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(region.localizedName)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemSymbol: .checkmark)
                        .fontWeight(.semibold)
                        .foregroundStyle(style.tint)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .accessibilityLabel(region.localizedName)
        .accessibilityValue(codeLabel ?? "")
        .accessibilityHint(selected ? WhereFormat.regionPickerRemoveSelection(region) : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .disabled(!model.draft.canToggle(region))
    }
}

#if DEBUG
    #Preview { RegionPickerView.snapshotPreviews }
#endif
