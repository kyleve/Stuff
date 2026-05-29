import SwiftUI
import WhereCore

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Presented as a sheet from the Primary tab.
struct PresenceTimelineView: View {
    @Environment(WhereModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var stints: [RegionStint] {
        guard let report = model.report else { return [] }
        return PresenceTimeline.stints(from: report)
    }

    var body: some View {
        NavigationStack {
            Group {
                if stints.isEmpty {
                    ContentUnavailableView {
                        Label(Strings.timelineEmptyTitle, systemImage: "calendar.day.timeline.left")
                    } description: {
                        Text(Strings.timelineEmptyDescription)
                    }
                } else {
                    List(stints) { stint in
                        StintRow(stint: stint)
                    }
                }
            }
            .navigationTitle(Strings.timelineTitle(year: model.selectedYear))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Strings.timelineDone) { dismiss() }
                }
            }
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
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if Calendar.current.isDate(stint.start, inSameDayAs: stint.end) {
            return stint.start.formatted(format)
        }
        return "\(stint.start.formatted(format)) – \(stint.end.formatted(format))"
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineView()
            .environment(PreviewSupport.loadedModel())
    }
#endif
