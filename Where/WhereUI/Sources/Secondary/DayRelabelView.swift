import SwiftUI
import WhereCore

/// Correct which regions a single day counted for. Unlike `ManualDayEntryView`
/// (which unions with GPS to backfill), saving here *overrides* the day — it
/// replaces whatever GPS or a prior entry recorded, so a wrong attribution can
/// be removed. The raw GPS samples are left untouched (see
/// `DayJournal.overrideDay`), so the fix is reversible.
struct DayRelabelView: View {
    @Environment(WhereSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let day: DayPresence

    @State private var selectedRegions: Set<Region>
    @State private var isSaving = false
    @State private var saveError: String?

    init(day: DayPresence) {
        self.day = day
        _selectedRegions = State(initialValue: day.regions)
    }

    private var canSave: Bool {
        !selectedRegions.isEmpty && !isSaving && selectedRegions != day.regions
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(Strings.relabelTitle, value: dateText)
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
                Text(Strings.relabelRegionsHeader)
            } footer: {
                Text(Strings.relabelRegionsFooter)
            }

            Section {
                Button(Strings.relabelReset, role: .destructive) { reset() }
                    .disabled(isSaving)
            } footer: {
                Text(Strings.relabelResetFooter)
            }
        }
        .navigationTitle(Strings.relabelTitle)
        .navigationBarTitleDisplayMode(.inline)
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

    private var dateText: String {
        day.date.formatted(.dateTime.month(.abbreviated).day().year())
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
                try await session.overrideDay(date: day.date, regions: selectedRegions)
                dismiss()
            } catch {
                // Keep the form up so the user can retry; the save didn't land.
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func reset() {
        isSaving = true
        saveError = nil
        Task {
            do {
                try await session.clearManualDay(date: day.date)
                dismiss()
            } catch {
                // Keep the form up so the user can retry; nothing was cleared.
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            DayRelabelView(day: DayPresence(date: .now, regions: [.other]))
                .environment(PreviewSupport.loadedSession())
        }
    }
#endif
