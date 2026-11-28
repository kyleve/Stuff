import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// Detail screen for an abrupt location change: explains the likely missing
/// travel day and offers relabel paths for either adjacent day.
struct AbruptChangeDetailView: View {
    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
        if let payload = travelDayPayload {
            Form {
                Section {
                    Text(String(localized: .resolutionAbruptDetailExplanation))
                }

                AdjacentTravelDaySection(
                    title: String(localized: .resolutionAbruptDetailEarlier),
                    linkTitle: String(localized: .resolutionAbruptDetailRelabelEarlier),
                    day: payload.earlier,
                    suggested: payload.suggested,
                    report: report,
                )

                AdjacentTravelDaySection(
                    title: String(localized: .resolutionAbruptDetailLater),
                    linkTitle: String(localized: .resolutionAbruptDetailRelabelLater),
                    day: payload.later,
                    suggested: payload.suggested,
                    report: report,
                )

                Section {
                    ConfirmTravelDaysButton(issue: issue, resolve: resolve)
                }
            }
            .navigationTitle(String(localized: .resolutionAbruptDetailTitle))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                String(localized: .commonLoadErrorTitle),
                systemSymbol: .exclamationmarkTriangle,
            )
        }
    }

    private var travelDayPayload: (
        earlier: DayPresence,
        later: DayPresence,
        suggested: Set<Region>,
    )? {
        if case let .markTravelDay(earlier, later, suggested) = issue.resolution {
            return (earlier, later, suggested)
        }
        return nil
    }
}

private struct AdjacentTravelDaySection: View {
    let title: String
    let linkTitle: String
    let day: DayPresence
    let suggested: Set<Region>
    let report: YearReportModel

    var body: some View {
        Section(title) {
            TravelDaySummary(day: day)
            NavigationLink {
                DayRelabelView(
                    day: day,
                    report: report,
                    initialRegions: suggested,
                    reason: .travelDay,
                )
            } label: {
                Text(linkTitle)
            }
        }
    }
}

private struct TravelDaySummary: View {
    @Environment(\.stylesheet) private var stylesheet
    let day: DayPresence

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(day.displayDate.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.headline)
            Text(day.regions.map(\.localizedName).sorted().joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConfirmTravelDaysButton: View {
    @Environment(\.dismiss) private var dismiss
    let issue: any DataIssue
    let resolve: ResolveModel

    var body: some View {
        Button(String(localized: .resolutionAbruptDetailBothRight)) {
            Task {
                await resolve.dismiss(issue)
                dismiss()
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            AbruptChangeDetailView(
                issue: AbruptChangeIssue(
                    earlierDay: DayPresence(
                        date: .now,
                        in: .current,
                        regions: [.california],
                    ),
                    laterDay: DayPresence(
                        date: Date().addingTimeInterval(86400),
                        in: .current,
                        regions: [.newYork],
                    ),
                ),
                report: PreviewSupport.loadedYearReportModel(),
                resolve: PreviewSupport.resolveModel(),
            )
        }
    }
#endif

#if DEBUG
    extension AbruptChangeDetailView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AbruptChangeDetailView.self,
            title: "Abrupt Change",
            routes: [
                .push(to: DayRelabelView.flyoverID),
            ],
        ) { world in
            AbruptChangeDetailView(
                issue: AbruptChangeIssue(
                    earlierDay: DayPresence(
                        date: PreviewSupport.referenceNow,
                        in: world.report.calendar,
                        regions: [.california],
                    ),
                    laterDay: DayPresence(
                        date: PreviewSupport.referenceNow.addingTimeInterval(86400),
                        in: world.report.calendar,
                        regions: [.newYork],
                    ),
                ),
                report: world.report,
                resolve: PreviewSupport.resolveModel(),
            )
        }
    }
#endif
