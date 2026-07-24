import SwiftUI
import WhereCore

/// The entry card at the bottom of the Locations tab that summarizes the
/// regions outside your primary spots and links to the full ``ElsewhereView``.
/// Shown only when there are secondary regions; the caller wraps it in the
/// `NavigationLink`, so this is just the (glass) label.
struct ElsewhereSummaryCard: View {
    /// Number of secondary regions.
    let regionCount: Int

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.ElsewhereCardStyle {
        stylesheet.elsewhereCard
    }

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: style.iconPointSize))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(String(localized: .secondaryTitle))
                    .font(.headline)
                Text(WhereFormat.elsewhereCardSubtitle(regions: regionCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous),
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        ElsewhereSummaryCard(regionCount: 3)
            .padding()
    }
#endif
