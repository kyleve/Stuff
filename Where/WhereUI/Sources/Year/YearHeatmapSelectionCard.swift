import RegionKit
import SwiftUI

/// The compact textual readout for the heatmap's selected day.
struct YearHeatmapSelectionCard: View {
    let day: YearOverview.Day
    let calendar: Calendar

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var style: WhereStylesheet.YearOverviewStyle {
        stylesheet.yearOverview
    }

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                Text(
                    day.id.startOfDay(in: calendar),
                    format: .dateTime.weekday(.wide).month(.wide).day().year(),
                )
                .font(.headline)
                Text(WhereFormat.yearOverviewKindName(day.kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(style.heatmap.calloutPadding)
        .background(Color.primary.opacity(0.05), in: .rect(
            cornerRadius: style.heatmap.calloutCornerRadius,
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WhereFormat.yearOverviewDayAccessibility(
            date: day.id.startOfDay(in: calendar),
            kind: day.kind,
        ))
    }

    private var color: Color {
        switch day.kind {
            case let .region(region): regionStyles.style(for: region).tint
            case .multipleLocations: style.multipleLocationsColor
            case .unrecorded: style.unrecordedColor
            case .remaining: style.remainingColor
        }
    }

    private var symbol: String {
        switch day.kind {
            case let .region(region): regionStyles.style(for: region).symbolName
            case .multipleLocations: "arrow.triangle.branch"
            case .unrecorded: "exclamationmark.circle.fill"
            case .remaining: "clock.fill"
        }
    }
}

#if DEBUG
    #Preview {
        let model = PreviewSupport.loadedYearReportModel()
        let overview = PreviewSupport.loadedYearOverview()
        if let day = overview.day(month: 1, dayOfMonth: 1) {
            YearHeatmapSelectionCard(day: day, calendar: model.calendar)
                .padding()
                .whereBroadwayRoot()
        }
    }
#endif
