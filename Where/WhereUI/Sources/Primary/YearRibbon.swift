import RegionKit
import SwiftUI
import WhereCore

/// A compact, calendar-proportional overview of the selected year's stays.
/// Empty portions remain visible, so the ribbon shows both travel and gaps.
struct YearRibbon: View {
    let days: [DayPresence]
    let year: Int
    let calendar: Calendar

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let overview = timeline.overview
        let ribbon = timeline.ribbon
        let regions = Region.inCanonicalOrder(Set(days.flatMap(\.regions)))
        let monthStarts = (1 ... 12).compactMap { month in
            calendar.date(from: DateComponents(year: year, month: month, day: 1))
        }

        VStack(alignment: .leading, spacing: overview.spacing) {
            Text(WhereFormat.yearText(year))
                .font(overview.yearFont)
                .monospacedDigit()

            VStack(spacing: ribbon.monthLabelSpacing) {
                HStack(spacing: 0) {
                    ForEach(monthStarts, id: \.self) { month in
                        VStack(spacing: 2) {
                            Text(month, format: .dateTime.month(.narrow))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(stylesheet.palette.brand.ink.opacity(0.22))
                                .frame(width: 0.5, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if ribbon.separatesRegions {
                    VStack(spacing: ribbon.regionSpacing) {
                        ForEach(regions, id: \.self) { region in
                            VStack(
                                alignment: .leading,
                                spacing: ribbon.regionLabelSpacing,
                            ) {
                                let style = regionStyles.style(for: region)
                                let regionName = region == .other
                                    ? String(localized: .secondaryTitle)
                                    : region.localizedName
                                HStack(spacing: stylesheet.spacing.small) {
                                    Image(systemName: style.symbolName)
                                        .foregroundStyle(style.tint)
                                    Text(regionName)
                                    Text(style.emoji)
                                        .font(.caption2)
                                }
                                .font(.caption)

                                YearRibbonBand(
                                    days: days,
                                    year: year,
                                    calendar: calendar,
                                    isolatedRegion: region,
                                )
                            }
                        }
                    }
                } else {
                    YearRibbonBand(
                        days: days,
                        year: year,
                        calendar: calendar,
                        isolatedRegion: nil,
                    )
                }
            }
            .accessibilityHidden(true)
        }
        .padding(overview.padding)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: overview.cornerRadius, style: .continuous)
                    .fill(stylesheet.palette.brand.raisedPaper)
                RoundedRectangle(cornerRadius: overview.cornerRadius)
                    .fill(overview.background)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: overview.cornerRadius)
                .stroke(
                    overview.border,
                    lineWidth: overview.borderWidth,
                )
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.loadedYearReportModel()
        YearRibbon(
            days: report.report?.days ?? [],
            year: report.selectedYear,
            calendar: report.calendar,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif
