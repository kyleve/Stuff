import SwiftUI
import WhereCore

/// Lists data-quality issues for the selected year and routes each to its fix
/// flow. Badge count comes from `session.dataIssueCount`.
struct ResolutionView: View {
    @Environment(WhereSession.self) private var session

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle(Strings.resolutionTitle)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch session.loadState {
            case .loading where session.report == nil:
                ProgressView(Strings.primaryLoading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.loadErrorTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
            case .idle, .loaded, .loading:
                if session.dataIssues.isEmpty {
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
                            IssueRow(issue: issue)
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
        session.dataIssues.filter { $0.category == category }
    }

    private func sectionIcon(_ category: DataIssueCategory) -> String {
        switch category {
            case .missingDays: "calendar.badge.exclamationmark"
            case .borderDrift: "location.circle"
            case .abruptChange: "arrow.triangle.swap"
        }
    }
}

private struct IssueRow: View {
    @Environment(WhereSession.self) private var session

    let issue: any DataIssue

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, UIConstants.Spacings.xSmall)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if issue.isDismissible {
                Button(role: .destructive) {
                    Task { await session.dismiss(issue) }
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
                ManualDayEntryView(prefill: range)
            case let .relabelDay(day, suggested, _):
                DayRelabelView(day: day, initialRegions: suggested)
            case .markTravelDay:
                AbruptChangeDetailView(issue: issue)
        }
    }

    private var title: String {
        switch issue.resolution {
            case let .backfill(range):
                DateRangeFormatting.abbreviated(start: range.start, end: range.end)
            case let .relabelDay(day, _, _):
                day.date.formatted(.dateTime.month(.abbreviated).day().year())
            case let .markTravelDay(earlier, later, _):
                Strings.resolutionAbruptRowTitle(
                    earlier: earlier.regions,
                    later: later.regions,
                )
        }
    }

    private var subtitle: String? {
        switch issue.resolution {
            case let .backfill(range):
                Strings.dayCount(range.dayCount)
            case let .relabelDay(_, suggested, meters):
                Self.relabelSubtitle(suggested: suggested, meters: meters)
            case let .markTravelDay(_, later, _):
                later.date.formatted(.dateTime.month(.abbreviated).day().year())
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
        ResolutionView()
            .environment(PreviewSupport.resolutionSession())
    }

    #Preview("Empty") {
        ResolutionView()
            .environment(PreviewSupport.loadedSession())
    }
#endif
