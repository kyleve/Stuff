import StuffCore
import SwiftUI
import WhereCore

/// Lists the calendar days this year with no recorded presence as tappable
/// ranges. Selecting one opens a prefilled `ManualDayEntryView` so the user can
/// backfill where they were. Presented as a sheet from the Primary tab's
/// warning banner.
struct MissingDaysView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(.missingDays.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizedStrings.MissingDays.done.localized) { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.missingDays.isEmpty {
            ContentUnavailableView {
                Label(
                    LocalizedStrings.MissingDays.emptyTitle.localized,
                    systemImage: "checkmark.circle",
                )
            } description: {
                Text(localized: .missingDays.emptyDescription)
            }
        } else {
            List {
                Section {
                    ForEach(session.missingDays) { range in
                        NavigationLink {
                            ManualDayEntryView(prefill: range)
                        } label: {
                            MissingDayRow(range: range)
                        }
                    }
                } header: {
                    Text(localized: .missingDays.header)
                } footer: {
                    Text(localized: .missingDays.footer)
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
                Text(localized: .common.dayCount(range.dayCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, UIConstants.Spacings.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var dateRange: String {
        DateRangeFormatting.abbreviated(start: range.start, end: range.end)
    }
}

#if DEBUG
    #Preview {
        MissingDaysView()
            .environment(PreviewSupport.missingDaysSession())
    }
#endif
