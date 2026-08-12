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
            WhereThemePreviewArtwork()

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

/// A compact rendering of the current Liquid Glass location-card language.
private struct WhereThemePreviewArtwork: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.card.regular
        let tint = Color.orange
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)

        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            HStack {
                Text(verbatim: "CALIFORNIA • 2026")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(tint.opacity(0.8))
                Spacer(minLength: 0)
                Image(systemSymbol: .sunMaxFill)
                    .foregroundStyle(tint)
            }

            Text(verbatim: "California")
                .font(style.regionNameTypography.font)
                .tracking(style.regionNameTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .foregroundStyle(tint.opacity(stylesheet.card.nameOpacity))

            HStack(alignment: .firstTextBaseline, spacing: stylesheet.spacing.xSmall) {
                Text(verbatim: "128")
                    .font(.title.bold().monospacedDigit())
                Text(.themePreviewDays)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(tint.opacity(0.16))
                .frame(height: style.progressBarHeight)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * 0.4)
                    }
                }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .background {
            SecurityPrintRosette(
                tint: tint,
                wobble: style.rosette.wobble,
                lineWidth: style.rosette.lineWidth,
                primaryRingSpacing: style.rosette.primaryRingSpacing,
                secondaryRingSpacing: style.rosette.secondaryRingSpacing,
                primaryOpacity: stylesheet.card.rosetteFill.primary,
                secondaryOpacity: stylesheet.card.rosetteFill.secondary,
            )
            .clipShape(shape)
        }
        .glassEffect(
            .regular.tint(tint.opacity(stylesheet.card.glassTintOpacity)),
            in: shape,
        )
        .overlay { shape.stroke(tint.opacity(0.18), lineWidth: 0.75) }
        .accessibilityHidden(true)
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
