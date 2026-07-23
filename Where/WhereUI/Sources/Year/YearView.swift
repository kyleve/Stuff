import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data.
/// A floating Liquid Glass pill at the bottom (Photos-style) zooms between the
/// calendar (month detail) and the timeline (year overview); the activity
/// summary sits in the toolbar.
struct YearView: View {
    let report: YearReportModel

    @State private var mode: YearMode = .calendar
    @State private var showingRecentActivity = false

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                    case .calendar:
                        CalendarContentView(report: report)
                    case .timeline:
                        PresenceTimelineList(report: report)
                }
            }
            // Crossfade between the two views rather than hard-cutting.
            .animation(.default, value: mode)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            // Keep the bar background on at all times. The calendar auto-scrolls
            // under the bar (so its scroll-edge material is showing) while the
            // timeline starts at the top; without pinning it, switching between
            // them animates that material in/out — reading as a toolbar fade.
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, alignment: .center) {
                YearModePicker(mode: $mode)
                    .padding(.bottom, stylesheet.spacing.xLarge)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingRecentActivity = true
                    } label: {
                        Label(Strings.primaryRecentActivity, systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("where_recent_activity_button")
                }
            }
        }
        .sheet(isPresented: $showingRecentActivity) {
            RecentActivitySummaryView(report: report)
        }
    }
}

/// The two lenses on the selected year the bottom pill zooms between.
private enum YearMode: String, Hashable, CaseIterable {
    case calendar
    case timeline

    var title: String {
        switch self {
            case .calendar: Strings.primaryCalendar
            case .timeline: Strings.primaryTimeline
        }
    }

    var systemImage: String {
        switch self {
            case .calendar: "calendar"
            case .timeline: "calendar.day.timeline.left"
        }
    }
}

/// A floating Liquid Glass pill (Photos-style) switching the Your Year view
/// between calendar and timeline, with the selection sliding between segments.
private struct YearModePicker: View {
    @Binding var mode: YearMode

    @Namespace private var selection
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.xxSmall) {
            ForEach(YearMode.allCases, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(stylesheet.spacing.small)
        // A single selection capsule that follows the selected segment's frame,
        // so changing selection slides it across (rather than a per-segment
        // capsule fading in/out). Real black in light mode / white in dark — it
        // sits *above* the glass layer (below) so the glass doesn't frost it grey.
        .background {
            Capsule()
                .fill(Color.primary)
                .matchedGeometryEffect(id: mode, in: selection, isSource: false)
        }
        .background {
            Color.clear.glassEffect(.regular, in: .capsule)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.yearSegmentPickerLabel)
    }

    private func segment(_ candidate: YearMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = candidate }
        } label: {
            Label(candidate.title, systemImage: candidate.systemImage)
                .labelStyle(.titleAndIcon)
                .imageScale(.large)
                .font(.subheadline.weight(.medium))
                // Keep the label at its intrinsic width so it never truncates
                // while the segment's frame animates.
                .fixedSize()
                .padding(.horizontal, stylesheet.spacing.medium)
                .padding(.vertical, stylesheet.spacing.small)
                // Contrast against the black/white selection capsule.
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: candidate, in: selection, isSource: true)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#if DEBUG
    #Preview("Loaded") {
        YearView(report: PreviewSupport.loadedYearReportModel())
    }

    #Preview("Empty") {
        YearView(report: PreviewSupport.emptyYearReportModel())
    }
#endif
