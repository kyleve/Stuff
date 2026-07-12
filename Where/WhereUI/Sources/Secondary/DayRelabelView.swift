import RegionKit
import SwiftUI
import WhereCore

/// Correct which regions a single day counted for. Unlike `ManualDayEntryView`
/// (which unions with GPS to backfill), saving here *overrides* the day — it
/// replaces whatever GPS or a prior entry recorded, so a wrong attribution can
/// be removed. The raw GPS samples are left untouched (see
/// `DayJournal.overrideDay`), so the fix is reversible.
struct DayRelabelView: View {
    @Environment(\.dismiss) private var dismiss

    let day: DayPresence
    let report: YearReportModel

    @State private var regionSelection: RegionSelectionState
    @State private var note = ""
    @State private var saveError = SaveErrorAlertState()
    @State private var pending: PendingWrite?

    /// Which async write is in flight. Saving captures a one-shot GPS fix (see
    /// `LocationSource.requestCurrentLocation()`) so it can take a moment and
    /// warrants a visible status; resetting just clears the day and is quick.
    private enum PendingWrite {
        case saving
        case resetting
    }

    init(day: DayPresence, report: YearReportModel, initialRegions: Set<Region>? = nil) {
        self.day = day
        self.report = report
        _regionSelection = State(
            initialValue: RegionSelectionState(selectedRegions: initialRegions ?? day.regions),
        )
    }

    private var canSave: Bool {
        !regionSelection.selectedRegions.isEmpty && pending == nil
            && regionSelection.selectedRegions != day.regions
    }

    var body: some View {
        @Bindable var saveError = saveError

        Form {
            Section {
                LabeledContent(String(localized: .relabelTitle), value: dateText)
            }

            Section {
                ForEach(regionSelection.items) { item in
                    RegionToggleRow(item: item)
                }
            } header: {
                Text(.relabelRegionsHeader)
            } footer: {
                Text(.relabelRegionsFooter)
            }

            Section {
                TextField(
                    String(localized: .manualNotePlaceholder),
                    text: $note,
                    axis: .vertical,
                )
                .lineLimit(3, reservesSpace: true)
                .disabled(pending != nil)
            } header: {
                Text(.manualNoteHeader)
            } footer: {
                Text(.manualNoteFooter)
            }

            if pending == .saving {
                Section {
                    SavingStatusRow(text: String(localized: .manualSavingStatus))
                }
            }

            auditSection

            Section {
                Button(.relabelReset, role: .destructive) { reset() }
                    .disabled(pending != nil)
            } footer: {
                Text(.relabelResetFooter)
            }
        }
        .animation(.default, value: pending)
        .navigationTitle(String(localized: .relabelTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if pending == .saving {
                    ProgressView()
                } else {
                    Button(.manualSave) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .alert(
            String(localized: .manualSaveErrorTitle),
            isPresented: $saveError.isPresented,
        ) {
            Button(.commonOk, role: .cancel) {}
        } message: {
            if let saveError = saveError.message {
                Text(saveError)
            }
        }
    }

    /// Read-only record of the last manual entry for this day (when it came from
    /// an override): when it was made, its note, and where the device was at the
    /// time — the audit trail retained for residency reviews.
    @ViewBuilder
    private var auditSection: some View {
        if let audit = day.audit {
            Section {
                LabeledContent(
                    String(localized: .auditRecordedAt),
                    value: recordedAtText(audit.recordedAt),
                )
                if let note = audit.note {
                    LabeledContent(String(localized: .auditNote), value: note)
                }
                LabeledContent(
                    String(localized: .auditLocation),
                    value: locationText(audit.location),
                )
            } header: {
                Text(.auditHeader)
            }
        }
    }

    private var dateText: String {
        day.date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func recordedAtText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    private func locationText(_ location: CapturedLocation?) -> String {
        guard let location else { return String(localized: .auditLocationUnavailable) }
        return WhereFormat.coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
        )
    }

    private func save() {
        pending = .saving
        saveError.message = nil
        Task {
            do {
                try await report.overrideDay(
                    date: day.date,
                    regions: regionSelection.selectedRegions,
                    note: note,
                )
                dismiss()
            } catch {
                // Keep the form up so the user can retry; the save didn't land.
                saveError.message = error.localizedDescription
                pending = nil
            }
        }
    }

    private func reset() {
        pending = .resetting
        saveError.message = nil
        Task {
            do {
                try await report.clearManualDay(date: day.date)
                dismiss()
            } catch {
                // Keep the form up so the user can retry; nothing was cleared.
                saveError.message = error.localizedDescription
                pending = nil
            }
        }
    }
}

#if DEBUG
    #Preview("Other region") {
        NavigationStack {
            DayRelabelView(
                day: DayPresence(date: .now, regions: [.other]),
                report: PreviewSupport.loadedYearReportModel(),
            )
        }
    }

    #Preview("With audit record") {
        NavigationStack {
            DayRelabelView(
                day: DayPresence(
                    date: .now,
                    regions: [.california],
                    isAuthoritative: true,
                    audit: ManualEntryAudit(
                        recordedAt: .now,
                        note: "Corrected after reviewing my boarding pass.",
                        location: CapturedLocation(
                            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                            horizontalAccuracy: 12,
                            timestamp: .now,
                        ),
                    ),
                ),
                report: PreviewSupport.loadedYearReportModel(),
            )
        }
    }
#endif
