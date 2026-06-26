import StuffCore
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

    @State private var regionSelection: RegionSelectionState
    @State private var saveError = SaveErrorAlertState()
    @State private var isSaving = false

    init(day: DayPresence) {
        self.day = day
        _regionSelection = State(initialValue: RegionSelectionState(selectedRegions: day.regions))
    }

    private var canSave: Bool {
        !regionSelection.selectedRegions.isEmpty && !isSaving
            && regionSelection.selectedRegions != day.regions
    }

    var body: some View {
        @Bindable var saveError = saveError

        Form {
            Section {
                LabeledContent(LocalizedStrings.Relabel.title.localized(), value: dateText)
            }

            Section {
                ForEach(regionSelection.items) { item in
                    RegionToggleRow(item: item)
                }
            } header: {
                Text.localized(LocalizedStrings.Relabel.regionsHeader)
            } footer: {
                Text.localized(LocalizedStrings.Relabel.regionsFooter)
            }

            Section {
                Button(LocalizedStrings.Relabel.reset.localized(), role: .destructive) { reset() }
                    .disabled(isSaving)
            } footer: {
                Text.localized(LocalizedStrings.Relabel.resetFooter)
            }
        }
        .navigationTitle(LocalizedStrings.Relabel.title.localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(LocalizedStrings.ManualEntry.save.localized()) { save() }
                    .disabled(!canSave)
            }
        }
        .alert(
            LocalizedStrings.ManualEntry.saveErrorTitle.localized(),
            isPresented: $saveError.isPresented,
        ) {
            Button(LocalizedStrings.Common.ok.localized(), role: .cancel) {}
        } message: {
            if let saveError = saveError.message {
                Text(saveError)
            }
        }
    }

    private var dateText: String {
        day.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func save() {
        isSaving = true
        saveError.message = nil
        Task {
            do {
                try await session.overrideDay(
                    date: day.date,
                    regions: regionSelection.selectedRegions,
                )
                dismiss()
            } catch {
                // Keep the form up so the user can retry; the save didn't land.
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func reset() {
        isSaving = true
        saveError.message = nil
        Task {
            do {
                try await session.clearManualDay(date: day.date)
                dismiss()
            } catch {
                // Keep the form up so the user can retry; nothing was cleared.
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#if DEBUG
    #Preview("Other region") {
        NavigationStack {
            DayRelabelView(day: DayPresence(date: .now, regions: [.other]))
                .environment(PreviewSupport.loadedSession())
        }
    }
#endif
