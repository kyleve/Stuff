import RegionKit
import SwiftUI
import WhereCore

/// Edit an existing logged day: adjust the regions it counts for and the note,
/// *preserving* whether it was an additive backfill (unions with GPS) or an
/// authoritative override (replaces GPS). Presented as a sheet from the
/// logged-days list, with explicit Cancel / Save. Unlike `DayRelabelView` (which
/// always overrides, for correcting a GPS-attributed day), this keeps the
/// entry's kind so managing a hand-logged day doesn't silently promote it.
struct LoggedDayEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let day: DayPresence
    let report: YearReportModel

    @State private var regionSelection: RegionSelectionState
    @State private var note: String
    @State private var saveError = SaveErrorAlertState()
    @State private var isSaving = false

    init(day: DayPresence, report: YearReportModel) {
        self.day = day
        self.report = report
        _regionSelection = State(initialValue: RegionSelectionState(selectedRegions: day.regions))
        _note = State(initialValue: day.audit?.note ?? "")
    }

    /// The note as originally stored (blank when none), so a note-only edit
    /// still enables Save.
    private var originalNote: String {
        day.audit?.note ?? ""
    }

    private var hasChanges: Bool {
        regionSelection.selectedRegions != day.regions
            || note.trimmingCharacters(in: .whitespacesAndNewlines)
            != originalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !regionSelection.selectedRegions.isEmpty && !isSaving && hasChanges
    }

    var body: some View {
        @Bindable var saveError = saveError

        Form {
            Section {
                LabeledContent(Strings.loggedDaysEditDate, value: dateText)
            }

            Section {
                ForEach(regionSelection.items) { item in
                    RegionToggleRow(item: item)
                }
            } header: {
                Text(Strings.relabelRegionsHeader)
            } footer: {
                Text(Strings.relabelRegionsFooter)
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

            if isSaving {
                Section {
                    SavingStatusRow(text: Strings.manualSavingStatus)
                }
            }

            if let audit = day.audit {
                ManualEntryAuditSection(audit: audit)
            }
        }
        .animation(.default, value: isSaving)
        .navigationTitle(Strings.loggedDaysEditTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Strings.commonCancel) { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(Strings.manualSave) { save() }
                        .disabled(!canSave)
                }
            }
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
    }

    private var dateText: String {
        day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Save preserving the entry's kind: an authoritative override stays
    /// authoritative (replaces GPS); an additive backfill stays additive (unions
    /// with GPS). Keeps the form up on failure so the user can retry.
    private func save() {
        isSaving = true
        saveError.message = nil
        Task {
            do {
                if day.isAuthoritative {
                    try await report.overrideDay(
                        date: day.date,
                        regions: regionSelection.selectedRegions,
                        note: note,
                    )
                } else {
                    try await report.setManualDay(
                        date: day.date,
                        regions: regionSelection.selectedRegions,
                        note: note,
                    )
                }
                dismiss()
            } catch {
                saveError.message = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#if DEBUG
    #Preview("Additive backfill") {
        NavigationStack {
            LoggedDayEditorView(
                day: DayPresence(date: .now, regions: [.california]),
                report: PreviewSupport.loadedYearReportModel(),
            )
        }
    }

    #Preview("Authoritative with audit") {
        NavigationStack {
            LoggedDayEditorView(
                day: DayPresence(
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
                ),
                report: PreviewSupport.loadedYearReportModel(),
            )
        }
    }
#endif
