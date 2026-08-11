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
    @Environment(\.stylesheet) private var stylesheet

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
    private enum PendingWrite {
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
            form
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

    private var form: some View {
        Form {
            reasonBanner

            Section {
                LabeledContent(String(localized: .relabelTitle), value: dateText)
            }

            Section {
                ForEach(regionSelection.items) { item in
                    RegionToggleRow(item: item)
                }
            } header: {
                Text(String(localized: .relabelRegionsHeader))
            } footer: {
                Text(String(localized: .relabelRegionsFooter))
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
                Text(String(localized: .manualNoteHeader))
            } footer: {
                Text(String(localized: .manualNoteFooter))
            }

            if pending == .saving {
                Section {
                    SavingStatusRow(text: String(localized: .manualSavingStatus))
                }
            }

            auditSection

            Section {
                Button(String(localized: .relabelReset), role: .destructive) { reset() }
                    .disabled(pending != nil)
            } footer: {
                Text(String(localized: .relabelResetFooter))
            }
        }
        .animation(stylesheet.motion.settle, value: pending)
    }

    /// A short callout explaining why the day was flagged, driven by the
    /// classifier that routed here. `.none` (plain Elsewhere browsing) shows
    /// nothing.
    @ViewBuilder
    private var reasonBanner: some View {
        switch reason {
            case .none:
                EmptyView()
            case let .borderDrift(region, meters):
                banner(
                    icon: .locationCircle,
                    text: WhereFormat.relabelReasonBorderDrift(
                        region: region.localizedName,
                        distance: meters.map(Self.formattedDistance),
                    ),
                )
            case .travelDay:
                banner(
                    icon: .arrowTriangleSwap,
                    text: String(localized: .relabelReasonTravelDay),
                )
            case let .flight(removed):
                banner(icon: .airplane, text: WhereFormat.relabelReasonFlight(removed: removed))
        }
    }

    private func banner(icon: SFSymbol, text: String) -> some View {
        Section {
            Label {
                Text(text)
            } icon: {
                Image(systemSymbol: icon)
                    .foregroundStyle(.tint)
            }
            .font(.subheadline)
        } header: {
            Text(String(localized: .relabelReasonTitle))
        }
    }

    private static func formattedDistance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
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

    /// Read-only record of the last manual entry for this day (when it came from
    /// an override): when it was made, its note, and where the device was at the
    /// time — the audit trail retained for residency reviews.
    @ViewBuilder
    private var auditSection: some View {
        if let audit = day.audit {
            ManualEntryAuditSection(audit: audit)
        }
    }

    private var dateText: String {
        day.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
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

#if DEBUG
    extension DayRelabelView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
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
