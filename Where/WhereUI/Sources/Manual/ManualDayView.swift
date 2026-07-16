import Observation
import RegionKit
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
    /// Whether the collapsed "more regions" group is expanded.
    @State private var showAllRegions = false

    private static let logger = WhereLog.channel(.model)

    init(report: YearReportModel, mode: Mode, showsCancelButton: Bool = false) {
        self.report = report
        self.showsCancelButton = showsCancelButton
        _fields = State(initialValue: Fields(mode: mode))
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
        .task { await loadTrackedRegions() }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.commonCancel) { dismiss() }
                        .disabled(pending != nil)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if pending == .saving {
                    ProgressView()
                } else {
                    Button(Strings.manualSave) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .confirmationDialog(
            Strings.loggedDaysDelete,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button(Strings.loggedDaysDelete, role: .destructive) { delete() }
            Button(Strings.commonCancel, role: .cancel) {}
        } message: {
            Text(Strings.loggedDaysDeleteFooter)
        }
        .alert(
            Strings.manualSaveErrorTitle,
            isPresented: $saveError.isPresented,
        ) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            if let message = saveError.message {
                Text(message)
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

    // MARK: - Mode-specific content

    @ViewBuilder
    private func addContent(_ add: AddFields) -> some View {
        @Bindable var add = add

        Section {
            Picker(Strings.manualEntryPickerLabel, selection: $add.dateSpan) {
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
            LabeledContent(Strings.loggedDaysEditDate, value: fixedDateText(edit.day.displayDate))
        }

        regionsSection(edit.regions)
        noteSection(note: $edit.note)

        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(Strings.loggedDaysDelete, systemImage: "trash")
            }
            .disabled(pending != nil)
        } footer: {
            Text(Strings.loggedDaysDeleteFooter)
        }

        savingSection

        if let audit = edit.day.audit {
            ManualEntryAuditSection(audit: audit)
        }
    }

    @ViewBuilder
    private func datePickers(_ add: AddFields) -> some View {
        @Bindable var add = add
        switch add.dateSpan {
            case .singleDay:
                DatePicker(
                    Strings.manualDay,
                    selection: $add.startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
            case .range:
                DatePicker(
                    Strings.manualFrom,
                    selection: $add.startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
                DatePicker(
                    Strings.manualThrough,
                    selection: $add.endDate,
                    in: add.startDate ... Date(),
                    displayedComponents: .date,
                )
        }
    }

    // MARK: - Shared sections

    @ViewBuilder
    private func regionsSection(_ regions: RegionSelectionState) -> some View {
        if regions.trackedRegions == nil {
            // Tracked set not loaded yet (or a preview without services): show
            // the flat catalog list, matching the pre-grouping behavior.
            Section {
                ForEach(regions.items) { RegionToggleRow(item: $0) }
            } header: {
                Text(Strings.manualRegionsHeader)
            } footer: {
                Text(Strings.manualRegionsFooter)
            }
        } else {
            if !regions.trackedItems.isEmpty {
                Section {
                    ForEach(regions.trackedItems) { RegionToggleRow(item: $0) }
                } header: {
                    Text(Strings.manualRegionsTrackedHeader)
                } footer: {
                    Text(Strings.manualRegionsFooter)
                }
            }
            if !regions.usedItems.isEmpty {
                Section {
                    ForEach(regions.usedItems) { RegionToggleRow(item: $0) }
                } header: {
                    Text(Strings.manualRegionsUsedHeader)
                }
            }
            Section {
                DisclosureGroup(isExpanded: $showAllRegions) {
                    ForEach(regions.otherItems) { RegionToggleRow(item: $0) }
                } label: {
                    Text(Strings.manualRegionsMore)
                }
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

    /// Load the user's tracked/primary regions once so the region toggles can be
    /// grouped (tracked / already-used / everything else). On failure the form
    /// keeps the flat list rather than a broken grouping, and logs.
    private func loadTrackedRegions() async {
        guard activeRegions.trackedRegions == nil else { return }
        do {
            try await activeRegions.applyTracked(report.services.primaryRegions())
        } catch {
            Self.logger.warning("Manual-day form couldn't load tracked regions for grouping")
        }
    }

    private func noteSection(note: Binding<String>) -> some View {
        Section {
            TextField(
                Strings.manualNotePlaceholder,
                text: note,
                axis: .vertical,
            )
            .lineLimit(3, reservesSpace: true)
            .disabled(pending != nil)
        } header: {
            Text(Strings.manualNoteHeader)
        } footer: {
            Text(Strings.manualNoteFooter)
        }
    }

    @ViewBuilder
    private var savingSection: some View {
        if pending == .saving {
            Section {
                SavingStatusRow(text: Strings.manualSavingStatus)
            }
        }
    }

    // MARK: - Derived state

    private var navigationTitle: String {
        switch fields {
            case .add: Strings.manualTitle
            case .edit: Strings.loggedDaysEditTitle
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
            case .singleDay: Strings.manualSingleDayFooter
            case .range: Strings.manualRangeFooter(count: add.dayCount)
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
                case .singleDay: Strings.manualModeSingleDay
                case .range: Strings.manualModeRange
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

        init(mode: Mode) {
            switch mode {
                case let .add(prefill): self = .add(AddFields(prefill: prefill))
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

        init(prefill: MissingDayRange?) {
            if let prefill {
                dateSpan = prefill.dayCount > 1 ? .range : .singleDay
                startDate = prefill.start.startOfDay(in: .current)
                endDate = prefill.end.startOfDay(in: .current)
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
            let calendar = Calendar.current
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
    #Preview("Add") {
        NavigationStack {
            ManualDayView(report: PreviewSupport.loadedYearReportModel(), mode: .add(prefill: nil))
        }
    }

    #Preview("Add — prefilled range") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.missingDaysYearReportModel(),
                mode: .add(prefill: MissingDayRange(
                    start: CalendarDay(year: 2026, month: 1, day: 1),
                    end: CalendarDay(year: 2026, month: 1, day: 5),
                    dayCount: 5,
                )),
            )
        }
    }

    #Preview("Edit — additive backfill") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.loadedYearReportModel(),
                mode: .edit(DayPresence(date: .now, in: .current, regions: [.california])),
            )
        }
    }

    #Preview("Edit — authoritative with audit") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.loadedYearReportModel(),
                mode: .edit(DayPresence(
                    date: .now,
                    in: .current,
                    regions: [.canada],
                    isAuthoritative: true,
                    audit: ManualEntryAudit(
                        recordedAt: .now,
                        note: "Corrected after reviewing my boarding pass.",
                        location: CapturedLocation(
                            coordinate: Coordinate(latitude: 49.2827, longitude: -123.1207),
                            horizontalAccuracy: 12,
                            timestamp: .now,
                        ),
                    ),
                )),
            )
        }
    }
#endif
