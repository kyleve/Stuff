import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// Detail screen for a suspected flight day: a map of the day's recorded points
/// (with the fly-over `.other` pins tinted apart from the grounded endpoints)
/// above an explanation and a one-tap fix. "Apply" writes an authoritative
/// `overrideDay` keeping only the endpoints; "Not what you expected?" hands off
/// to the regular `DayRelabelView` (seeded from the day's *actual* regions, so a
/// wrong guess isn't baked in); "These are all correct" dismisses the issue.
struct FlightDayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stylesheet) private var stylesheet

    let issue: any DataIssue
    let report: YearReportModel
    let resolve: ResolveModel

    @State private var mapPoints: [RecordedMapPoint] = []
    @State private var applying = false
    @State private var saveError = SaveErrorAlertState()

    var body: some View {
        @Bindable var saveError = saveError

        Group {
            if let payload = flightPayload {
                content(payload)
                    .task(id: payload.day.day) { await loadPoints(for: payload.day.day) }
            } else {
                ContentUnavailableView(
                    String(localized: .commonLoadErrorTitle),
                    systemImage: "exclamationmark.triangle",
                )
            }
        }
        .navigationTitle(String(localized: .resolutionFlightDetailTitle))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            String(localized: .manualSaveErrorTitle),
            isPresented: $saveError.isPresented,
        ) {
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: {
            if let message = saveError.message {
                Text(message)
            }
        }
    }

    private func content(_ payload: FlightPayload) -> some View {
        VStack(spacing: 0) {
            if !mapPoints.isEmpty {
                RecordedPointsMap(points: mapPoints)
            }
            form(payload)
        }
        .animation(.default, value: applying)
    }

    private func form(_ payload: FlightPayload) -> some View {
        Form {
            Section {
                Text(WhereFormat.resolutionFlightDetailExplanation(
                    peakSpeedKMH: payload.peakSpeedKMH,
                    removed: payload.removed,
                ))
            } header: {
                Text(dateText(payload.day))
            }

            if applying {
                Section {
                    SavingStatusRow(text: String(localized: .manualSavingStatus))
                }
            }

            Section {
                Button {
                    apply(payload)
                } label: {
                    Text(WhereFormat.resolutionFlightApply(regions: payload.keep))
                }
                .disabled(applying)
            }

            Section {
                NavigationLink {
                    DayRelabelView(
                        day: payload.day,
                        report: report,
                        reason: .flight(removed: payload.removed),
                    )
                } label: {
                    Text(String(localized: .resolutionFlightManualFix))
                }
                .disabled(applying)
            } footer: {
                Text(String(localized: .resolutionFlightManualFixFooter))
            }

            Section {
                Button(String(localized: .resolutionFlightBothRight)) {
                    Task {
                        await resolve.dismiss(issue)
                        dismiss()
                    }
                }
                .disabled(applying)
            }
        }
    }

    private func dateText(_ day: DayPresence) -> String {
        day.displayDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func loadPoints(for day: CalendarDay) async {
        let byRegion = await report.locations(onDay: day)
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

    private func apply(_ payload: FlightPayload) {
        applying = true
        saveError.message = nil
        Task {
            do {
                try await report.overrideDay(
                    date: payload.day.startOfDay(in: report.calendar),
                    regions: payload.keep,
                )
                dismiss()
            } catch {
                // Keep the screen up so the user can retry; the fix didn't land.
                saveError.message = error.localizedDescription
                applying = false
            }
        }
    }

    private var flightPayload: FlightPayload? {
        if case let .correctFlightDay(day, keep, removed, peak) = issue.resolution {
            return FlightPayload(day: day, keep: keep, removed: removed, peakSpeedKMH: peak)
        }
        return nil
    }

    /// The `.correctFlightDay` resolution unpacked for the view (a named struct
    /// rather than a tuple, since it escapes into `content`/`form`).
    private struct FlightPayload {
        let day: DayPresence
        let keep: Set<Region>
        let removed: Set<Region>
        let peakSpeedKMH: Double
    }
}

#if DEBUG
    extension FlightDayDetailView: SnapshotProviding {
        /// The flight-day fixture pins its day to `referenceNow` (a bespoke
        /// `.now` would churn the reference daily). The preview store seeds no
        /// raw samples, so the recorded-points map stays out of the tree and the
        /// capture is deterministic.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .screenDefaults) {
                NavigationStack {
                    FlightDayDetailView(
                        issue: FlightDayIssue(
                            day: DayPresence(
                                date: PreviewSupport.referenceNow,
                                in: .current,
                                regions: [.newYork, .other, .california],
                            ),
                            keepRegions: [.newYork, .california],
                            removedRegions: [.other],
                            peakSpeedKMH: 880,
                        ),
                        report: PreviewSupport.loadedYearReportModel(),
                        resolve: PreviewSupport.resolveModel(),
                    )
                }
            }
        }
    }

    #Preview {
        FlightDayDetailView.snapshotPreviews
    }
#endif
