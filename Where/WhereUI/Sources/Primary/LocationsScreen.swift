import SFSafeSymbols
import SwiftUI
import WhereCore

struct LocationsScreen: View {
    let report: YearReportModel
    let navigation: LocationsView.Navigation
    let cardPresentation: LocationCardsPresentationModel
    let tilt: TiltProvider
    let calendarTransition: Namespace.ID
    let cardVariant: WhereStylesheet.CardStyle.Variant
    let showsSelection: Bool
    let isCardSurfaceUncovered: Bool
    @Binding var isCardSurfaceVisible: Bool
    let openPlanning: () -> Void
    let openElsewhere: (() -> Void)?

    var body: some View {
        switch report.loadState {
            case .loading where report.report == nil, .failed where report.report == nil:
                LocationsStateView(
                    report: report,
                    planningAction: openPlanning,
                    openReview: { navigation.flightReview = $0 },
                    openElsewhere: openElsewhere,
                )
            case .idle, .loaded, .loading, .failed:
                if report.locationRegions.isEmpty {
                    LocationsStateView(
                        report: report,
                        planningAction: openPlanning,
                        openReview: { navigation.flightReview = $0 },
                        openElsewhere: openElsewhere,
                    )
                } else {
                    LocationsCardsView(
                        report: report,
                        cardPresentation: cardPresentation,
                        tilt: tilt,
                        calendarTransition: calendarTransition,
                        isCardSurfaceUncovered: isCardSurfaceUncovered,
                        isCardSurfaceVisible: $isCardSurfaceVisible,
                        planningAction: openPlanning,
                        navigation: navigation,
                        cardVariant: cardVariant,
                        showsSelection: showsSelection,
                    )
                }
        }
    }
}

/// Bounds loading, failure, and empty-state construction separately from the
/// navigation shell. Keep the state payload behind its own view boundary.
struct LocationsStateView: View {
    let report: YearReportModel
    let planningAction: () -> Void
    var openReview: ((GPSCorrectionReview) -> Void)?
    var openElsewhere: (() -> Void)?

    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        ScrollView {
            VStack(spacing: spacing.xxLarge) {
                LocationsFlightNotice(report: report, openReview: openReview)
                LocationsStateContent(
                    report: report,
                    planningAction: planningAction,
                    openElsewhere: openElsewhere,
                )
            }
            .padding()
            .whereContentRoot()
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(report.liveFlightReview == nil ? .center : .top, for: .alignment)
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            LocationsStateView(report: PreviewSupport.emptyYearReportModel(), planningAction: {})
        }
        .whereBroadwayRoot()
    }
#endif

/// The payload for a short Locations state; the parent owns the flight notice.
struct LocationsStateContent: View {
    let report: YearReportModel
    let planningAction: () -> Void
    var openElsewhere: (() -> Void)?

    var body: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            case let .failed(error):
                LocationsLoadFailure(message: error.message)
            case .idle, .loaded, .loading:
                // Tracked days outside configured primary regions still need the Elsewhere state.
                if report.trackedDayCount == 0 {
                    LocationsEmptyState(report: report, planningAction: planningAction)
                } else {
                    LocationsElsewhereOnlyState(
                        report: report,
                        planningAction: planningAction,
                        openElsewhere: openElsewhere,
                    )
                }
        }
    }
}

private struct LocationsLoadFailure: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .commonLoadErrorTitle),
                systemSymbol: .exclamationmarkIcloud,
            )
        } description: {
            Text(message)
        }
    }
}

private struct LocationsEmptyState: View {
    let report: YearReportModel
    let planningAction: () -> Void
    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        ScrollView {
            VStack(spacing: spacing.large) {
                LocationsEmptyMessage(year: report.selectedYear)
                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
        }
    }
}

private struct LocationsEmptyMessage: View {
    let year: Int

    var body: some View {
        ContentUnavailableView {
            Label(
                WhereFormat.primaryEmptyTitle(year: year),
                systemSymbol: .map,
            )
        } description: {
            Text(String(localized: .primaryEmptyDescription))
        }
    }
}

private struct LocationsElsewhereOnlyState: View {
    let report: YearReportModel
    let planningAction: () -> Void
    @Environment(\.stylesheet.spacing) private var spacing
    let openElsewhere: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: spacing.large) {
                LocationsElsewhereMessage(report: report, openElsewhere: openElsewhere)
                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
        }
    }
}

private struct LocationsElsewhereMessage: View {
    let report: YearReportModel
    let openElsewhere: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .primaryElsewhereOnlyTitle),
                systemSymbol: .globeAmericas,
            )
        } description: {
            Text(WhereFormat.primaryElsewhereOnlyDescription(count: report.trackedDayCount))
        } actions: {
            if report.hasElsewhere, let openElsewhere {
                Button(String(localized: .primaryElsewhereOnlyOpen), action: openElsewhere)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

#if DEBUG
    #Preview {
        LocationsStateContent(report: PreviewSupport.emptyYearReportModel(), planningAction: {})
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    #Preview("Locations loading and cards") {
        LocationsView(report: PreviewSupport.loadedYearReportModel())
            .whereBroadwayRoot()
    }
#endif
