import BroadwayUI
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
    @State private var history: HistorySelectionModel
    @State private var planningDestination: PlannedStaysDestination?
    @State private var calendarPresentation: CalendarPresentationState

    @Environment(\.stylesheet) private var stylesheet

    init(
        report: YearReportModel,
        initialMode: YearMode = .calendar,
        history: HistorySelectionModel? = nil,
    ) {
        self.report = report
        _mode = State(initialValue: initialMode)
        _history = State(initialValue: history ?? HistorySelectionModel())
        _calendarPresentation = State(initialValue: CalendarPresentationState(mode: CalendarModel(
            report: report,
            persistenceKey: .year,
        ).isOverview(fallback: false) ? .overview : .detail))
    }

    var body: some View {
        AdaptiveHistoryContainer { arrangement in
            switch arrangement {
                case .compact:
                    YearCompactContent(
                        report: report,
                        mode: $mode,
                        history: history,
                        calendarPresentation: calendarPresentation,
                        planningDestination: $planningDestination,
                    )
                case .columns:
                    NavigationSplitView(columnVisibility: .constant(.all)) {
                        timeline(presentation: .linked)
                            .navigationSplitViewColumnWidth(
                                min: stylesheet.adaptiveHistory.minimumControlsWidth,
                                ideal: stylesheet.adaptiveHistory.minimumControlsWidth,
                            )
                    } detail: {
                        calendar(presentation: .year)
                            .navigationSplitViewColumnWidth(
                                min: stylesheet.adaptiveHistory.minimumHistoryWidth,
                                ideal: stylesheet.adaptiveHistory.minimumHistoryWidth,
                            )
                    }
                    .navigationSplitViewStyle(.balanced)
                case let .tabletop(panes):
                    TabletopHistoryLayout(panes: panes) {
                        NavigationStack { calendar(presentation: .month) }
                    } controls: {
                        NavigationStack {
                            timeline(presentation: .linked)
                                .safeAreaInset(edge: .top, spacing: 0) {
                                    HistoryMonthControls(
                                        report: report,
                                        history: history,
                                    )
                                }
                        }
                    }
            }
        }
        .modifier(PlanningPresentation(report: report, destination: $planningDestination))
        .onChange(of: report.selectedYear) { history.reset() }
    }

    private func calendar(presentation: CalendarContentView.Presentation) -> some View {
        CalendarContentView(
            report: report,
            history: history,
            presentationState: calendarPresentation,
            presentation: presentation,
            persistenceKey: .year,
            scrollRole: .year,
            planningDestination: $planningDestination,
        )
        .navigationTitle(String(localized: .primaryCalendar))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeline(presentation: PresenceTimelineList.Presentation) -> some View {
        PresenceTimelineList(
            report: report,
            presentation: presentation,
            history: history,
            planningDestination: $planningDestination,
        )
        .navigationTitle(String(localized: .primaryTimeline))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The single-pane production presentation, also captured in full for content completeness.
struct YearCompactView: View {
    let report: YearReportModel
    @State private var mode = YearMode.calendar
    @State private var history = HistorySelectionModel()
    @State private var planningDestination: PlannedStaysDestination?
    @State private var calendarPresentation: CalendarPresentationState

    init(report: YearReportModel) {
        self.report = report
        _calendarPresentation = State(initialValue: CalendarPresentationState(mode: CalendarModel(
            report: report,
            persistenceKey: .year,
        ).isOverview(fallback: false) ? .overview : .detail))
    }

    var body: some View {
        YearCompactContent(
            report: report,
            mode: $mode,
            history: history,
            calendarPresentation: calendarPresentation,
            planningDestination: $planningDestination,
        )
        .bScrollRestorationScope()
        .modifier(PlanningPresentation(report: report, destination: $planningDestination))
    }
}

private struct YearCompactContent: View {
    let report: YearReportModel
    @Binding var mode: YearMode
    let history: HistorySelectionModel
    let calendarPresentation: CalendarPresentationState
    @Binding var planningDestination: PlannedStaysDestination?
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                    case .calendar:
                        CalendarContentView(
                            report: report,
                            history: history,
                            presentationState: calendarPresentation,
                            persistenceKey: .year,
                            scrollRole: .year,
                            planningDestination: $planningDestination,
                        )
                    case .timeline:
                        PresenceTimelineList(
                            report: report,
                            history: history,
                            planningDestination: $planningDestination,
                        )
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
        let layout = stylesheet.yearModePicker.layout == .stacked
            ? AnyLayout(VStackLayout(spacing: stylesheet.spacing.xxSmall))
            : AnyLayout(HStackLayout(spacing: stylesheet.spacing.xxSmall))

        layout {
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
    }

    private func segment(_ candidate: YearMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            withAnimation(.snappy(duration: 0.28)) { mode = candidate }
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
                configurations: .fullContentScreenRepresentative,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                YearCompactView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(
                name: "Empty",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                YearCompactView(report: PreviewSupport.emptyYearReportModel())
            }
            whereSnapshot(
                name: "RestoredOverview",
                configurations: .fullContentPhoneLightDark,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                let report = PreviewSupport.loadedYearReportModel()
                let _ = report.preferences.setCalendarOverview(true, forKey: .year)
                YearView(report: report)
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
