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
    @State private var deleteError = SaveErrorAlertState()
    @State private var showDeleteConfirmation = false
    @State private var pending: PendingWrite?

    /// Which async write is in flight, so the form can disable inputs and show
    /// progress without two overlapping `Bool`s.
    private enum PendingWrite {
        case saving
        case deleting
    }

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
        !regionSelection.selectedRegions.isEmpty && pending == nil && hasChanges
    }

    var body: some View {
        @Bindable var saveError = saveError
        @Bindable var deleteError = deleteError

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
                .disabled(pending != nil)
            } header: {
                Text(Strings.manualNoteHeader)
            } footer: {
                Text(Strings.manualNoteFooter)
            }

            // This editor only ever edits an already-stored entry, so deleting
            // it (restoring the day's GPS attribution) always applies.
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

            if pending == .saving {
                Section {
                    SavingStatusRow(text: Strings.manualSavingStatus)
                }
            }

            if let audit = day.audit {
                ManualEntryAuditSection(audit: audit)
            }
        }
        .animation(.default, value: pending)
        .navigationTitle(Strings.loggedDaysEditTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(Strings.commonCancel) { dismiss() }
                    .disabled(pending != nil)
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

    private var dateText: String {
        day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Save preserving the entry's kind: an authoritative override stays
    /// authoritative (replaces GPS); an additive backfill stays additive (unions
    /// with GPS). Keeps the form up on failure so the user can retry.
    private func save() {
        pending = .saving
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
                pending = nil
            }
        }
    }

    /// Delete this manual entry, restoring the day's GPS-detected attribution.
    /// Keeps the form up on failure so the user can retry.
    private func delete() {
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
