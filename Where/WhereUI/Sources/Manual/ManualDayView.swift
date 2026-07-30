import Observation
import PeriscopeCore
import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// The one hand-entry form for a manual day. In `.add` mode it retroactively
/// asserts which regions a single day — or a whole range — belongs to
/// (additive: unions with GPS, see `DayJournal.addManualDay` / `addManualDays`).
/// In `.edit` mode it adjusts a stored entry's regions and note, *preserving*
/// its kind (an additive backfill stays additive; an authoritative override
/// stays authoritative), and offers a confirmed delete.
///
/// Presented as a sheet from the logged-days list (add "+" and row tap) and
/// pushed by the Resolve backfill flow. Distinct from `DayRelabelView`, which
/// corrects a *GPS-attributed* day (always authoritative, "reset to GPS") from
/// the Elsewhere/Resolve surfaces.
struct ManualDayView: View {
    /// Whether the form creates a new entry or edits a stored one. The caller's
    /// entry point; the editable state it seeds lives in `Fields`.
    enum Mode {
        /// Add a new entry, optionally prefilled with a range to backfill.
        case add(prefill: MissingDayRange?)
        /// Edit the given stored entry, preserving its kind.
        case edit(DayPresence)
    }

    let report: YearReportModel

    /// When presented modally (the logged-days list), the form needs its own
    /// Cancel button to dismiss without saving. Pushed contexts (the Resolve
    /// backfill flow) rely on the navigation back button, so it defaults off.
    let showsCancelButton: Bool

    @Environment(\.dismiss) private var dismiss

    /// Mode-specific editable state, each case carrying *exactly* the fields that
    /// mode needs — so add-only inputs (dates, span) can't be read in edit and
    /// the day being edited can't be read in add. Held in `@State` (the
    /// `@Observable` cases persist and drive updates); the body switches on it.
    @State private var fields: Fields
    @State private var saveError = SaveErrorAlertState()
    @State private var deleteError = SaveErrorAlertState()
    @State private var showDeleteConfirmation = false
    @State private var pending: PendingWrite?

    private static let logger = WhereLog.session(ManualDayViewLog.self)

    init(report: YearReportModel, mode: Mode, showsCancelButton: Bool = false) {
        self.report = report
        self.showsCancelButton = showsCancelButton
        _fields = State(initialValue: Fields(mode: mode, calendar: report.calendar))
    }

