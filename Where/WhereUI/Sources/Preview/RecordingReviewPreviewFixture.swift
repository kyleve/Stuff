#if DEBUG
    import Foundation
    import Observation
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// Runs the real inspection and guarded-save paths against a fresh synthetic store before
    /// each capture. Hosted interaction tests separately exercise compatibility-admitted services.
    @MainActor
    @Observable
    final class RecordingReviewPreviewFixture {
        enum Scenario: String, CaseIterable {
            case browsing = "Browsing"
            case selected = "Selected"
            case stale = "ChangedEvidence"
            case calendar = "CalendarRequired"
            case failed = "FailedReview"
        }

        struct State {
            let store: SwiftDataStore
            let services: WhereServices
            let choice: RecordingChoiceModel
        }

        private let scenario: Scenario
        private(set) var preparedState: State?
        var state: State {
            guard let preparedState else {
                preconditionFailure("Prepare the recording fixture before reading its state")
            }
            return preparedState
        }

        private(set) var scopeEditor: RecordingScopeEditorModel?
        private(set) var flow: RecordingReviewFlowModel?
        private(set) var report: YearReportModel?

        init(scenario: Scenario) {
            self.scenario = scenario
        }

        func prepare() async {
            let prepared = Self.makeState()
            do {
                let comparison = RecordingChoicePreview.comparison(.selected)
                try await prepared.store.perform {
                    try await prepared.store.raiseRequiredDataMajor(1)
                    for track in comparison.tracks {
                        try await prepared.store.addRecordingDeviceProfile(.init(
                            id: track.id,
                            systemName: track.name,
                            kind: .phone,
                            registeredAt: PreviewSupport.referenceNow,
                            registrationGenerationID: .initial,
                        ))
                        for observation in track.observations {
                            try await prepared.store.add(sample: observation.sample)
                        }
                    }
                }
                await prepared.choice.load()
                let deviceID = comparison.tracks[0].id
                switch scenario {
                    case .browsing: break
                    case .selected: await prepared.choice.choose(.select(deviceID))
                    case .calendar:
                        await prepared.choice.review(.init(scope: .recordingDay(
                            deviceID: deviceID,
                            day: CalendarDay(year: 2026, month: 7, day: 15),
                        ), action: .select(deviceID)))
                    case .failed:
                        await prepared.choice.review(.init(scope: .periods([]), action: .automatic))
                    case .stale:
                        await prepared.choice.choose(.select(deviceID))
                        let first = comparison.tracks[0].observations[0].sample
                        let late = LocationSample(
                            id: UUID(),
                            timestamp: first.timestamp.addingTimeInterval(1),
                            coordinate: first.coordinate,
                            horizontalAccuracy: first.horizontalAccuracy,
                            source: first.source,
                            recordingDeviceID: deviceID,
                            recordingDay: first.recordingDay,
                        )
                        try await prepared.store
                            .perform { try await prepared.store.add(sample: late) }
                        await prepared.choice.apply()
                }
                preparedState = prepared
            } catch {
                preconditionFailure("Invalid recording review fixture: \(error)")
            }
        }

        func prepareScope(kind: RecordingScopeEditorModel.Kind) async {
            await prepare()
            guard let presentation = state.choice.presentation else {
                preconditionFailure("Scope fixture needs a prepared inspection")
            }
            let editor = RecordingScopeEditorModel(
                presentation: presentation,
                originalPeriods: state.choice.originalPeriods,
            )
            editor.kind = kind
            scopeEditor = editor
        }

        func prepareFlow(skipped: Bool) async {
            await prepare()
            do {
                let scan = try await state.services.resolution.historicalScan(
                    driftThresholdMeters: 1000,
                    force: true,
                )
                let references = try scan.recording.issues
                    .flatMap { try Array(scan.references(for: $0)) }
                let prepared = try RecordingReviewFlowModel(
                    services: state.services,
                    references: references,
                )
                await prepared.refresh()
                if skipped {
                    while prepared.page != nil {
                        prepared.skipCurrent()
                    }
                } else {
                    await prepared.page?.choice.loadIfNeeded()
                }
                flow = prepared
            } catch {
                preconditionFailure("Invalid recording queue fixture: \(error)")
            }
        }

        func prepareResolution() async {
            await prepare()
            let prepared = YearReportModel(
                services: state.services,
                selectedYear: 2027,
                preferences: PreviewSupport.previewPreferences(),
                now: { PreviewSupport.referenceNow },
            )
            await prepared.refreshAll(forceDataIssueCount: true)
            report = prepared
        }

        private static func makeState() -> State {
            let store = try! SwiftDataStore.inMemory()
            let services = PreviewSupport.recordingReviewServices(store: store)
            let start = Date(timeIntervalSince1970: 1_784_102_400)
            let periods = try! [
                RecordingPeriod(start: start, end: start.addingTimeInterval(601)),
                RecordingPeriod(
                    start: start.addingTimeInterval(2400),
                    end: start.addingTimeInterval(3600),
                )
            ]
            return State(
                store: store,
                services: services,
                choice: RecordingChoiceModel(services: services, periods: periods),
            )
        }
    }

    /// Reads the fixture inside a SwiftUI body so asynchronous readiness replaces the initial
    /// placeholder. A SnapshotCase content closure is evaluated before those hooks complete.
    struct RecordingReviewPreview<Content: View>: View {
        let fixture: RecordingReviewPreviewFixture
        @ViewBuilder let content: (RecordingReviewPreviewFixture) -> Content

        var body: some View {
            content(fixture)
        }
    }

    #Preview("Prepared recording fixtures") { RecordingChoiceView.snapshotPreviews }
#endif
