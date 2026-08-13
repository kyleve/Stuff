import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Your Year tab: a composed annual cover that opens into the calendar/timeline
/// ledger through Where's second identity-preserving zoom transition.
struct YearView: View {
    private struct LedgerTransitionID: Hashable {
        let year: Int
    }

    let report: YearReportModel
    private let initialMode: YearMode

    @Namespace private var ledgerTransition

    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, initialMode: YearMode = .calendar) {
        self.report = report
        self.initialMode = initialMode
    }

    var body: some View {
        NavigationStack {
            screen
                .background(stylesheet.palette.brand.canvas.ignoresSafeArea())
                .toolbarBackground(stylesheet.palette.brand.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var screen: some View {
        if let yearReport = report.report {
            let transitionID = LedgerTransitionID(year: report.selectedYear)
            ScrollView {
                NavigationLink {
                    YearLedgerDetailView(report: report, initialMode: initialMode)
                        .navigationTransition(
                            .zoom(sourceID: transitionID, in: ledgerTransition),
                        )
                } label: {
                    StaggeredRevealScope {
                        YearLedgerCover(
                            year: report.selectedYear,
                            summary: YearLedgerSummary(report: yearReport),
                            calendar: report.calendar,
                        )
                    }
                    .id(report.selectedYear)
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: transitionID, in: ledgerTransition) { source in
                    source.clipShape(
                        RoundedRectangle(
                            cornerRadius: stylesheet.year.cover.cornerRadius,
                            style: .continuous,
                        ),
                    )
                }
                .accessibilityHint(String(localized: .yearLedgerOpenHint))
            }
            .contentMargins(
                .horizontal,
                stylesheet.locations.horizontalInset,
                for: .scrollContent,
            )
            .contentMargins(.vertical, stylesheet.spacing.large, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
        } else if case let .failed(error) = report.loadState {
            ContentUnavailableView {
                Label(
                    String(localized: .commonLoadErrorTitle),
                    systemImage: "exclamationmark.icloud",
                )
            } description: {
                Text(error.message)
            }
        } else {
            AppIconLoadingView(caption: String(localized: .primaryLoading))
        }
    }
}

/// The opened annual ledger. It retains functional native navigation chrome
/// and the stable bottom lens selector while its content depth-dissolves.
struct YearLedgerDetailView: View {
    let report: YearReportModel

    @State private var mode: YearMode

    @Environment(\.stylesheet) private var stylesheet

    init(report: YearReportModel, initialMode: YearMode = .calendar) {
        self.report = report
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
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
        .animation(stylesheet.year.motion.contentAnimation, value: mode)
        .background(stylesheet.palette.brand.canvas.ignoresSafeArea())
        .navigationTitle(WhereFormat.yearLedgerTitle(year: report.selectedYear))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(stylesheet.palette.brand.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, alignment: .center) {
            YearModePicker(mode: $mode)
                .padding(.bottom, stylesheet.spacing.xLarge)
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
                name: "Glass",
                theme: .standard,
                configurations: .fullContentPhoneLightDark,
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
