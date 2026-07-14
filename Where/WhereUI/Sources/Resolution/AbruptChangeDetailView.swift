import RegionKit
import SwiftUI
import WhereCore

/// Detail screen for an abrupt location change: explains the likely missing
/// travel day and offers relabel paths for either adjacent day.
struct AbruptChangeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet

    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    var body: some View {
        if let payload = travelDayPayload {
            Form {
                Section {
                    Text(Strings.resolutionAbruptDetailExplanation)
                }

                Section(Strings.resolutionAbruptDetailEarlierHeader) {
                    daySummary(payload.earlier)
                    NavigationLink {
                        DayRelabelView(
                            day: payload.earlier,
                            report: report,
                            initialRegions: payload.suggested,
                            reason: .travelDay,
                        )
                    } label: {
                        Text(Strings.resolutionAbruptDetailRelabelEarlier)
                    }
                }

                Section(Strings.resolutionAbruptDetailLaterHeader) {
                    daySummary(payload.later)
                    NavigationLink {
                        DayRelabelView(
                            day: payload.later,
                            report: report,
                            initialRegions: payload.suggested,
                            reason: .travelDay,
                        )
                    } label: {
                        Text(Strings.resolutionAbruptDetailRelabelLater)
                    }
                }

                Section {
                    Button(Strings.resolutionAbruptDetailBothRight) {
                        Task {
                            await resolve.dismiss(issue)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(Strings.resolutionAbruptDetailTitle)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                Strings.loadErrorTitle,
                systemImage: "exclamationmark.triangle",
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

    private func daySummary(_ day: DayPresence) -> some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(day.date.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.headline)
            Text(day.regions.map(\.localizedName).sorted().joined(separator: ", "))
                .foregroundStyle(.secondary)
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
                        regions: [.california],
                    ),
                    laterDay: DayPresence(
                        date: .now,
                        regions: [.newYork],
                    ),
                ),
                report: PreviewSupport.loadedYearReportModel(),
                resolve: PreviewSupport.resolveModel(),
            )
        }
    }
#endif
