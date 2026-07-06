import SwiftUI
import WhereCore

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Presented as a sheet from the Primary tab.
struct PresenceTimelineView: View {
    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PresenceTimelineList(report: report)
                .navigationTitle(Strings.timelineTitle(year: report.selectedYear))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.timelineDone) { dismiss() }
                    }
                }
        }
    }
}

/// The stint list shared by `PresenceTimelineView` and the calendar drill-in.
/// When `scrollToMonth` is set, scrolls to the first stint overlapping that
/// month on appear.
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

    private var style: RegionStyle {
        stint.region.style
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacings.large) {
            Capsule()
                .fill(style.tint.gradient)
                .frame(
                    width: UIConstants.Size.timelineAccentWidth,
                    height: UIConstants.Size.timelineAccentHeight,
                )

            Text(style.emoji)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                Text(stint.region.localizedName)
                    .font(.headline)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: UIConstants.Spacings.medium)

            Text(Strings.dayCount(stint.dayCount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, UIConstants.Spacings.xSmall)
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
        PresenceTimelineView(report: PreviewSupport.loadedYearReportModel())
    }
#endif
