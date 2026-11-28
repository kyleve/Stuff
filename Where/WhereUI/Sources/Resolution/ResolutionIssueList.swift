import PeriscopeCore
import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

struct ResolutionIssueList: View {
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
        List {
            if let error = resolve.loadError {
                Section {
                    Label(error, systemSymbol: .exclamationmarkTriangle)
                }
            }
            if !resolve.pendingReviews.isEmpty {
                FlightReviewSection(
                    title: String(localized: .flightStatusPendingSection),
                    reviews: resolve.pendingReviews,
                    report: report,
                )
            }
            ForEach(DataIssueCategory.allCases, id: \.self) { category in
                ResolutionCategorySection(category: category, report: report, resolve: resolve)
            }
            if !resolve.completedReviews.isEmpty {
                FlightReviewSection(
                    title: String(localized: .flightStatusCompletedSection),
                    reviews: resolve.completedReviews,
                    report: report,
                )
            }
        }
        .refreshable { await report.rescanForIssues() }
        .accessibilityIdentifier("where_resolution_list")
    }
}

private struct ResolutionCategorySection: View {
    let category: DataIssueCategory
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
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

private struct FlightReviewSection: View {
    let title: String
    let reviews: [GPSCorrectionReview]
    let report: YearReportModel

    var body: some View {
        Section(title) {
            ForEach(reviews) { review in
                FlightReviewLink(review: review, report: report)
            }
        }
    }
}

private struct FlightReviewLink: View {
    let review: GPSCorrectionReview
    let report: YearReportModel

    var body: some View {
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
}

private struct IssueRow: View {
    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationLink {
            ResolutionIssueDestination(issue: issue, report: report, resolve: resolve)
        } label: {
            ResolutionIssueLabel(title: title, subtitle: subtitle)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if issue.isDismissible {
                DismissIssueButton(issue: issue, resolve: resolve)
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

private struct ResolutionIssueLabel: View {
    @Environment(\.stylesheet) private var stylesheet
    let title: String
    let subtitle: String?

    var body: some View {
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
}

private struct DismissIssueButton: View {
    let issue: any DataIssue
    let resolve: ResolveModel

    var body: some View {
        Button(role: .destructive) {
            Task { await resolve.dismiss(issue) }
        } label: {
            Label(String(localized: .resolutionDismiss), systemSymbol: .xmark)
        }
    }
}

private struct ResolutionIssueDestination: View {
    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
        switch issue.resolution {
            case let .backfill(range):
                ManualDayView(report: report, mode: .add(prefill: range))
            case .markTravelDay:
                AbruptChangeDetailView(issue: issue, report: report, resolve: resolve)
            case let .correctSamples(proposal):
                if let review = resolve.review(for: issue) {
                    FlightDayDetailView(review: review, report: report)
                } else {
                    MissingFlightReview(day: proposal.day, report: report)
                }
        }
    }
}

private struct MissingFlightReview: View {
    let day: DayPresence
    let report: YearReportModel

    var body: some View {
        ContentUnavailableView {
            Label(String(localized: .commonLoadErrorTitle), systemSymbol: .infoCircle)
        } description: {
            Text(String(localized: .flightReviewUnavailable))
        } actions: {
            NavigationLink(String(localized: .flightReviewManualEdit)) {
                DayRelabelView(day: day, report: report)
            }
        }
    }
}

#if DEBUG
    #Preview { ResolutionView.snapshotPreviews }
#endif
