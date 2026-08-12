import SwiftUI

/// The annual ledger's midnight cover and its three report-backed figures.
struct YearLedgerCover: View {
    let year: Int
    let summary: YearLedgerSummary
    let calendar: Calendar

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let cover = stylesheet.year.cover
        let brand = stylesheet.palette.brand
        let shape = RoundedRectangle(cornerRadius: cover.cornerRadius, style: .continuous)

        ZStack(alignment: .bottomTrailing) {
            WhereSeal(tint: brand.onMidnight.opacity(0.06))
                .frame(width: 260, height: 260)
                .offset(x: 76, y: 72)

            VStack(alignment: .leading, spacing: stylesheet.spacing.xxxLarge) {
                HStack(alignment: .top) {
                    WhereSeal(tint: brand.brass)
                        .frame(width: cover.sealSize, height: cover.sealSize)

                    Spacer()

                    VStack(alignment: .trailing, spacing: stylesheet.spacing.xxSmall) {
                        Text(.yearLedgerPrivateRecord)
                            .font(cover.eyebrowFont)
                            .tracking(1.4)
                            .textCase(.uppercase)
                        Text(WhereFormat.yearText(year))
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(brand.brass)
                }
                .staggeredReveal(order: 0)

                VStack(alignment: .leading, spacing: stylesheet.spacing.regular) {
                    Text(WhereFormat.yearLedgerCoverTitle(year: year))
                        .font(cover.titleFont)
                        .foregroundStyle(brand.onMidnight)
                        .fixedSize(horizontal: false, vertical: true)

                    Rectangle()
                        .fill(brand.brass)
                        .frame(width: 52, height: 1)
                        .accessibilityHidden(true)
                }
                .staggeredReveal(order: 1)

                if summary.recordedDayCount == 0 {
                    emptyState
                        .staggeredReveal(order: 2)
                } else {
                    figures
                        .staggeredReveal(order: 2)
                }

                Spacer(minLength: stylesheet.spacing.large)

                HStack(spacing: stylesheet.spacing.medium) {
                    Text(.yearLedgerOpen)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(brand.midnight)
                .padding(.horizontal, cover.actionHorizontalPadding)
                .padding(.vertical, cover.actionVerticalPadding)
                .background(brand.onMidnight, in: Capsule())
            }
            .padding(.horizontal, cover.horizontalPadding)
            .padding(.vertical, cover.verticalPadding)
        }
        .frame(maxWidth: .infinity, minHeight: cover.minimumHeight, alignment: .leading)
        .background(brand.midnight, in: shape)
        .optionalGlassSurface(
            cover.usesGlassSurface,
            tint: brand.midnight.opacity(0.2),
            in: shape,
        )
        .overlay {
            shape.strokeBorder(
                brand.brass.opacity(cover.borderOpacity),
                lineWidth: cover.borderWidth,
            )
        }
        .clipShape(shape)
        .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: stylesheet.year.cover.figureSpacing) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.year.cover.figureSpacing) {
                    figure(
                        value: summary.recordedDayCount.formatted(),
                        label: String(localized: .yearLedgerRecordedDays),
                    )
                    figure(
                        value: summary.namedRegionCount.formatted(),
                        label: String(localized: .yearLedgerNamedRegions),
                        detail: summary.includesElsewhere
                            ? String(localized: .yearLedgerIncludesElsewhere)
                            : nil,
                    )
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: stylesheet.year.cover.figureSpacing) {
                        figure(
                            value: summary.recordedDayCount.formatted(),
                            label: String(localized: .yearLedgerRecordedDays),
                        )
                        figure(
                            value: summary.namedRegionCount.formatted(),
                            label: String(localized: .yearLedgerNamedRegions),
                            detail: summary.includesElsewhere
                                ? String(localized: .yearLedgerIncludesElsewhere)
                                : nil,
                        )
                    }

                    VStack(alignment: .leading, spacing: stylesheet.year.cover.figureSpacing) {
                        figure(
                            value: summary.recordedDayCount.formatted(),
                            label: String(localized: .yearLedgerRecordedDays),
                        )
                        figure(
                            value: summary.namedRegionCount.formatted(),
                            label: String(localized: .yearLedgerNamedRegions),
                            detail: summary.includesElsewhere
                                ? String(localized: .yearLedgerIncludesElsewhere)
                                : nil,
                        )
                    }
                }
            }

            if let leadingRegion = summary.leadingRegion {
                figure(
                    value: leadingRegion.region.localizedName,
                    label: String(localized: .yearLedgerLeadingRegion),
                    detail: WhereFormat.dayCount(leadingRegion.days),
                    usesEditorialValue: true,
                )
            } else if summary.includesElsewhere {
                figure(
                    value: String(localized: .secondaryTitle),
                    label: String(localized: .yearLedgerLeadingRegion),
                    detail: WhereFormat.dayCount(summary.elsewhereDayCount),
                    usesEditorialValue: true,
                )
            }

            if let latestRecordedDay = summary.latestRecordedDay {
                Text(WhereFormat.yearLedgerLatestRecord(
                    day: latestRecordedDay,
                    calendar: calendar,
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(stylesheet.palette.brand.onMidnight.opacity(0.66))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
            Text(.yearLedgerEmptyTitle)
                .font(.title3.weight(.semibold))
            Text(.yearLedgerEmptyDescription)
                .font(.subheadline)
                .foregroundStyle(stylesheet.palette.brand.onMidnight.opacity(0.72))
        }
        .foregroundStyle(stylesheet.palette.brand.onMidnight)
    }

    private func figure(
        value: String,
        label: String,
        detail: String? = nil,
        usesEditorialValue: Bool = false,
    ) -> some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(value)
                .font(
                    usesEditorialValue
                        ? stylesheet.year.cover.figureEditorialFont
                        : stylesheet.year.cover.figureNumberFont,
                )
                .foregroundStyle(stylesheet.palette.brand.onMidnight)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(stylesheet.year.cover.figureLabelFont)
                .tracking(0.8)
                .foregroundStyle(stylesheet.palette.brand.brass)
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(stylesheet.palette.brand.onMidnight.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        if let yearReport = report.report {
            StaggeredRevealScope {
                YearLedgerCover(
                    year: report.selectedYear,
                    summary: YearLedgerSummary(report: yearReport),
                    calendar: report.calendar,
                )
            }
            .padding()
            .background(WhereStylesheet.default.palette.brand.canvas)
            .whereBroadwayRoot()
        }
    }
#endif
