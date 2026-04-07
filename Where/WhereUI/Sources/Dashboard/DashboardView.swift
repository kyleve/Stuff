import SwiftUI
import WhereCore

struct DashboardView: View {
    let viewModel: RootViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot = viewModel.snapshot {
                    List {
                        Section("Year to Date") {
                            ForEach(snapshot.primarySummaries) { summary in
                                SummaryRow(summary: summary)
                            }
                        }

                        if !snapshot.secondarySummaries.isEmpty {
                            Section("Needs Review") {
                                ForEach(snapshot.secondarySummaries) { summary in
                                    SummaryRow(summary: summary)
                                }
                            }
                        }

                        Section("Tracking") {
                            LabeledContent("Status", value: snapshot.trackingStatus.title)
                        }

                        Section("Recent Days") {
                            ForEach(snapshot.recentDays) { day in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(day.dateLabel)
                                        .font(.headline)

                                    Text(day.jurisdictions.map(\.displayName).joined(separator: ", "))
                                        .foregroundStyle(.secondary)

                                    if let note = day.note {
                                        Text(note)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .accessibilityIdentifier("where_dashboard")
                } else if viewModel.isLoading {
                    ProgressView("Loading tracking data...")
                        .accessibilityIdentifier("where_loading")
                } else {
                    ContentUnavailableView(
                        "No Tracking Data",
                        systemImage: "location.slash",
                        description: Text("Open the app regularly while background tracking is being set up."),
                    )
                }
            }
            .navigationTitle("Where")
        }
    }
}

private struct SummaryRow: View {
    let summary: YearProgressSnapshot.JurisdictionSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.jurisdiction.displayName)
                Text(summary.jurisdiction.abbreviation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(summary.totalDays, format: .number)
                .font(.title3.monospacedDigit())
        }
    }
}
