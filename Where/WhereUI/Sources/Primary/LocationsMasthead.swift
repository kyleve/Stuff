import SwiftUI
import WhereCore

/// The annual title page above the ranked Locations folio.
struct LocationsMasthead: View {
    let year: Int
    let recordedDayCount: Int
    let representedRegionCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.locations
        let brand = stylesheet.palette.brand

        VStack(alignment: .leading, spacing: style.mastheadSpacing) {
            HStack(spacing: stylesheet.spacing.medium) {
                WhereSeal(tint: brand.brass)
                    .frame(width: 30, height: 30)

                Text(mastheadLabel(for: style.mastheadLabel))
                    .font(style.eyebrowFont)
                    .tracking(1.4)
                    .foregroundStyle(brand.brass)
                    .textCase(.uppercase)
            }

            Text(WhereFormat.locationsRecordedTitle(year: year))
                .font(style.titleFont)
                .foregroundStyle(brand.ink)

            Rectangle()
                .fill(brand.ink.opacity(0.72))
                .frame(width: style.ruleWidth, height: 1)
                .accessibilityHidden(true)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.spacing.regular) {
                    folioFigure(
                        value: recordedDayCount,
                        label: String(localized: .locationsRecordedDays),
                    )
                    folioFigure(
                        value: representedRegionCount,
                        label: String(localized: .locationsRepresentedRegions),
                    )
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: stylesheet.spacing.xxxLarge) {
                        folioFigure(
                            value: recordedDayCount,
                            label: String(localized: .locationsRecordedDays),
                        )
                        folioFigure(
                            value: representedRegionCount,
                            label: String(localized: .locationsRepresentedRegions),
                        )
                    }

                    VStack(alignment: .leading, spacing: stylesheet.spacing.regular) {
                        folioFigure(
                            value: recordedDayCount,
                            label: String(localized: .locationsRecordedDays),
                        )
                        folioFigure(
                            value: representedRegionCount,
                            label: String(localized: .locationsRepresentedRegions),
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func mastheadLabel(
        for label: WhereStylesheet.LocationsStyle.MastheadLabel,
    ) -> LocalizedStringResource {
        switch label {
            case .folio: .locationsFolioLabel
            case .record: .locationsRecordLabel
        }
    }

    @ViewBuilder
    private func folioFigure(value: Int, label: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(value, format: .number)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(stylesheet.palette.brand.ink)
                Text(label)
                    .font(stylesheet.locations.summaryFont)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: stylesheet.spacing.small) {
                Text(value, format: .number)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(stylesheet.palette.brand.ink)
                Text(label)
                    .font(stylesheet.locations.summaryFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    #Preview {
        LocationsMasthead(
            year: 2026,
            recordedDayCount: 212,
            representedRegionCount: 6,
        )
        .padding()
        .background(WhereStylesheet.default.palette.brand.canvas)
        .whereBroadwayRoot()
    }
#endif
