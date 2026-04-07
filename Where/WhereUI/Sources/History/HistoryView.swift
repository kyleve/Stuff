import SwiftUI

struct HistoryView: View {
    let viewModel: RootViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Available Years") {
                    ForEach(viewModel.availableYears, id: \.self) { year in
                        Button {
                            Task {
                                await viewModel.selectYear(year)
                            }
                        } label: {
                            HStack {
                                Text(String(year))
                                Spacer()
                                if year == viewModel.selectedYear {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                if let snapshot = viewModel.snapshot {
                    Section("Recent History") {
                        ForEach(snapshot.recentDays) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(day.dateLabel)
                                Text(day.jurisdictions.map(\.displayName).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .accessibilityIdentifier("where_history")
        }
    }
}
