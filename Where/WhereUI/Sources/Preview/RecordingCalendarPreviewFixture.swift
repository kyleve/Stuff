#if DEBUG
    import Foundation
    import Observation
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// Uses real controls and synthetic observations across New York's 2026 offset change.
    @MainActor
    @Observable
    final class RecordingCalendarPreviewFixture {
        enum Scenario: String, CaseIterable {
            case draft = "Draft"
            case reviewed = "OffsetChange"
            case subset = "SeparatePeriods"
            case stale = "ChangedEvidence"
            case conflict = "KnownDates"
        }

        private let scenario: Scenario
        private(set) var editor: RecordingCalendarEditorModel?

        init(scenario: Scenario) {
            self.scenario = scenario
        }

        func prepare() async {
            do {
                let deviceID = RecordingDeviceID(rawValue:
                    UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
                let transition = try Date("2026-11-01T06:00:00Z", strategy: .iso8601)
                let store = try SwiftDataStore.inMemory()
                let services = PreviewSupport.recordingReviewServices(store: store)
                let sample = try LocationSample(
                    id: UUID(),
                    timestamp: transition,
                    coordinate: .init(latitude: 40.71, longitude: -74),
                    horizontalAccuracy: 10,
                    source: .gpsSignificantChange,
                    recordingDeviceID: deviceID,
                    recordingDay: scenario == .conflict ?
                        .resolved(.init(observedAt: transition, timeZone: .gmt)) : .unresolved,
                )
                try await store.perform {
                    try await store.raiseRequiredDataMajor(1)
                    try await store.add(sample: sample)
                }
                var periods = try [RecordingPeriod(
                    start: transition.addingTimeInterval(-3600),
                    end: transition.addingTimeInterval(3600),
                )]
                if scenario == .subset {
                    try periods.append(.init(
                        start: transition.addingTimeInterval(86400),
                        end: transition.addingTimeInterval(90000),
                    ))
                }
                let prepared = RecordingCalendarEditorModel(
                    services: services,
                    periods: periods,
                    devices: [deviceID],
                    names: [deviceID: "Travel iPhone"],
                    selectedDevice: scenario == .draft ? nil : deviceID,
                )
                if scenario == .subset { prepared.periods[1].isIncluded = false }
                if scenario != .draft {
                    prepared.timeZone = TimeZone(identifier: "America/New_York")!
                    await prepared.review()
                }
                if scenario == .stale {
                    let late = LocationSample(
                        id: UUID(),
                        timestamp: transition.addingTimeInterval(1),
                        coordinate: sample.coordinate,
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: deviceID,
                        recordingDay: .unresolved,
                    )
                    try await store.perform { try await store.add(sample: late) }
                    await prepared.apply()
                }
                editor = prepared
            } catch {
                preconditionFailure("Invalid calendar recovery fixture: \(error)")
            }
        }
    }

    struct RecordingCalendarPreview: View {
        let fixture: RecordingCalendarPreviewFixture

        var body: some View {
            if let editor = fixture.editor {
                RecordingCalendarEditor(model: editor).id(editor.id)
            }
        }
    }

    #Preview { RecordingCalendarEditor.snapshotPreviews }
#endif
