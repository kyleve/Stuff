import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Why the user landed on "Fix this day", so the screen can show a short banner
/// explaining the flagged problem. `.none` is the plain browsing entry (the
/// Elsewhere drill-in) — no banner.
enum DayRelabelReason: Hashable {
    case none
    case borderDrift(region: Region, distanceMeters: Double?)
    case travelDay
    case flight(removed: Set<Region>)
}

/// Correct which regions a single day counted for. Unlike `ManualDayView`
/// (which unions with GPS to backfill / edits a hand-logged entry), saving here
/// *overrides* the day — it replaces whatever GPS or a prior entry recorded, so
/// a wrong attribution can be removed. The raw GPS samples are left untouched
/// (see `DayJournal.overrideDay`), so the fix is reversible.
///
/// A map of the day's recorded points sits at the top (so the user can see
/// where the fixes actually were), and an optional `reason` banner explains why
/// the day was flagged.
struct DayRelabelView: View {
    @Environment(\.dismiss) private var dismiss

    let day: DayPresence
    let report: YearReportModel
    let reason: DayRelabelReason

    @State private var regionSelection: RegionSelectionState
    @State private var note = ""
    @State private var saveError = SaveErrorAlertState()
    @State private var pending: PendingWrite?
    @State private var mapPoints: [RecordedMapPoint] = []

    /// Which async write is in flight. Saving captures a one-shot GPS fix (see
    /// `LocationSource.requestCurrentLocation()`) so it can take a moment and
    /// warrants a visible status; resetting just clears the day and is quick.
    fileprivate enum PendingWrite {
        case saving
        case resetting
    }

    init(
        day: DayPresence,
        report: YearReportModel,
        initialRegions: Set<Region>? = nil,
        reason: DayRelabelReason = .none,
    ) {
        self.day = day
        self.report = report
        self.reason = reason
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

        VStack(spacing: 0) {
            if !mapPoints.isEmpty {
                RecordedPointsMap(points: mapPoints)
            }

            DayRelabelForm(
                reason: reason,
                day: day,
                regionSelection: regionSelection,
                note: $note,
                pending: pending,
                reset: reset,
            )
        }
        .navigationTitle(String(localized: .relabelTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if pending == .saving {
                    ProgressView()
                } else {
                    Button(String(localized: .manualSave)) { save() }
                        .disabled(!canSave)
                }
            }
        }
        .alert(
            String(localized: .manualSaveErrorTitle),
            isPresented: $saveError.isPresented,
        ) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            if let saveError = saveError.message {
                Text(saveError)
            }
        }
        .task(id: day.day) { await loadPoints() }
    }

    private func loadPoints() async {
        let byRegion = await report.locations(onDay: day.day)
        guard !Task.isCancelled else { return }
        mapPoints = byRegion.flatMap { region, points in
            points.map {
                RecordedMapPoint(
                    coordinate: $0.coordinate,
                    horizontalAccuracy: $0.horizontalAccuracy,
                    region: region,
                )
            }
        }
    }

    private func save() {
        pending = .saving
        saveError.message = nil
        Task {
            do {
                try await report.overrideDay(
                    date: day.startOfDay(in: report.calendar),
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
                try await report.clearManualDay(date: day.startOfDay(in: report.calendar))
                dismiss()
            } catch {
                // Keep the form up so the user can retry; nothing was cleared.
                saveError.message = error.localizedDescription
                pending = nil
            }
        }
    }
}

private struct DayRelabelForm: View {
    let reason: DayRelabelReason
    let day: DayPresence
    let regionSelection: RegionSelectionState
    @Binding var note: String
    let pending: DayRelabelView.PendingWrite?
    let reset: () -> Void

    var body: some View {
        Form {
            DayRelabelReasonSection(reason: reason)

            Section {
                LabeledContent(
                    String(localized: .relabelTitle),
                    value: day.displayDate.formatted(.dateTime.month(.abbreviated).day().year()),
                )
            }
            DayRelabelRegionsSection(regionSelection: regionSelection)
            ManualDayNoteSection(note: $note, isWriting: pending != nil)
            ManualDaySavingSection(isSaving: pending == .saving)
            if let audit = day.audit {
                ManualEntryAuditSection(audit: audit)
            }
            DayRelabelResetSection(isWriting: pending != nil, reset: reset)
        }
        .animation(.default, value: pending)
    }
}

private struct DayRelabelRegionsSection: View {
    let regionSelection: RegionSelectionState

    var body: some View {
        Section {
            ForEach(regionSelection.items) { item in
                RegionToggleRow(item: item)
            }
        } header: {
            Text(String(localized: .relabelRegionsHeader))
        } footer: {
            Text(String(localized: .relabelRegionsFooter))
        }
    }
}

private struct DayRelabelResetSection: View {
    let isWriting: Bool
    let reset: () -> Void

    var body: some View {
        Section {
            Button(String(localized: .relabelReset), role: .destructive) { reset() }
                .disabled(isWriting)
        } footer: {
            Text(String(localized: .relabelResetFooter))
        }
    }
}

#if DEBUG
    extension DayRelabelView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                ],
            ) {
                NavigationStack {
                    DayRelabelView(
                        day: DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.other],
                        ),
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
            whereSnapshot(name: "WithAudit", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    DayRelabelView(
                        day: DayPresence(
                            date: PreviewSupport.referenceNow,
                            in: .current,
                            regions: [.california],
                            isAuthoritative: true,
                            audit: ManualEntryAudit(
                                recordedAt: PreviewSupport.referenceNow,
                                note: "Corrected after reviewing my boarding pass.",
                                location: CapturedLocation(
                                    coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                                    horizontalAccuracy: 12,
                                    timestamp: PreviewSupport.referenceNow,
                                ),
                            ),
                        ),
                        report: PreviewSupport.loadedYearReportModel(),
                    )
                }
            }
        }
    }

    #Preview {
        DayRelabelView.snapshotPreviews
    }
#endif

#if DEBUG
    extension DayRelabelView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            DayRelabelView.self,
            title: "Relabel Day",
        )
    }
#endif
