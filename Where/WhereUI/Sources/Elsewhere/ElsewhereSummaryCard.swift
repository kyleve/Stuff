import SFSafeSymbols
import SwiftUI
import WhereCore

/// The entry card at the bottom of the Locations tab that summarizes the
/// regions outside your primary spots and links to the full ``ElsewhereView``.
/// Shown only when there are secondary regions; the caller wraps it in the
/// `NavigationLink`, so this is just the neutral folio label.
struct ElsewhereSummaryCard: View {
    /// Number of secondary regions.
    let regionCount: Int

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.ElsewhereCardStyle {
        stylesheet.elsewhereCard
    }

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            WhereSeal(tint: stylesheet.palette.brand.brass)
                .frame(width: style.iconPointSize, height: style.iconPointSize)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(String(localized: .secondaryTitle))
                    .font(.system(.headline, design: .serif).weight(.semibold))
                    .foregroundStyle(stylesheet.palette.brand.ink)
                Text(WhereFormat.elsewhereCardSubtitle(regions: regionCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemSymbol: .chevronRight)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity)
        .background(stylesheet.palette.brand.raisedPaper, in: cardShape)
        .overlay {
            cardShape.strokeBorder(
                stylesheet.palette.brand.ink.opacity(
                    stylesheet.locations.surfaceBorderOpacity,
                ),
                lineWidth: stylesheet.locations.surfaceBorderWidth,
            )
        }
        .shadow(
            color: Color.black.opacity(0.06),
            radius: 10,
            y: 4,
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }
}

#if DEBUG
    #Preview {
        ElsewhereSummaryCard(regionCount: 3)
            .padding()
    }
#endif
