import SwiftUI
import WhereCore

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Hosted as the Timeline segment of the Your Year tab and as the calendar's
/// day-tap drill-in. When `scrollToMonth` is set, scrolls to the first stint
/// overlapping that month on appear.
struct PresenceTimelineList: View {
    let report: YearReportModel

    var scrollToMonth: Date?

    private var stints: [RegionStint] {
        guard let report = report.report else { return [] }
        return PresenceTimeline.stints(from: report)
    }

    var body: some View {
        if stints.isEmpty {
            ContentUnavailableView {
                Label(Strings.timelineEmptyTitle, systemImage: "calendar.day.timeline.left")
            } description: {
                Text(Strings.timelineEmptyDescription)
            }
        } else {
            ScrollViewReader { proxy in
                List(stints) { stint in
                    StintRow(stint: stint)
                }
                .onAppear {
                    scrollToTargetMonth(proxy)
                }
            }
        }
    }

    private func scrollToTargetMonth(_ proxy: ScrollViewProxy) {
        guard let startOfMonth = scrollToMonth else { return }
        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)
        else { return }
        guard let target = stints.first(where: { $0.end >= startOfMonth && $0.start < nextMonth })
        else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(target.id, anchor: .top)
        }
    }
}

/// One row in the timeline: region, the date span it covers, and how many
/// consecutive days that was.
private struct StintRow: View {
    let stint: RegionStint

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var timeline: WhereStylesheet.TimelineStyle {
        stylesheet.timeline
    }

    private var style: RegionStyle {
        regionStyles.style(for: stint.region)
    }

    var body: some View {
        HStack(spacing: timeline.rowSpacing) {
            Capsule()
                .fill(style.tint.gradient)
                .frame(
                    width: timeline.accentWidth,
                    height: timeline.accentHeight,
                )

            Text(style.emoji)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: timeline.labelSpacing) {
                Text(stint.region.localizedName)
                    .font(.headline)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: timeline.trailingMinSpacing)

            Text(Strings.dayCount(stint.dayCount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, timeline.rowVerticalPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Strings.timelineRowAccessibility(
                region: stint.region.localizedName,
                range: dateRange,
                days: stint.dayCount,
            ),
        )
    }

    private var dateRange: String {
        DateRangeFormatting.abbreviated(start: stint.start, end: stint.end)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            PresenceTimelineList(report: PreviewSupport.loadedYearReportModel())
        }
    }
#endif
