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
                        Label("No stays yet", systemImage: "calendar.day.timeline.left")
                    } description: {
                        Text(
                            "Once Where has a run of days in a region, your stays will appear here.",
                        )
                    }
                } else {
                    List(stints) { stint in
                        StintRow(stint: stint)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var navigationTitle: String {
        "Timeline · \(model.selectedYear)"
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
        HStack(spacing: 12) {
            Capsule()
                .fill(style.tint.gradient)
                .frame(width: 4, height: 34)

            Text(style.emoji)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(stint.region.localizedName)
                    .font(.headline)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(stint.dayCount) \(stint.dayCount == 1 ? "day" : "days")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stint.region.localizedName), \(dateRange), \(stint.dayCount) days")
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
