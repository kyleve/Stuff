import SwiftUI
import WhereCore

/// Retroactively assert which regions a single calendar day belongs to. This
/// overrides any prior manual entry for that day and unions with whatever GPS
/// recorded (see `WhereController.addManualDay`).
struct ManualDayEntryView: View {
    @Environment(WhereModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var selectedRegions: Set<Region> = []
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Day",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date,
                )
            } footer: {
                Text("Time travel: tell Where where you really were.")
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
                Text("Saving replaces any manual regions you previously set for this day.")
            }
        }
        .navigationTitle("Log a Day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(selectedRegions.isEmpty || isSaving)
            }
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
            await model.setManualDay(date: date, regions: selectedRegions)
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
