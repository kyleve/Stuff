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
                case .singleDay: "Single day"
                case .range: "Date range"
            }
        }
    }

    @State private var mode: EntryMode = .singleDay
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var selectedRegions: Set<Region> = []
    @State private var isSaving = false

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
                Picker("Entry", selection: $mode) {
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
                Text("Regions")
            } footer: {
                Text("Saving replaces any manual regions you previously set for those days.")
            }
        }
        .navigationTitle("Log a Day")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: startDate) { _, newValue in
            if endDate < newValue { endDate = newValue }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var datePickers: some View {
        switch mode {
            case .singleDay:
                DatePicker(
                    "Day",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
            case .range:
                DatePicker(
                    "From",
                    selection: $startDate,
                    in: ...Date(),
                    displayedComponents: .date,
                )
                DatePicker(
                    "Through",
                    selection: $endDate,
                    in: startDate ... Date(),
                    displayedComponents: .date,
                )
        }
    }

    private var dateFooter: String {
        switch mode {
            case .singleDay:
                "Time travel: tell Where where you really were."
            case .range:
                "Backfilling \(dayCount) \(dayCount == 1 ? "day" : "days")."
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
        Task {
            switch mode {
                case .singleDay:
                    await model.setManualDay(date: startDate, regions: selectedRegions)
                case .range:
                    await model.setManualDays(
                        from: startDate,
                        through: endDate,
                        regions: selectedRegions,
                    )
            }
            dismiss()
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
