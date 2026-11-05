#if DEBUG
    import Foundation
    import Observation
    import RegionKit
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// A moving phone wins over a stationary phone through the real selection pipeline.
    @MainActor
    @Observable
    final class RecordingHistoryPreviewFixture {
        private(set) var model: RecordingHistoryModel?

        func prepare() async {
            guard model == nil else { return }
            do {
                let store = try SwiftDataStore.inMemory()
                let services = PreviewSupport.recordingReviewServices(store: store)
                let tracks = RecordingChoicePreview.comparison(.conflict).tracks
                let start = tracks[0].observations[0].sample.timestamp
                try await store.perform {
                    try await store.raiseRequiredDataMajor(1)
                    for (offset, track) in tracks.enumerated() {
                        try await store.addRecordingDeviceProfile(.init(
                            id: track.id,
                            systemName: offset == 0 ? "Phone One" : "Phone Two",
                            kind: .phone,
                            registeredAt: start,
                            registrationGenerationID: .initial,
                        ))
                        for index in 0 ... 2 {
                            let timestamp = start.addingTimeInterval(Double(index) * 600)
                            try await store.add(sample: LocationSample(
                                id: UUID(),
                                timestamp: timestamp,
                                coordinate: offset == 0
                                    ? Coordinate(
                                        latitude: 37.78,
                                        longitude: -122.42 + Double(index) * 0.02,
                                    )
                                    : Coordinate(latitude: 40.71, longitude: -74),
                                horizontalAccuracy: 10,
                                source: .gpsSignificantChange,
                                recordingDeviceID: track.id,
                                recordingDay: .resolved(.init(
                                    observedAt: timestamp,
                                    timeZone: .gmt,
                                )),
                            ))
                        }
                    }
                }
                model = RecordingHistoryModel(
                    services: services,
                    now: { start.addingTimeInterval(86400) },
                )
            } catch {
                preconditionFailure("Invalid recording history fixture: \(error)")
            }
        }
    }

    struct RecordingHistoryPreview: View {
        let fixture: RecordingHistoryPreviewFixture

        var body: some View {
            if let model = fixture.model {
                NavigationStack { RecordingHistoryView(model: model) }
            } else {
                ProgressView()
            }
        }
    }

    #Preview { RecordingHistoryView.snapshotPreviews }
#endif
