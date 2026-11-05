#if DEBUG
    import Foundation
    import Observation
    import RegionKit
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// Uses the production reader to show resolved presence beside unresolved source/date evidence.
    @MainActor
    @Observable
    final class RecordingReportPreviewFixture {
        enum Scenario: String, CaseIterable {
            case known = "KnownDates"
            case unknown = "UnknownDates"
            case mixed = "MixedDates"
        }

        private(set) var report: YearReportModel?
        private(set) var elsewhere: ElsewhereModel?
        let artwork = RegionOutlinePathCache()
        let scenario: Scenario

        init(scenario: Scenario) {
            self.scenario = scenario
        }

        func prepare() async {
            do {
                let store = try SwiftDataStore.inMemory()
                let services = PreviewSupport.recordingReviewServices(store: store)
                let state: RecordingChoicePreview
                    .State = scenario == .unknown ? .unknownDates : .conflict
                let tracks = RecordingChoicePreview.comparison(state).tracks
                try await store.perform {
                    try await store.raiseRequiredDataMajor(1)
                    for track in tracks {
                        for observation in track.observations {
                            try await store.add(sample: observation.sample)
                        }
                    }
                    let first = tracks[0].observations[0].sample
                    // Independent resolved presence on the same day still counts once.
                    let timestamp = first.timestamp.addingTimeInterval(6 * 3600)
                    try await store.add(sample: LocationSample(
                        id: UUID(),
                        timestamp: timestamp,
                        coordinate: first.coordinate,
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: tracks[0].id,
                        recordingDay: .resolved(.init(observedAt: timestamp, timeZone: .gmt)),
                    ))
                    let elsewhereTime = timestamp.addingTimeInterval(3 * 3600)
                    try await store.add(sample: LocationSample(
                        id: UUID(),
                        timestamp: elsewhereTime,
                        coordinate: ElsewherePreview.vegas,
                        horizontalAccuracy: 10,
                        source: .gpsSignificantChange,
                        recordingDeviceID: tracks[0].id,
                        recordingDay: .resolved(.init(observedAt: elsewhereTime, timeZone: .gmt)),
                    ))
                    if scenario == .mixed {
                        try await store.add(sample: LocationSample(
                            id: UUID(),
                            timestamp: timestamp.addingTimeInterval(86400),
                            coordinate: first.coordinate,
                            horizontalAccuracy: 10,
                            source: .gpsSignificantChange,
                            recordingDeviceID: tracks[0].id,
                            recordingDay: .unresolved,
                        ))
                    }
                }
                let model = YearReportModel(
                    services: services,
                    selectedYear: 2026,
                    preferences: PreviewSupport.previewPreferences(),
                    now: { Date(timeIntervalSince1970: 1_784_275_200) },
                )
                await model.refreshAll(forceDataIssueCount: true)
                let elsewhere = ElsewhereModel(
                    resolver: services.elsewhere,
                    namer: PreviewPlaceNamer(),
                )
                if let input = model.elsewhereInput { await elsewhere.refresh(input) }
                await PreviewSupport.loadCardArtwork(
                    for: Region.inCanonicalOrder(Set(
                        model.locationRegions.map(\.region)
                            + (elsewhere.content(for: 2026)?.regions.map(\.region) ?? []),
                    )),
                    cache: artwork,
                )
                self.elsewhere = elsewhere
                report = model
            } catch {
                preconditionFailure("Invalid incomplete report fixture: \(error)")
            }
        }
    }

    struct RecordingReportPreview<Content: View>: View {
        let fixture: RecordingReportPreviewFixture
        @ViewBuilder let content: (YearReportModel, ElsewhereModel) -> Content

        var body: some View {
            if let report = fixture.report, let elsewhere = fixture.elsewhere {
                content(report, elsewhere)
                    .environment(\.regionOutlinePathCache, fixture.artwork)
            } else {
                ProgressView()
            }
        }
    }

    #Preview { HistoryCompletenessNotice.snapshotPreviews }
#endif
