import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data.
/// A floating Liquid Glass pill at the bottom (Photos-style) zooms between the
/// calendar (month detail) and the timeline (year overview).
struct YearView: View {
    let report: YearReportModel

    @State private var navigation: SceneNavigationModel.Year

    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, navigation: SceneNavigationModel.Year) {
        self.report = report
        _navigation = State(initialValue: navigation)
    }

    init(report: YearReportModel, initialMode: YearMode = .calendar) {
        self.init(report: report, navigation: SceneNavigationModel.Year(mode: initialMode))
    }

    var body: some View {
        AdaptiveHistoryContainer { arrangement in
            switch arrangement {
                case .compact:
                    YearCompactView(report: report, navigation: navigation)
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
                                        history: navigation.history,
                                    )
                                }
                        }
                    }
            }
        }
        .modifier(PlanningPresentation(report: report, navigation: navigation.history.planning))
    }

    private func calendar(presentation: CalendarContentView.Presentation) -> some View {
        CalendarContentView(
            report: report,
            history: navigation.history,
            presentation: presentation,
            persistenceKey: .year,
        )
        .navigationTitle(String(localized: .primaryCalendar))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeline(presentation: PresenceTimelineList.Presentation) -> some View {
        PresenceTimelineList(
            report: report,
            presentation: presentation,
            history: navigation.history,
        )
        .navigationTitle(String(localized: .primaryTimeline))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The single-pane production presentation, also captured in full for content completeness.
struct YearCompactView: View {
    let report: YearReportModel
    @State private var navigation: SceneNavigationModel.Year
    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, navigation: SceneNavigationModel.Year? = nil) {
        self.report = report
        _navigation = State(initialValue: navigation ?? SceneNavigationModel.Year())
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack {
            Group {
                switch navigation.mode {
                    case .calendar:
                        CalendarContentView(
                            report: report,
                            history: navigation.history,
                            persistenceKey: .year,
                        )
                    case .timeline:
                        PresenceTimelineList(report: report, history: navigation.history)
                }
            }
            // Crossfade between the two views rather than hard-cutting.
            .animation(.default, value: navigation.mode)
            .navigationTitle(navigation.mode.title)
            .navigationBarTitleDisplayMode(.inline)
            // Keep the bar background on at all times. The calendar auto-scrolls
            // under the bar (so its scroll-edge material is showing) while the
            // timeline starts at the top; without pinning it, switching between
            // them animates that material in/out — reading as a toolbar fade.
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, alignment: .center) {
                YearModePicker(mode: $navigation.mode)
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