    var body: some View {
        @Bindable var saveError = saveError
        @Bindable var deleteError = deleteError

        Form {
            switch fields {
                case let .add(add): addContent(add)
                case let .edit(edit): editContent(edit)
            }
        }
        .animation(.default, value: pending)
        .task { await loadGrouping() }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) { dismiss() }
                        .disabled(pending != nil)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if pending == .saving {
                    ProgressView()
                } else {
                    Button(String(localized: .manualSave)) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .confirmationDialog(
            String(localized: .loggedDaysDelete),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button(String(localized: .loggedDaysDelete), role: .destructive) { delete() }
            Button(String(localized: .commonCancel), role: .cancel) {}
        } message: {
            Text(String(localized: .loggedDaysDeleteFooter))
        }
        .alert(
            String(localized: .manualSaveErrorTitle),
            isPresented: $saveError.isPresented,
        ) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            if let message = saveError.message {
                Text(message)
            }
        }
        .alert(
            String(localized: .loggedDaysDeleteErrorTitle),
            isPresented: $deleteError.isPresented,
        ) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            if let message = deleteError.message {
                Text(message)
            }
        }
        // Log View Mode: reveal an inspect badge for the manual-day form's
        // events (region grouping load). A no-op in release.
        .debugLogInspectable(WhereLog.session(ManualDayViewLog.self))
    }

    // MARK: - Mode-specific content

    @ViewBuilder
    private func addContent(_ add: AddFields) -> some View {
        @Bindable var add = add

        Section {
            Picker(String(localized: .manualEntryPickerLabel), selection: $add.dateSpan) {
                ForEach(DateSpan.allCases) { span in
                    Text(span.title).tag(span)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("where_manual_mode")

            datePickers(add)
        } footer: {
            Text(addDateFooter(add))
        }
        // Keep the range's end from drifting before its start when the user
        // moves the start forward (the end picker's range only clamps display).
        .onChange(of: add.startDate) { _, newValue in
            if add.endDate < newValue { add.endDate = newValue }
        }

        regionsSection(add.regions)
        noteSection(note: $add.note)
        savingSection
    }

    @ViewBuilder
    private func editContent(_ edit: EditFields) -> some View {
        @Bindable var edit = edit

        Section {
            LabeledContent(
                String(localized: .loggedDaysEditDate),
                value: fixedDateText(edit.day.displayDate),
            )
        }

        regionsSection(edit.regions)
        noteSection(note: $edit.note)

        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(String(localized: .loggedDaysDelete), systemImage: "trash")
            }
            .disabled(pending != nil)
        } footer: {
            Text(String(localized: .loggedDaysDeleteFooter))
        }

        savingSection

        if let audit = edit.day.audit {
            ManualEntryAuditSection(audit: audit)
        }
    }

    /// `WhereDatePicker` renders a deterministic stand-in under snapshot capture
    /// (the live compact capsule's date format depends on the real-world date,
    /// so no reference image containing it is stable across days) — the capture
    /// handling stays inside the wrapper, not here.
    @ViewBuilder
    private func datePickers(_ add: AddFields) -> some View {
        @Bindable var add = add
        switch add.dateSpan {
            case .singleDay:
                WhereDatePicker(
                    String(localized: .manualDay),
                    selection: $add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
            case .range:
                WhereDatePicker(
                    String(localized: .manualFrom),
                    selection: $add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
                WhereDatePicker(
                    String(localized: .manualThrough),
                    selection: $add.endDate,
                    earliest: add.startDate,
                    latest: Date(),
                    displayedComponents: .date,
                )
        }
    }

    // MARK: - Shared sections

    @ViewBuilder
    private func regionsSection(_ regions: RegionSelectionState) -> some View {
        if regions.isGrouped {
            // Your regions / Used this year / More — the shared grouped sections,
            // with day-membership toggles as the row.
            GroupedRegionSections(
                grouping: regions.grouping,
                yoursFooter: String(localized: .manualRegionsFooter),
            ) { region in
                if let item = regions.item(for: region) {
                    RegionToggleRow(item: item)
                }
            }
        } else {
            // Tracked set not loaded yet (or a preview without services): show
            // the flat catalog list, matching the pre-grouping behavior.
            Section {
                ForEach(regions.items) { RegionToggleRow(item: $0) }
            } header: {
                Text(String(localized: .manualRegionsHeader))
            } footer: {
                Text(String(localized: .manualRegionsFooter))
            }
        }
    }

    /// The region-selection state for the active mode.
    private var activeRegions: RegionSelectionState {
        switch fields {
            case let .add(add): add.regions
            case let .edit(edit): edit.regions
        }
    }

    /// Load the tracked/primary regions + the regions used this year once so the
    /// toggles can be grouped (tracked / used-this-year / everything else). On
    /// failure the form keeps the flat list rather than a broken grouping, and
    /// logs.
    private func loadGrouping() async {
        guard activeRegions.trackedRegions == nil else { return }
        // "Used this year" is the *selected report year* — the year this form is
        // reached for (logged-days list / relabel are per-report-year), so it
        // matches the day being edited in practice. It only drives grouping
        // order, not what gets saved.
        let usedThisYear = Set(
            (report.report?.totals ?? [:]).filter { $0.value > 0 }.map(\.key),
        )
        do {
            let tracked = try await report.services.primaryRegions()
            activeRegions.applyGrouping(tracked: tracked, usedThisYear: usedThisYear)
        } catch {
            Self.logger(attachments: [.error(error, name: "grouping-error")]) {
                .regionGroupingLoadFailed(description: error.localizedDescription)
            }
        }
    }

    private func noteSection(note: Binding<String>) -> some View {
        Section {
            TextField(
                String(localized: .manualNotePlaceholder),
                text: note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
            .disabled(pending != nil)
        } header: {
            Text(String(localized: .manualNoteHeader))
        } footer: {
            Text(String(localized: .manualNoteFooter))
        }
    }

    @ViewBuilder
    private var savingSection: some View {
        if pending == .saving {
            Section {
                SavingStatusRow(text: String(localized: .manualSavingStatus))
            }
        }
    }

    // MARK: - Derived state

    private var navigationTitle: String {
        switch fields {
            case .add: String(localized: .manualTitle)
            case .edit: String(localized: .loggedDaysEditTitle)
        }
    }

    private var canSave: Bool {
        guard pending == nil else { return false }
        switch fields {
            case let .add(add):
                guard !add.regions.selectedRegions.isEmpty else { return false }
                return add.dateSpan == .range ? add.endDate >= add.startDate : true
            case let .edit(edit):
                return !edit.regions.selectedRegions.isEmpty && edit.hasChanges
        }
    }

    private func addDateFooter(_ add: AddFields) -> String {
        switch add.dateSpan {
            case .singleDay: String(localized: .manualSingleDayFooter)
            case .range: WhereFormat.manualRangeFooter(count: add.dayCount)
        }
    }

    private func fixedDateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    // MARK: - Writes

    /// Save the entry. Add mode is additive (single day or range); edit mode
    /// preserves the entry's kind. Keeps the form up on failure so the user can
    /// retry.
    private func save() {
        pending = .saving
        saveError.message = nil
        Task {
            do {
                try await performSave()
                dismiss()
            } catch {
                saveError.message = error.localizedDescription
                pending = nil
            }
        }
    }

    private func performSave() async throws {
        switch fields {
            case let .add(add):
                let regions = add.regions.selectedRegions
                switch add.dateSpan {
                    case .singleDay:
                        try await report.setManualDay(
                            date: add.startDate,
                            regions: regions,
                            note: add.note,
                        )
                    case .range:
                        try await report.setManualDays(
                            from: add.startDate,
                            through: add.endDate,
                            regions: regions,
                            note: add.note,
                        )
                }
            case let .edit(edit):
                let regions = edit.regions.selectedRegions
                let date = edit.day.startOfDay(in: report.calendar)
                if edit.day.isAuthoritative {
                    try await report.overrideDay(
                        date: date,
                        regions: regions,
                        note: edit.note,
                    )
                } else {
                    try await report.setManualDay(
                        date: date,
                        regions: regions,
                        note: edit.note,
                    )
                }
        }
    }

    /// Delete the entry being edited, restoring the day's GPS-detected
    /// attribution. A no-op in add mode. Keeps the form up on failure.
    private func delete() {
        guard case let .edit(edit) = fields else { return }
        pending = .deleting
        deleteError.message = nil
        Task {
            do {
                try await report.clearManualDay(date: edit.day.startOfDay(in: report.calendar))
                dismiss()
            } catch {
                deleteError.message = error.localizedDescription
                pending = nil
            }
        }
    }
}

extension ManualDayView {
    /// Single day vs. a date range — an add-only choice.
    enum DateSpan: Hashable, CaseIterable, Identifiable {
        case singleDay
        case range

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .singleDay: String(localized: .manualModeSingleDay)
                case .range: String(localized: .manualModeRange)
            }
        }
    }

    /// Which async write is in flight, so the form can disable inputs and show
    /// progress without two overlapping `Bool`s.
    enum PendingWrite {
        case saving
        case deleting
    }

    /// The editable state, grouped so each mode holds only its own fields.
    enum Fields {
        case add(AddFields)
        case edit(EditFields)

        init(mode: Mode, calendar: Calendar) {
            switch mode {
                case let .add(prefill):
                    self = .add(AddFields(prefill: prefill, calendar: calendar))
                case let .edit(day): self = .edit(EditFields(day: day))
            }
        }
    }

    /// Editable state for adding a new entry: the day span, its date(s), the
    /// chosen regions, and an optional note.
    @Observable
    final class AddFields {
        var dateSpan: DateSpan
        var startDate: Date
        var endDate: Date
        var regions: RegionSelectionState
        var note: String
        private let calendar: Calendar

        init(prefill: MissingDayRange?, calendar: Calendar) {
            self.calendar = calendar
            if let prefill {
                dateSpan = prefill.dayCount > 1 ? .range : .singleDay
                startDate = prefill.start.startOfDay(in: calendar)
                endDate = prefill.end.startOfDay(in: calendar)
            } else {
                dateSpan = .singleDay
                startDate = Date()
                endDate = Date()
            }
            regions = RegionSelectionState()
            note = ""
        }

        /// Inclusive day count of the current range (or 1 for a single day),
        /// for the footer.
        var dayCount: Int {
            let start = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)
            let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            return max(0, span) + 1
        }
    }

    /// Editable state for correcting a stored entry: the fixed day it targets,
    /// plus the (prefilled) regions and note.
    @Observable
    final class EditFields {
        let day: DayPresence
        var regions: RegionSelectionState
        var note: String

        init(day: DayPresence) {
            self.day = day
            regions = RegionSelectionState(selectedRegions: day.regions)
            note = day.audit?.note ?? ""
        }

        /// Whether the regions or the note differ from what's stored, so a
        /// note-only edit still enables Save.
        var hasChanges: Bool {
            regions.selectedRegions != day.regions
                || note.trimmingCharacters(in: .whitespacesAndNewlines)
                != (day.audit?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

#if DEBUG
    extension ManualDayView: SnapshotProviding {
        /// A plain add (`prefill: nil`) would default its date pickers to the
        /// real current date and churn the references daily, so the add cases
        /// prefill a fixed single day instead — same form, deterministic date.
        private static var addPrefill: MissingDayRange {
            let day = CalendarDay(from: PreviewSupport.referenceNow, in: .current)
            return MissingDayRange(start: day, end: day, dayCount: 1)
        }

        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Add", configurations: .screenDefaults) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .add(prefill: addPrefill),
                        showsCancelButton: false,
                    )
                }
            }
            whereSnapshot(name: "AddWithCancel", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .add(prefill: addPrefill),
                        showsCancelButton: true,
                    )
                }
            }
            whereSnapshot(name: "EditPlain", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .edit(DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.california],
                        )),
                        showsCancelButton: true,
                    )
                }
            }
            whereSnapshot(name: "EditAuthoritative", configurations: .phoneLightDark) {
                NavigationStack {
                    ManualDayView(
                        report: PreviewSupport.loadedYearReportModel(),
                        mode: .edit(DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.canada],
                            isAuthoritative: true,
                            audit: ManualEntryAudit(
                                recordedAt: PreviewSupport.referenceNow,
                                note: "Boarding pass.",
                                location: nil,
                            ),
                        )),
                        showsCancelButton: true,
                    )
                }
            }
        }
    }

    #Preview {
        ManualDayView.snapshotPreviews
    }
#endif

#if DEBUG
    extension ManualDayView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            ManualDayView.self,
            title: "Manual Day",
        )
    }
#endif
