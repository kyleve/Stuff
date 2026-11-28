import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

struct WhereThemeOptionButton: View {
    @Environment(\.stylesheet) private var stylesheet
    let theme: WhereTheme
    let isSelected: Bool
    let onSelect: (WhereTheme) -> Void

    var body: some View {
        Button {
            onSelect(theme)
        } label: {
            VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                WhereThemeCardSpecimen(theme: theme)

                WhereThemeOptionCaption(theme: theme, isSelected: isSelected)
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
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityValue(
            isSelected
                ? String(localized: .themeSelectedValue)
                : String(localized: .themeNotSelectedValue),
        )
        .accessibilityHint(theme.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WhereThemeOptionCaption: View {
    @Environment(\.stylesheet) private var stylesheet
    let theme: WhereTheme
    let isSelected: Bool

    var body: some View {
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
                .lineLimit(3...)
        }
    }
}

private struct WhereThemeCardSpecimen: View {
    @Environment(\.regionOutlinePathCache) private var regionOutlinePathCache
    let theme: WhereTheme

    var body: some View {
        RegionSummaryCard(
            regionDays: RegionDays(region: .california, days: 128),
            variant: .compact,
            renderPurpose: .themeSpecimen,
            year: 2026,
            showsRecordedPoints: false,
        )
        .environment(\.regionOutlinePathCache, regionOutlinePathCache)
        .whereBroadwayRoot(theme: theme)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview { WhereThemePicker(selection: .standard) { _ in }.whereBroadwayRoot() }
#endif
