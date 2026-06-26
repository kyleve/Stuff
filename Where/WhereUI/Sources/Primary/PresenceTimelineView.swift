import StuffCore
import SwiftUI
import WhereCore

/// A chronological list of continuous stays (`RegionStint`s) for the selected
/// year — "California, Jan 1 – Feb 3", "New York, Feb 3 – Mar 10", and so on.
/// Presented as a sheet from the Primary tab.
struct PresenceTimelineView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var stints: [RegionStint] {
        guard let report = session.report else { return [] }
        return PresenceTimeline.stints(from: report)
    }

    var body: some View {
        NavigationStack {
            Group {
                if stints.isEmpty {
                    ContentUnavailableView {
                        Label(
                            LocalizedStrings.Timeline.emptyTitle.localized,
                            systemImage: "calendar.day.timeline.left",
                        )
                    } description: {
                        Text.localized(LocalizedStrings.Timeline.emptyDescription)
                    }
                } else {
                    List(stints) { stint in
                        StintRow(stint: stint)
                    }
                }
            }
            .navigationTitle(LocalizedStrings.Timeline.title(year: session.selectedYear)
                .localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStrings.Timeline.done.localized) { dismiss() }
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

            Text.localized(LocalizedStrings.Common.dayCount(stint.dayCount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, UIConstants.Spacings.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            LocalizedStrings.Timeline.rowAccessibility(
                region: stint.region.localizedName,
                range: dateRange,
                days: stint.dayCount,
            ).localized,
        )
    }

    private var dateRange: String {
        DateRangeFormatting.abbreviated(start: stint.start, end: stint.end)
    }
}

#if DEBUG
    #Preview {
        PresenceTimelineView()
            .environment(PreviewSupport.loadedSession())
    }
#endif
