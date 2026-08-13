import RegionKit
import SFSafeSymbols
import SwiftUI

/// The identity-preserving destination for a ranked folio card.
///
/// The compact document header carries the source card's region ink, name,
/// map, and year into the calendar while the native zoom remains interactive.
struct FocusedRegionCalendarView: View {
    let region: Region
    let report: YearReportModel

    @State private var regionPath = Path()

    @Environment(\.regionOutlinePathCache) private var regionOutlinePathCache
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    private var regionStyle: RegionStyle {
        regionStyles.style(for: region)
    }

    private var dayCount: Int {
        report.report?.totals[region] ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CalendarContentView(focusedRegion: region, report: report)
        }
        .background(stylesheet.palette.brand.canvas.ignoresSafeArea())
        .navigationTitle(
            WhereFormat.calendarRegionTitle(region: region, year: report.selectedYear),
        )
        .toolbarBackground(stylesheet.palette.brand.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: region) {
            guard let regionOutlinePathCache else { return }
            let path = await regionOutlinePathCache.path(for: region, resolution: .medium)
            guard !Task.isCancelled else { return }
            regionPath = path
        }
    }

    private var header: some View {
        let card = stylesheet.card.regular
        let shape = RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)

        return ZStack(alignment: .trailing) {
            if let artworkStyle = card.regionShape?.watermark, !regionPath.isEmpty {
                RegionOutlineArtwork(
                    path: regionPath,
                    tint: regionStyle.tint,
                    style: artworkStyle,
                )
                .frame(width: 160, height: 104)
                .offset(x: 18)
            }

            VStack(alignment: .leading, spacing: stylesheet.spacing.regular) {
                HStack(spacing: stylesheet.spacing.medium) {
                    WhereSeal(tint: stylesheet.palette.brand.brass)
                        .frame(width: 24, height: 24)
                    Text(WhereFormat.yearText(report.selectedYear))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .tracking(1)
                        .foregroundStyle(stylesheet.palette.brand.brass)
                }

                Text(region.localizedName)
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(regionStyle.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(alignment: .firstTextBaseline, spacing: stylesheet.spacing.small) {
                    Image(systemSymbol: regionStyle.symbol)
                        .font(.caption)
                    Text(dayCount, format: .number)
                        .font(.headline.monospacedDigit())
                    Text(WhereFormat.dayUnit(dayCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(regionStyle.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(card.padding)
        .background(stylesheet.palette.brand.raisedPaper, in: shape)
        .overlay {
            shape.strokeBorder(
                stylesheet.palette.brand.ink.opacity(
                    stylesheet.locations.surfaceBorderOpacity,
                ),
                lineWidth: stylesheet.locations.surfaceBorderWidth,
            )
        }
        .clipShape(shape)
        .padding(.horizontal, stylesheet.locations.horizontalInset)
        .padding(.top, stylesheet.spacing.medium)
        .padding(.bottom, stylesheet.spacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            WhereFormat.regionDaysAccessibility(
                region: region.localizedName,
                days: dayCount,
            ),
        )
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            FocusedRegionCalendarView(
                region: .california,
                report: PreviewSupport.loadedYearReportModel(),
            )
        }
        .whereBroadwayRoot()
    }
#endif
