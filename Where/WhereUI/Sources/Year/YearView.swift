import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data.
/// A floating Liquid Glass pill at the bottom (Photos-style) zooms between the
/// calendar (month detail) and the timeline (year overview).
struct YearView: View {
    let report: YearReportModel

    @State private var mode: YearMode

    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, initialMode: YearMode = .calendar) {
        self.report = report
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                    case .calendar:
                        CalendarContentView(report: report)
                            .transition(stylesheet.year.motion.contentTransition)
                    case .timeline:
                        PresenceTimelineList(report: report)
                            .transition(stylesheet.year.motion.contentTransition)
                }
            }
            // The two representations share no stable cell identity, so a
            // restrained depth dissolve preserves the chrome without inventing
            // a noisy cell-by-cell morph.
            .animation(stylesheet.year.motion.contentAnimation, value: mode)
            .navigationTitle(WhereFormat.yearLedgerTitle(year: report.selectedYear))
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
        }
    }
}

/// The two lenses on the selected year the bottom pill zooms between.
enum YearMode: String, Hashable, CaseIterable {
    case calendar
    case timeline

    var title: String {
        switch self {
            case .calendar: String(localized: .primaryCalendar)
            case .timeline: String(localized: .primaryTimeline)
        }
    }

    var systemSymbol: SFSymbol {
        switch self {
            case .calendar: .calendar
            case .timeline: .calendarDayTimelineLeft
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
        .accessibilityLabel(String(localized: .yearSegmentPicker))
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func segment(_ candidate: YearMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            withAnimation(stylesheet.motion.settle) { mode = candidate }
        } label: {
            Label(candidate.title, systemSymbol: candidate.systemSymbol)
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
    extension YearView: SnapshotProviding {
        /// Timeline rendering is owned by `PresenceTimelineList`'s matrix; the
        /// initializer seam is used by Flyover without duplicating that suite.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                YearView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                YearView(report: PreviewSupport.emptyYearReportModel())
            }
        }
    }

    #Preview {
        YearView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(
            YearView.self,
        ) { id, world in
            .init(
                id: id,
                title: "Your Year",
                navigationContainer: .none,
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "calendar",
                        title: "Calendar",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .calendar)
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "timeline",
                        title: "Timeline",
                        world: world,
                    ) {
                        YearView(report: world.report, initialMode: .timeline)
                    },
                ],
            )
        }
    }
#endif
