import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Lists actionable corrections and retained flight reviews from one scene scan.
struct ResolutionView: View {
    let report: YearReportModel
    @State private var resolve: ResolveModel
    @Environment(\.dismiss) private var dismiss

    init(report: YearReportModel) {
        self.report = report
        _resolve = State(initialValue: ResolveModel(
            services: report.services,
            source: report,
        ))
    }

    init(report: YearReportModel, resolve: ResolveModel) {
        self.report = report
        _resolve = State(initialValue: resolve)
    }

    var body: some View {
        NavigationStack {
            ResolutionContent(report: report, resolve: resolve)
                .navigationTitle(String(localized: .resolutionTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { dismiss() }
                    }
                }
                .task(id: report.dataIssueScanInputs) {
                    await resolve.load(
                        year: report.selectedYear,
                        primaryRegions: report.ranking.primary.map(\.region),
                    )
                }
        }
        // Log View Mode: reveal an inspect badge for data-issue resolution
        // events. A no-op in release.
        .debugLogInspectable(WhereLog.session(ResolveModelLog.self))
    }
}

private struct ResolutionContent: View {
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            case let .failed(error):
                ReportLoadFailure(message: error.message)
            case .idle, .loaded, .loading:
                if !resolve.hasLoaded {
                    // The report is loaded but this tab's own scan hasn't landed
                    // yet; show the loading state rather than flash "all clear"
                    // under a non-zero badge.
                    AppIconLoadingView(caption: String(localized: .primaryLoading))
                } else if let error = resolve.loadError, resolve.dataIssues.isEmpty,
                          resolve.reviews.isEmpty
                {
                    IssueScanFailure(error: error, report: report)
                } else if resolve.dataIssues.isEmpty, resolve.reviews.isEmpty {
                    NoResolutionIssues()
                } else {
                    ResolutionIssueList(report: report, resolve: resolve)
                }
        }
    }
}

private struct ReportLoadFailure: View {
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

private struct IssueScanFailure: View {
    let error: String
    let report: YearReportModel

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .commonLoadErrorTitle),
                systemSymbol: .exclamationmarkTriangle,
            )
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: .commonRetry)) {
                Task { await report.rescanForIssues() }
            }
        }
    }
}

private struct NoResolutionIssues: View {
    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .resolutionEmptyTitle),
                systemSymbol: .checkmarkSeal,
            )
        } description: {
            Text(String(localized: .resolutionEmptyDescription))
        }
    }
}

#if DEBUG
    extension ResolutionView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithIssues", configurations: .fullContentScreenRepresentative) {
                ResolutionView(
                    report: PreviewSupport.loadedYearReportModel(),
                    resolve: PreviewSupport.resolveModel(),
                )
            }
            for state in [FlightReviewPreviewState.waiting, .ready, .completed] {
                whereSnapshot(name: state.rawValue, configurations: .fullContentPhoneLightDark) {
                    ResolutionView(
                        report: PreviewSupport.flightYearReportModel(state: state),
                        resolve: PreviewSupport.flightResolveModel(state: state),
                    )
                }
            }
            whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                ResolutionView(
                    report: PreviewSupport.loadedYearReportModel(),
                    resolve: PreviewSupport.resolveModel(seededWithIssues: false),
                )
            }
        }
    }

    #Preview {
        ResolutionView.snapshotPreviews
    }
#endif

#if DEBUG
    extension ResolutionView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            ResolutionView.self,
            title: "Resolve",
            routes: [
                .push(to: ManualDayView.flyoverID),
                .push(to: DayRelabelView.flyoverID),
                .push(to: AbruptChangeDetailView.flyoverID),
                .push(to: FlightDayDetailView.flyoverID),
            ],
        )
    }
#endif
