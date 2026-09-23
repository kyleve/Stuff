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
            preferences: report.preferences,
        ))
    }

    #if DEBUG
        /// Preview/test seam: inject a `ResolveModel` seeded via
        /// `@_spi(Testing) setDataIssues` so the list renders without raw samples.
        init(report: YearReportModel, resolve: ResolveModel) {
            self.report = report
            _resolve = State(initialValue: resolve)
        }
    #endif

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle(String(localized: .resolutionTitle))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .commonDone)) { dismiss() }
                    }
                }
                .task(id: report.dataIssueScanInputs) {
                    if report.dataIssueScan == nil, report.dataIssueScanError == nil {
                        await report.refreshDataIssueCount(force: false)
                    }
                    guard !Task.isCancelled else { return }
                    resolve.receive(scan: report.dataIssueScan, error: report.dataIssueScanError)
                }
        }
        // Log View Mode: reveal an inspect badge for data-issue resolution
        // events. A no-op in release.
        .debugLogInspectable(WhereLog.session(ResolveModelLog.self))
    }

    @ViewBuilder
    private var screen: some View {
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
                if !resolve.hasLoaded {
                    // The report is loaded but this tab's own scan hasn't landed
                    // yet; show the loading state rather than flash "all clear"
                    // under a non-zero badge.
                    AppIconLoadingView(caption: String(localized: .primaryLoading))
                } else if let error = resolve.loadError, resolve.dataIssues.isEmpty,
                          resolve.reviews.isEmpty
                {
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
                } else if resolve.dataIssues.isEmpty, resolve.reviews.isEmpty {
                    ContentUnavailableView {
                        Label(
                            String(localized: .resolutionEmptyTitle),
                            systemSymbol: .checkmarkSeal,
                        )
                    } description: {
                        Text(String(localized: .resolutionEmptyDescription))
                    }
                } else {
                    issueList
                }
        }
    }

    private var issueList: some View {
        List {
            if let error = resolve.loadError {
                Section {
                    Label(error, systemSymbol: .exclamationmarkTriangle)
                }
            }
            if !resolve.pendingReviews.isEmpty {
                Section(String(localized: .flightStatusPendingSection)) {
                    ForEach(resolve.pendingReviews) { review in
                        reviewLink(review)
                    }
                }
            }
            ForEach(DataIssueCategory.allCases, id: \.self) { category in
                let issues = issues(in: category)
                if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.id) { issue in
                            IssueRow(issue: issue, report: report, resolve: resolve)
                        }
                    } header: {
                        Label(
                            WhereFormat.resolutionSectionHeader(category),
                            systemSymbol: sectionIcon(category),
                        )
                    }
                }
            }
            if !resolve.completedReviews.isEmpty {
                Section(String(localized: .flightStatusCompletedSection)) {
                    ForEach(resolve.completedReviews) { review in
                        reviewLink(review)
                    }
                }
            }
        }
        .refreshable { await report.rescanForIssues() }
        .accessibilityIdentifier("where_resolution_list")
    }

    private func reviewLink(_ review: GPSCorrectionReview) -> some View {
        NavigationLink {
            FlightDayDetailView(review: review, report: report)
        } label: {
            VStack(alignment: .leading) {
                Text(review.day.displayDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)
                FlightStatusBanner(
                    review: review,
                    deviceLabel: review.flight.map(report.flightDeviceLabel),
                )
            }
        }
    }

    private func issues(in category: DataIssueCategory) -> [any DataIssue] {
        resolve.dataIssues.filter { $0.category == category }
    }

    private func sectionIcon(_ category: DataIssueCategory) -> SFSymbol {
        switch category {
            case .missingDays: .calendarBadgeExclamationmark
            case .borderDrift: .locationCircle
            case .abruptChange: .arrowTriangleSwap
            case .flightDay: .airplane
        }
    }
}

private struct IssueRow: View {
    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, stylesheet.spacing.xSmall)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if issue.isDismissible {
                Button(role: .destructive) {
                    Task { await resolve.dismiss(issue) }
                } label: {
                    Label(String(localized: .resolutionDismiss), systemSymbol: .xmark)
                }
            }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch issue.resolution {
            case let .backfill(range):
                ManualDayView(report: report, mode: .add(prefill: range))
            case .markTravelDay:
                AbruptChangeDetailView(issue: issue, report: report, resolve: resolve)
            case let .correctSamples(proposal):
                if let review = resolve.review(for: issue) {
                    FlightDayDetailView(review: review, report: report)
                } else {
                    ContentUnavailableView {
                        Label(String(localized: .commonLoadErrorTitle), systemSymbol: .infoCircle)
                    } description: {
                        Text(String(localized: .flightReviewUnavailable))
                    } actions: {
                        NavigationLink(String(localized: .flightReviewManualEdit)) {
                            DayRelabelView(day: proposal.day, report: report)
                        }
                    }
                }
        }
    }

    private var title: String {
        switch issue.resolution {
            case let .backfill(range):
                DateRangeFormatting.abbreviated(start: range.start, end: range.end)
            case let .markTravelDay(earlier, later, _):
                WhereFormat.resolutionAbruptRowTitle(
                    earlier: earlier.regions,
                    later: later.regions,
                )
            case let .correctSamples(proposal):
                proposal.day.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var subtitle: String? {
        switch issue.resolution {
            case let .backfill(range):
                WhereFormat.dayCount(range.dayCount)
            case let .markTravelDay(_, later, _):
                later.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
            case .correctSamples:
                String(localized: .flightStatusReadyTitle)
        }
    }
}

#if DEBUG
    extension ResolutionView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "WithIssues", configurations: .fullContentScreenDefaults) {
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
