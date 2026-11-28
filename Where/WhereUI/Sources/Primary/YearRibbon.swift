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
                YearRibbonMonths(monthStarts: monthStarts)

                if ribbon.separatesRegions {
                    VStack(spacing: ribbon.regionSpacing) {
                        ForEach(regions, id: \.self) { region in
                            YearRibbonRegion(
                                region: region,
                                days: days,
                                year: year,
                                calendar: calendar,
                                spacing: ribbon.regionLabelSpacing,
                            )
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
                RoundedRectangle(cornerRadius: overview.cornerRadius)
                    .fill(.background)
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

private struct YearRibbonMonths: View {
    let monthStarts: [Date]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(monthStarts, id: \.self) { month in
                Text(month, format: .dateTime.month(.narrow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct YearRibbonRegion: View {
    let region: Region
    let days: [DayPresence]
    let year: Int
    let calendar: Calendar
    let spacing: CGFloat
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            let style = regionStyles.style(for: region)
            Label {
                Text(region.localizedName)
            } icon: {
                Text(style.emoji)
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
