import SwiftUI
import WhereCore

/// Lists the calendar days this year with no recorded presence as tappable
/// ranges. Selecting one opens a prefilled `ManualDayEntryView` so the user can
/// backfill where they were. Presented as a sheet from the Primary tab's
/// warning banner.
struct MissingDaysView: View {
    @Environment(WhereModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Strings.missingDaysTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.missingDaysDone) { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.missingDays.isEmpty {
            ContentUnavailableView {
                Label(Strings.missingDaysEmptyTitle, systemImage: "checkmark.circle")
            } description: {
                Text(Strings.missingDaysEmptyDescription)
            }
        } else {
            List {
                Section {
                    ForEach(model.missingDays) { range in
                        NavigationLink {
                            ManualDayEntryView(prefill: range)
                        } label: {
                            MissingDayRow(range: range)
                        }
                    }
                } header: {
                    Text(Strings.missingDaysHeader)
                } footer: {
                    Text(Strings.missingDaysFooter)
                }
            }
            .accessibilityIdentifier("where_missing_days_list")
        }
    }
}

/// One row: the date span that's missing and how many days it covers.
private struct MissingDayRow: View {
    let range: MissingDayRange

    var body: some View {
        HStack(spacing: UIConstants.Spacings.large) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                Text(dateRange)
                    .font(.headline)
                Text(Strings.dayCount(range.dayCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, UIConstants.Spacings.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var dateRange: String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day()
        if Calendar.current.isDate(range.start, inSameDayAs: range.end) {
            return range.start.formatted(format)
        }
        return "\(range.start.formatted(format)) – \(range.end.formatted(format))"
    }
}

#if DEBUG
    #Preview {
        MissingDaysView()
            .environment(PreviewSupport.missingDaysModel())
    }
#endif
