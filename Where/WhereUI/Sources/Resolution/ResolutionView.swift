import RegionKit
import SwiftUI
import WhereCore

/// Lists data-quality issues for the selected year and routes each to its fix
/// flow. The scene's `YearReportModel` owns the badge *count*; this view owns the
/// list via a view-scoped `ResolveModel`, re-scanned from a `.task(id:)` keyed
/// on the report's `dataIssueScanInputs` (so it refreshes on appear, on any
/// committed write, on a year switch, and on a drift-threshold change — the same
/// triggers that recompute the badge count).
struct ResolutionView: View {
    let report: YearReportModel
    @State private var resolve: ResolveModel

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
                .navigationTitle(Strings.resolutionTitle)
                .navigationBarTitleDisplayMode(.inline)
                .task(id: report.dataIssueScanInputs) {
                    await resolve.load(
                        year: report.selectedYear,
                        primaryRegions: report.ranking.primary.map(\.region),
                    )
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch report.loadState {
            case .loading where report.report == nil:
                AppIconLoadingView(caption: Strings.primaryLoading)
            case let .failed(error):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error.message)
                }
            case .idle, .loaded, .loading:
                if !resolve.hasLoaded {
                    // The report is loaded but this tab's own scan hasn't landed
                    // yet; show the loading state rather than flash "all clear"
                    // under a non-zero badge.
                    AppIconLoadingView(caption: Strings.primaryLoading)
                } else if resolve.dataIssues.isEmpty {
                    ContentUnavailableView {
                        Label(Strings.resolutionEmptyTitle, systemImage: "checkmark.seal")
                    } description: {
                        Text(Strings.resolutionEmptyDescription)
                    }
                } else {
                    issueList
                }
        }
    }

    private var issueList: some View {
        List {
            ForEach(DataIssueCategory.allCases, id: \.self) { category in
                let issues = issues(in: category)
                if !issues.isEmpty {
                    Section {
                        ForEach(issues, id: \.id) { issue in
                            IssueRow(issue: issue, report: report, resolve: resolve)
                        }
                    } header: {
                        Label(
                            Strings.resolutionSectionHeader(category),
                            systemImage: sectionIcon(category),
                        )
                    }
                }
            }
        }
        .accessibilityIdentifier("where_resolution_list")
    }

    private func issues(in category: DataIssueCategory) -> [any DataIssue] {
        resolve.dataIssues.filter { $0.category == category }
    }

    private func sectionIcon(_ category: DataIssueCategory) -> String {
        switch category {
            case .missingDays: "calendar.badge.exclamationmark"
            case .borderDrift: "location.circle"
            case .abruptChange: "arrow.triangle.swap"
            case .flightDay: "airplane"
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
                    Label(Strings.resolutionDismiss, systemImage: "xmark")
                }
            }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch issue.resolution {
            case let .backfill(range):
                ManualDayView(report: report, mode: .add(prefill: range))
            case let .relabelDay(day, suggested, meters):
                DayRelabelView(
                    day: day,
                    report: report,
                    initialRegions: suggested,
                    reason: .borderDrift(region: suggested.first ?? .other, distanceMeters: meters),
                )
            case .markTravelDay:
                AbruptChangeDetailView(issue: issue, report: report, resolve: resolve)
            case .correctFlightDay:
                FlightDayDetailView(issue: issue, report: report, resolve: resolve)
        }
    }

    private var title: String {
        switch issue.resolution {
            case let .backfill(range):
                DateRangeFormatting.abbreviated(start: range.start, end: range.end)
            case let .relabelDay(day, _, _):
                day.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
            case let .markTravelDay(earlier, later, _):
                Strings.resolutionAbruptRowTitle(
                    earlier: earlier.regions,
                    later: later.regions,
                )
            case let .correctFlightDay(day, _, _, _):
                day.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    private var subtitle: String? {
        switch issue.resolution {
            case let .backfill(range):
                Strings.dayCount(range.dayCount)
            case let .relabelDay(_, suggested, meters):
                Self.relabelSubtitle(suggested: suggested, meters: meters)
            case let .markTravelDay(_, later, _):
                later.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
            case .correctFlightDay:
                Strings.resolutionFlightRowSubtitle
        }
    }

    private static func relabelSubtitle(suggested: Set<Region>, meters: Double?) -> String {
        if let meters {
            let regionName = suggested.first?.localizedName ?? ""
            let distance = Measurement(value: meters, unit: UnitLength.meters)
                .formatted(.measurement(width: .abbreviated, usage: .road))
            return Strings.driftRowSubtitle(region: regionName, distance: distance)
        }
        return suggested.map(\.localizedName).sorted().joined(separator: ", ")
    }
}

#if DEBUG
    #Preview("Loaded") {
        ResolutionView(
            report: PreviewSupport.loadedYearReportModel(),
            resolve: PreviewSupport.resolveModel(),
        )
    }

    #Preview("Empty") {
        ResolutionView(
            report: PreviewSupport.loadedYearReportModel(),
            resolve: PreviewSupport.resolveModel(seededWithIssues: false),
        )
    }
#endif
