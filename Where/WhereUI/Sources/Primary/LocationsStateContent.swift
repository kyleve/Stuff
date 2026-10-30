import SFSafeSymbols
import SwiftUI

/// The payload for a short Locations state; the parent owns the flight notice.
struct LocationsStateContent: View {
    let report: YearReportModel
    let planningAction: () -> Void
    var openElsewhere: (() -> Void)?

    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            case let .failed(error):
                ContentUnavailableView {
                    Label(
                        String(localized: .commonLoadErrorTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
                } description: {
                    Text(error.message)
                }
            case .idle, .loaded, .loading:
                // Tracked days outside configured primary regions still need the Elsewhere state.
                if report.trackedDayCount == 0 {
                    emptyState
                } else {
                    elsewhereOnlyState
                }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: spacing.large) {
                ContentUnavailableView {
                    Label(
                        WhereFormat.primaryEmptyTitle(year: report.selectedYear),
                        systemSymbol: .map,
                    )
                } description: {
                    Text(String(localized: .primaryEmptyDescription))
                }
                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
        }
    }

    private var elsewhereOnlyState: some View {
        ScrollView {
            VStack(spacing: spacing.large) {
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
                LocationsEstimatePanel(report: report, planningAction: planningAction)
            }
            .padding()
        }
    }
}

#if DEBUG
    #Preview {
        LocationsStateContent(report: PreviewSupport.emptyYearReportModel(), planningAction: {})
            .whereBroadwayRoot()
    }
#endif
