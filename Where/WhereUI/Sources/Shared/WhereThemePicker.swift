import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// The adaptive theme selector shared by onboarding and Appearance Settings.
/// Its specimens deliberately use the same current card language while the
/// two theme identities remain visual scaffolding.
struct WhereThemePicker: View {
    let selection: WhereTheme
    let onSelect: (WhereTheme) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: stylesheet.spacing.large))
            : AnyLayout(HStackLayout(alignment: .top, spacing: stylesheet.spacing.large))

        layout {
            ForEach(WhereTheme.allCases, id: \.self) { theme in
                Button {
                    onSelect(theme)
                } label: {
                    WhereThemeOption(theme: theme, isSelected: theme == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityValue(
                    theme == selection
                        ? String(localized: .themeSelectedValue)
                        : String(localized: .themeNotSelectedValue),
                )
                .accessibilityHint(theme.detail)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct WhereThemeOption: View {
    let theme: WhereTheme
    let isSelected: Bool

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            RegionSummaryCard(
                regionDays: RegionDays(region: .california, days: 128),
                variant: .compact,
                renderPurpose: .themeSpecimen,
                year: 2026,
                showsRecordedPoints: false,
            )
            .whereBroadwayRoot(theme: theme)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                HStack(spacing: stylesheet.spacing.small) {
                    Text(theme.title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    Image(systemSymbol: isSelected ? .checkmarkCircleFill : .circle)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                Text(theme.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3, reservesSpace: true)
            }
        }
        .padding(stylesheet.spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(isSelected ? 0.055 : 0.018),
            in: RoundedRectangle(cornerRadius: 18),
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                    lineWidth: isSelected ? 2 : 0.75,
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var selection = WhereTheme.standard
        WhereThemePicker(selection: selection) { selection = $0 }
            .padding()
            .whereBroadwayRoot(theme: selection)
    }
#endif
