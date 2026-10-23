import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Your Year tab: the selected year's calendar and timeline for the same data.
/// Swipe between the calendar (month detail) and timeline (year overview), or
/// select either page with the floating Liquid Glass pill at the bottom.
struct YearView: View {
    let report: YearReportModel

    @State private var mode: YearMode

    init(report: YearReportModel, initialMode: YearMode = .calendar) {
        self.report = report
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $mode) {
                CalendarContentView(report: report, showsPlanningToolbar: false)
                    .tag(YearMode.calendar)
                PresenceTimelineList(report: report, showsPlanningToolbar: false)
                    .tag(YearMode.timeline)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .modifier(YearNavigationModifier(report: report, mode: $mode))
        }
    }
}

/// Shared navigation chrome for the pager and full-content captures of its pages.
private struct YearNavigationModifier: ViewModifier {
    let report: YearReportModel
    @Binding var mode: YearMode

    @Environment(\.stylesheet) private var stylesheet
    @State private var planningDestination: PlannedStaysDestination?

    func body(content: Content) -> some View {
        content
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            // Keep the material steady while paging between vertical scroll views.
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if report.showsEstimatedTimeAndPlanning {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(
                            String(localized: .plannedStaysTitle),
                            systemSymbol: .calendarBadgeClock,
                        ) {
                            planningDestination = .list
                        }
                    }
                }
            }
            .sheet(item: $planningDestination) { destination in
                PlannedStaysDestinationView(destination: destination, report: report)
            }
            .safeAreaInset(edge: .bottom, alignment: .center) {
                YearModePicker(mode: $mode)
                    .padding(.bottom, stylesheet.spacing.xLarge)
            }
    }
}

/// The two pages of the selected year, shared by the pager and bottom picker.
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
        /// Capture the shared scrolling child and chrome directly: expanding the
        /// native pager to full content distorts its viewport and accessibility tree.
        /// `YearViewTests` exercises paging; `PresenceTimelineList` owns timeline images.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Loaded",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                let report = PreviewSupport.loadedYearReportModel()
                NavigationStack {
                    CalendarContentView(report: report, showsPlanningToolbar: false)
                        .modifier(YearNavigationModifier(
                            report: report,
                            mode: .constant(.calendar),
                        ))
                }
            }
            whereSnapshot(
                name: "Empty",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                let report = PreviewSupport.emptyYearReportModel()
                NavigationStack {
                    CalendarContentView(report: report, showsPlanningToolbar: false)
                        .modifier(YearNavigationModifier(
                            report: report,
                            mode: .constant(.calendar),
                        ))
                }
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
