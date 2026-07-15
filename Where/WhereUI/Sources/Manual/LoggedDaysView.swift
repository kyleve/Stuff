import RegionKit
import SwiftUI
import WhereCore

/// A sheet listing every day the user logged or overrode by hand in the selected
/// year, newest first, with a "+" to log a new one. Tapping a row opens an editor
/// to correct it; swiping (or edit mode) deletes the entry, restoring the
/// GPS-derived attribution for that day. Presented from the Primary tab.
///
/// The list stays in sync off the single store-change signal
/// (`LoggedDaysModel.observe`), so an add, edit, or delete — from here or
/// anywhere — reloads it.
struct LoggedDaysView: View {
    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet
    @State private var model: LoggedDaysModel
    @State private var showingAdd = false
    @State private var editTarget: EditTarget?
    @State private var deleteError = SaveErrorAlertState()
    @State private var filter: LoggedDaysFilter = .all

    init(report: YearReportModel) {
        self.report = report
        _model = State(initialValue: LoggedDaysModel(services: report.services))
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen state.
        init(report: YearReportModel, model: LoggedDaysModel) {
            self.report = report
            _model = State(initialValue: model)
        }
    #endif

    /// Identifies which day's editor to present. `DayPresence` isn't
    /// `Identifiable`, and `.sheet(item:)` needs identity; a manual entry's
    /// start-of-day date is unique.
    private struct EditTarget: Identifiable {
        let day: DayPresence
        var id: CalendarDay {
            day.day
        }
    }

    var body: some View {
        @Bindable var deleteError = deleteError

        NavigationStack {
            content
                .navigationTitle(Strings.loggedDaysTitle(year: report.selectedYear))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.commonDone) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAdd = true
                        } label: {
                            Label(Strings.loggedDaysAdd, systemImage: "plus")
                        }
                        .accessibilityIdentifier("where_add_logged_day_button")
                    }
                }
        }
        // Load, then keep the list current off the single store-change signal —
        // no per-action reload wiring needed. Runs for the sheet's lifetime and
        // is cancelled when it closes.
        .task { await model.observe(year: report.selectedYear) }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                ManualDayView(report: report, mode: .add(prefill: nil), showsCancelButton: true)
            }
        }
        .sheet(item: $editTarget) { target in
            NavigationStack {
                ManualDayView(report: report, mode: .edit(target.day), showsCancelButton: true)
            }
        }
        .alert(
            Strings.loggedDaysDeleteErrorTitle,
            isPresented: $deleteError.isPresented,
        ) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            if let message = deleteError.message {
                Text(message)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                AppIconLoadingView(caption: Strings.primaryLoading)
            case let .loaded(days):
                loaded(days)
            case .empty:
                emptyState
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.loggedDaysFailedTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
        }
    }

    /// The Logged/Overridden/All filter pinned above the list, then the matching
    /// rows — or a "nothing matches this filter" state, distinct from the
    /// year-has-no-entries `emptyState`.
    private func loaded(_ days: [DayPresence]) -> some View {
        let matches = days.filter(filter.matches)
        return VStack(spacing: 0) {
            Picker(Strings.loggedDaysFilterLabel, selection: $filter) {
                ForEach(LoggedDaysFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, stylesheet.spacing.small)
            .accessibilityIdentifier("where_logged_days_filter")

            if matches.isEmpty {
                noMatchesState
            } else {
                list(matches)
            }
        }
        .animation(.default, value: filter)
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label(
                Strings.loggedDaysNoMatchesTitle,
                systemImage: "line.3.horizontal.decrease.circle",
            )
        } description: {
            Text(Strings.loggedDaysNoMatchesDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func list(_ days: [DayPresence]) -> some View {
        List {
            ForEach(days, id: \.day) { day in
                Button {
                    editTarget = EditTarget(day: day)
                } label: {
                    LoggedDayRow(day: day)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                delete(offsets.map { days[$0] })
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("where_logged_days_list")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.loggedDaysEmptyTitle, systemImage: "calendar.badge.plus")
        } description: {
            Text(Strings.loggedDaysEmptyDescription)
        } actions: {
            Button(Strings.loggedDaysAdd) { showingAdd = true }
        }
    }

    /// Delete the given manual entries in one transaction (restoring GPS
    /// attribution for those days). The list refreshes off the store-change
    /// signal `observe` watches; a failure surfaces in an alert and the rows
    /// stay put.
    private func delete(_ days: [DayPresence]) {
        Task {
            do {
                try await report.clearManualDays(
                    dates: days.map { $0.startOfDay(in: report.calendar) },
                )
            } catch {
                deleteError.message = error.localizedDescription
            }
        }
    }
}

/// One logged day: an icon marking backfill vs. override, the date, the regions
/// it counts for, a "Logged"/"Overridden" tag, and the audit note if one was
/// saved with the entry.
private struct LoggedDayRow: View {
    let day: DayPresence

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemName: day.isAuthoritative ? "pencil.circle" : "calendar.badge.plus")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: stylesheet.size.statusIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(dateText)
                    .font(.headline)
                Text(regionsText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = day.audit?.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: stylesheet.spacing.small)
            // `fixedSize` keeps the tag at its intrinsic width so long region
            // lists wrap in the VStack rather than squeezing "Logged"/"Overridden".
            Text(kindText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.vertical, stylesheet.spacing.xxSmall)
        // Make the whole row (including the spacer) tap into the edit sheet.
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        day.displayDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day().year())
    }

    private var kindText: String {
        day.isAuthoritative ? Strings.loggedDaysKindOverridden : Strings.loggedDaysKindLogged
    }

    /// Region names joined in declaration order so the caption is stable.
    private var regionsText: String {
        Region.allCases
            .filter { day.regions.contains($0) }
            .map(\.localizedName)
            .joined(separator: ", ")
    }
}

#if DEBUG
    #Preview("Loaded") {
        LoggedDaysView(
            report: PreviewSupport.loadedYearReportModel(),
            model: PreviewSupport
                .loggedDaysModel(state: .loaded(PreviewSupport.sampleManualDays())),
        )
    }

    #Preview("Empty") {
        LoggedDaysView(
            report: PreviewSupport.loadedYearReportModel(),
            model: PreviewSupport.loggedDaysModel(state: .empty),
        )
    }

    #Preview("Failed") {
        LoggedDaysView(
            report: PreviewSupport.loadedYearReportModel(),
            model: PreviewSupport.loggedDaysModel(state: .failed("iCloud is unavailable.")),
        )
    }
#endif
