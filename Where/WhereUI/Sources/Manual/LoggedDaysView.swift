import RegionKit
import SwiftUI
import WhereCore

/// A sheet listing every day the user logged or overrode by hand in the selected
/// year, newest first, with a "+" to log a new one. Tapping a row pushes the
/// relabel form to correct it; swiping (or edit mode) deletes the entry,
/// restoring the GPS-derived attribution for that day. Presented from the
/// Primary tab.
///
/// The list reloads whenever the selected year's report changes (any committed
/// write re-pulls it) and again after adding or deleting, so a new, edited, or
/// removed entry appears immediately.
struct LoggedDaysView: View {
    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss
    @State private var model: LoggedDaysModel
    @State private var showingAdd = false
    @State private var deleteError = SaveErrorAlertState()

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

    /// Inputs that should trigger a reload: the selected year and the loaded
    /// report (any committed write in the year re-pulls it, so an edit made in
    /// the pushed relabel form refreshes the list on return).
    private struct LoadID: Equatable {
        let year: Int
        let report: YearReport?
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
                .navigationDestination(for: DayPresence.self) { day in
                    DayRelabelView(day: day, report: report)
                }
                .navigationDestination(isPresented: $showingAdd) {
                    ManualDayEntryView(report: report)
                }
        }
        .task(id: loadID) { await model.load(for: report.selectedYear) }
        // The pushed add form commits before it pops; reload on return so a new
        // entry appears even when it didn't change the aggregated report.
        .onChange(of: showingAdd) { _, isShowing in
            if !isShowing { reloadAfterAdd() }
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

    private var loadID: LoadID {
        LoadID(year: report.selectedYear, report: report.report)
    }

    /// A new entry can land on a day whose aggregated attribution is unchanged
    /// (an additive backfill of a region GPS already had), leaving `loadID`
    /// unchanged — so reload explicitly when the add sheet closes.
    private func reloadAfterAdd() {
        Task { await model.load(for: report.selectedYear) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                AppIconLoadingView(caption: Strings.primaryLoading)
            case let .loaded(days):
                list(days)
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

    private func list(_ days: [DayPresence]) -> some View {
        List {
            ForEach(days, id: \.date) { day in
                NavigationLink(value: day) {
                    LoggedDayRow(day: day)
                }
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

    /// Delete the given manual entries (restoring GPS attribution for those
    /// days), then reload. A failure surfaces in an alert and the list keeps its
    /// rows rather than dropping one that's still stored.
    private func delete(_ days: [DayPresence]) {
        Task {
            do {
                for day in days {
                    try await report.clearManualDay(date: day.date)
                }
                await model.load(for: report.selectedYear)
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
            Text(kindText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, stylesheet.spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        day.date.formatted(.dateTime.weekday(.abbreviated).month(.wide).day().year())
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
