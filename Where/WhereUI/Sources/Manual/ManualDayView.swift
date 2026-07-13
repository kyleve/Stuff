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
    /// Whether the form creates a new entry or edits a stored one — the axis the
    /// mode-specific sections and the save path switch on.
    enum Mode {
        /// Add a new entry, optionally prefilled with a range to backfill.
        case add(prefill: MissingDayRange?)
        /// Edit the given stored entry, preserving its kind.
        case edit(DayPresence)
    }

    let report: YearReportModel
    let mode: Mode

    /// When presented modally (the logged-days list), the form needs its own
    /// Cancel button to dismiss without saving. Pushed contexts (the Resolve
    /// backfill flow) rely on the navigation back button, so it defaults off.
    let showsCancelButton: Bool

    @Environment(\.dismiss) private var dismiss

    /// Single day vs. a date range — an `.add`-only choice.
    private enum DateSpan: Hashable, CaseIterable, Identifiable {
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
    private enum PendingWrite {
        case saving
        case deleting
    }

    @State private var dateSpan: DateSpan = .singleDay
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var regionSelection: RegionSelectionState
    @State private var note: String
    @State private var saveError = SaveErrorAlertState()
    @State private var deleteError = SaveErrorAlertState()
    @State private var showDeleteConfirmation = false
    @State private var pending: PendingWrite?

    init(report: YearReportModel, mode: Mode, showsCancelButton: Bool = false) {
        self.report = report
        self.mode = mode
        self.showsCancelButton = showsCancelButton
        switch mode {
            case let .add(prefill):
                if let prefill {
                    _dateSpan = State(initialValue: prefill.dayCount > 1 ? .range : .singleDay)
                    _startDate = State(initialValue: prefill.start)
                    _endDate = State(initialValue: prefill.end)
                }
                _regionSelection = State(initialValue: RegionSelectionState())
                _note = State(initialValue: "")
            case let .edit(day):
                _regionSelection = State(
                    initialValue: RegionSelectionState(selectedRegions: day.regions),
                )
                _note = State(initialValue: day.audit?.note ?? "")
        }
    }

    /// The stored entry being edited, or `nil` in add mode.
    private var editingDay: DayPresence? {
        if case let .edit(day) = mode { return day }
        return nil
    }

    private var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, span) + 1
    }

    private var canSave: Bool {
        guard !regionSelection.selectedRegions.isEmpty, pending == nil else { return false }
        switch mode {
            case .add:
                return dateSpan == .range ? endDate >= startDate : true
            case let .edit(day):
                return hasChanges(from: day)
        }
    }

    /// In edit mode, whether the regions or the note differ from what's stored,
    /// so a note-only edit still enables Save.
    private func hasChanges(from day: DayPresence) -> Bool {
        regionSelection.selectedRegions != day.regions
            || note.trimmingCharacters(in: .whitespacesAndNewlines)
            != (day.audit?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        @Bindable var saveError = saveError
        @Bindable var deleteError = deleteError

        Form {
            dateSection

            Section {
                ForEach(regionSelection.items) { item in
                    RegionToggleRow(item: item)
                }
            } header: {
                Text(Strings.manualRegionsHeader)
            } footer: {
                Text(Strings.manualRegionsFooter)
            }

            Section {
                TextField(
                    Strings.manualNotePlaceholder,
                    text: $note,
                    axis: .vertical,
                )
                .lineLimit(3, reservesSpace: true)
                .disabled(pending != nil)
            } header: {
                Text(Strings.manualNoteHeader)
            } footer: {
                Text(Strings.manualNoteFooter)
            }

            // Editing always targets a stored entry, so deleting it (restoring
            // the day's GPS attribution) applies only in edit mode.
            if editingDay != nil {
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
            }

            if pending == .saving {
                Section {
                    SavingStatusRow(text: Strings.manualSavingStatus)
                }
            }

            if let audit = editingDay?.audit {
                ManualEntryAuditSection(audit: audit)
            }
        }
        .animation(.default, value: pending)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
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

    @ViewBuilder
    private var dateSection: some View {
        switch mode {
            case .add:
                Section {
                    Picker(Strings.manualEntryPickerLabel, selection: $dateSpan) {
                        ForEach(DateSpan.allCases) { span in
                            Text(span.title).tag(span)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("where_manual_mode")

                    datePickers
                } footer: {
                    Text(dateFooter)
                }
            case let .edit(day):
                Section {
                    LabeledContent(Strings.loggedDaysEditDate, value: fixedDateText(day.date))
                }
        }
    }

    @ViewBuilder
    private var datePickers: some View {
        switch dateSpan {
            case .singleDay:
                DatePicker(
                    Strings.manualDay,
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
            case .range:
                DatePicker(
                    Strings.manualFrom,
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
                DatePicker(
                    Strings.manualThrough,
                    selection: $endDate,
                    in: startDate ... Date(),
                    displayedComponents: .date,
                )
        }
    }

    private var navigationTitle: String {
        editingDay == nil ? Strings.manualTitle : Strings.loggedDaysEditTitle
    }

    private var dateFooter: String {
        switch dateSpan {
            case .singleDay: Strings.manualSingleDayFooter
            case .range: Strings.manualRangeFooter(count: dayCount)
        }
    }

    private func fixedDateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

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
        let regions = regionSelection.selectedRegions
        switch mode {
            case .add:
                switch dateSpan {
                    case .singleDay:
                        try await report.setManualDay(date: startDate, regions: regions, note: note)
                    case .range:
                        try await report.setManualDays(
                            from: startDate,
                            through: endDate,
                            regions: regions,
                            note: note,
                        )
                }
            case let .edit(day):
                if day.isAuthoritative {
                    try await report.overrideDay(date: day.date, regions: regions, note: note)
                } else {
                    try await report.setManualDay(date: day.date, regions: regions, note: note)
                }
        }
    }

    /// Delete the entry being edited, restoring the day's GPS-detected
    /// attribution. Keeps the form up on failure so the user can retry.
    private func delete() {
        guard let day = editingDay else { return }
        pending = .deleting
        deleteError.message = nil
        Task {
            do {
                try await report.clearManualDay(date: day.date)
                dismiss()
            } catch {
                deleteError.message = error.localizedDescription
                pending = nil
            }
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
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 86400 * 4),
                    dayCount: 5,
                )),
            )
        }
    }

    #Preview("Edit — additive backfill") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.loadedYearReportModel(),
                mode: .edit(DayPresence(date: .now, regions: [.california])),
            )
        }
    }

    #Preview("Edit — authoritative with audit") {
        NavigationStack {
            ManualDayView(
                report: PreviewSupport.loadedYearReportModel(),
                mode: .edit(DayPresence(
                    date: .now,
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
