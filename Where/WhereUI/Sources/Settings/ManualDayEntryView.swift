import SwiftUI
import WhereCore

/// Retroactively assert which regions a calendar day — or a whole range of
/// days — belongs to. This overrides any prior manual entry for those days
/// and unions with whatever GPS recorded (see
/// `WhereController.addManualDay` / `addManualDays`).
struct ManualDayEntryView: View {
    @Environment(WhereModel.self) private var model
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
    @State private var selectedRegions: Set<Region> = []
    @State private var isSaving = false
    @State private var saveError: String?

    private var dayCount: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, span) + 1
    }

    private var canSave: Bool {
        guard !selectedRegions.isEmpty, !isSaving else { return false }
        if mode == .range {
            return endDate >= startDate
        }
        return true
    }

    var body: some View {
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
                ForEach(Region.allCases, id: \.self) { region in
                    Toggle(isOn: binding(for: region)) {
                        Label {
                            Text(region.localizedName)
                        } icon: {
                            Text(region.style.emoji)
                        }
                    }
                }
            } header: {
                Text(Strings.manualRegionsHeader)
            } footer: {
                Text(Strings.manualRegionsFooter)
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
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } },
            ),
        ) {
            Button(Strings.commonOK, role: .cancel) {}
        } message: {
            if let saveError {
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

    private func binding(for region: Region) -> Binding<Bool> {
        Binding(
            get: { selectedRegions.contains(region) },
            set: { isOn in
                if isOn {
                    selectedRegions.insert(region)
                } else {
                    selectedRegions.remove(region)
                }
            },
        )
    }

    private func save() {
        isSaving = true
        saveError = nil
        Task {
            do {
                switch mode {
                    case .singleDay:
                        try await model.setManualDay(date: startDate, regions: selectedRegions)
                    case .range:
                        try await model.setManualDays(
                            from: startDate,
                            through: endDate,
                            regions: selectedRegions,
                        )
                }
                dismiss()
            } catch {
                // Keep the form up so the user can retry; the save didn't land.
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            ManualDayEntryView()
        }
        .environment(PreviewSupport.loadedModel())
    }
#endif
