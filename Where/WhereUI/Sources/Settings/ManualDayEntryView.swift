import SwiftUI
import WhereCore

/// Retroactively assert which regions a calendar day — or a whole range of
/// days — belongs to. This overrides any prior manual entry for those days
/// and unions with whatever GPS recorded (see
/// `DayJournal.addManualDay` / `addManualDays`).
struct ManualDayEntryView: View {
    let report: YearReportModel

    @Environment(\.dismiss) private var dismiss

    private enum EntryMode: Hashable, CaseIterable, Identifiable {
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

    @State private var mode: EntryMode = .singleDay
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var regionSelection = RegionSelectionState()
    @State private var note = ""
    @State private var saveError = SaveErrorAlertState()
    @State private var isSaving = false

    /// Open with the dates (and single-day vs range mode) preselected — used by
    /// the backfill flow so tapping a missing range lands on a populated form.
    init(report: YearReportModel, prefill: MissingDayRange? = nil) {
        self.report = report
        guard let prefill else { return }
        _mode = State(initialValue: prefill.dayCount > 1 ? .range : .singleDay)
        _startDate = State(initialValue: prefill.start)
        _endDate = State(initialValue: prefill.end)
    }

    private var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, span) + 1
    }

    private var canSave: Bool {
        guard !regionSelection.selectedRegions.isEmpty, !isSaving else { return false }
        if mode == .range {
            return endDate >= startDate
        }
        return true
    }

    var body: some View {
        @Bindable var saveError = saveError

        Form {
            Section {
                Picker(Strings.manualEntryPickerLabel, selection: $mode) {
                    ForEach(EntryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("where_manual_mode")

                datePickers
            } footer: {
                Text(dateFooter)
            }

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
                .disabled(isSaving)
            } header: {
                Text(Strings.manualNoteHeader)
            } footer: {
                Text(Strings.manualNoteFooter)
            }
        }
        .navigationTitle(Strings.manualTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(Strings.manualSave) { save() }
                    .disabled(!canSave)
            }
        }
        .alert(
            Strings.manualSaveErrorTitle,
            isPresented: $saveError.isPresented,
        ) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            if let saveError = saveError.message {
                Text(saveError)
            }
        }
    }

    @ViewBuilder
    private var datePickers: some View {
        switch mode {
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

    private var dateFooter: String {
        switch mode {
            case .singleDay:
                Strings.manualSingleDayFooter
            case .range:
                Strings.manualRangeFooter(count: dayCount)
        }
    }

    private func save() {
        isSaving = true
        saveError.message = nil
        Task {
            do {
                switch mode {
                    case .singleDay:
                        try await report.setManualDay(
                            date: startDate,
                            regions: regionSelection.selectedRegions,
                            note: note,
                        )
                    case .range:
                        try await report.setManualDays(
                            from: startDate,
                            through: endDate,
                            regions: regionSelection.selectedRegions,
                            note: note,
                        )
                }
                dismiss()
            } catch {
                // Keep the form up so the user can retry; the save didn't land.
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#if DEBUG
    #Preview("Default") {
        NavigationStack {
            ManualDayEntryView(report: PreviewSupport.loadedYearReportModel())
        }
    }

    #Preview("Prefill range") {
        NavigationStack {
            ManualDayEntryView(
                report: PreviewSupport.missingDaysYearReportModel(),
                prefill: MissingDayRange(
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 86400 * 4),
                    dayCount: 5,
                ),
            )
        }
    }
#endif
