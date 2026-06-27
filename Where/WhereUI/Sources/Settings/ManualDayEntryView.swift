import StuffCore
import SwiftUI
import WhereCore

/// Retroactively assert which regions a calendar day — or a whole range of
/// days — belongs to. This overrides any prior manual entry for those days
/// and unions with whatever GPS recorded (see
/// `DayJournal.addManualDay` / `addManualDays`).
struct ManualDayEntryView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private enum EntryMode: Hashable, CaseIterable, Identifiable {
        case singleDay
        case range

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case .singleDay: LocalizedStrings.ManualEntry.modeSingleDay.localized
                case .range: LocalizedStrings.ManualEntry.modeRange.localized
            }
        }
    }

    @State private var mode: EntryMode = .singleDay
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var regionSelection = RegionSelectionState()
    @State private var saveError = SaveErrorAlertState()
    @State private var isSaving = false

    /// Open with the dates (and single-day vs range mode) preselected — used by
    /// the backfill flow so tapping a missing range lands on a populated form.
    init(prefill: MissingDayRange? = nil) {
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
                Picker(LocalizedStrings.ManualEntry.pickerLabel.localized, selection: $mode) {
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
                Text(localized: .manualEntry.regionsHeader)
            } footer: {
                Text(localized: .manualEntry.regionsFooter)
            }
        }
        .navigationTitle(.manualEntry.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStrings.ManualEntry.save.localized) { save() }
                    .disabled(!canSave)
            }
        }
        .alert(
            LocalizedStrings.ManualEntry.saveErrorTitle.localized,
            isPresented: $saveError.isPresented,
        ) {
            Button(LocalizedStrings.Common.ok.localized, role: .cancel) {}
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
                    LocalizedStrings.ManualEntry.day.localized,
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
            case .range:
                DatePicker(
                    LocalizedStrings.ManualEntry.from.localized,
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
                DatePicker(
                    LocalizedStrings.ManualEntry.through.localized,
                    selection: $endDate,
                    in: startDate ... Date(),
                    displayedComponents: .date,
                )
        }
    }

    private var dateFooter: String {
        switch mode {
            case .singleDay:
                LocalizedStrings.ManualEntry.singleDayFooter.localized
            case .range:
                LocalizedStrings.ManualEntry.rangeFooter(count: dayCount).localized
        }
    }

    private func save() {
        isSaving = true
        saveError.message = nil
        Task {
            do {
                switch mode {
                    case .singleDay:
                        try await session.setManualDay(
                            date: startDate,
                            regions: regionSelection.selectedRegions,
                        )
                    case .range:
                        try await session.setManualDays(
                            from: startDate,
                            through: endDate,
                            regions: regionSelection.selectedRegions,
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
            ManualDayEntryView()
        }
        .environment(PreviewSupport.loadedSession())
    }

    #Preview("Prefill range") {
        NavigationStack {
            ManualDayEntryView(prefill: MissingDayRange(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 86400 * 4),
                dayCount: 5,
            ))
        }
        .environment(PreviewSupport.missingDaysSession())
    }
#endif
