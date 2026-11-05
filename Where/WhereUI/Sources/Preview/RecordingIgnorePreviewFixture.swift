#if DEBUG
    import Foundation
    import Observation
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// Produces real reviewed controls and history over a fresh synthetic store per capture.
    @MainActor
    @Observable
    final class RecordingIgnorePreviewFixture {
        enum EditorScenario: String, CaseIterable {
            case draft = "Draft", reviewed = "Reviewed", resume = "Resume", undo = "ElapsedUndo"
            case stale = "ChangedEvidence", failed = "FailedSave", saved = "Saved"
        }

        enum HistoryScenario: String, CaseIterable {
            case empty = "Empty", history = "History", conflict = "ConflictingChoices", expired = "Expired"
        }

        enum Surface { case editor(EditorScenario), history(HistoryScenario), devices }
        enum Content {
            case editor(RecordingIgnoreEditorModel), history(RecordingIgnoreModel),
                 devices(WhereSession)
        }

        enum FixtureError: Error { case interruptedReceipt }

        private let surface: Surface
        private(set) var content: Content?

        init(editor: EditorScenario) {
            surface = .editor(editor)
        }

        init(history: HistoryScenario) {
            surface = .history(history)
        }

        init() {
            surface = .devices
        }

        func prepare() async {
            do {
                let deviceID =
                    RecordingDeviceID(
                        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    )
                let now = try Date("2026-07-16T14:00:00Z", strategy: .iso8601)
                let start = now.addingTimeInterval(-86400)
                let zone = TimeZone(identifier: "America/New_York")!
                let store = try SwiftDataStore.inMemory()
                let services = PreviewSupport.recordingReviewServices(store: store)
                try await store.perform { try await store.raiseRequiredDataMajor(1) }
                let coordinator = services.recordingControlEdits
                let until = try RecordingIgnoreDecision.Until(
                    day: .init(year: 2026, month: 7, day: 17),
                    timeZone: zone,
                )
                // Equal-start history rows use their operation identity as a stable tiebreaker.
                let decision = try RecordingIgnoreDecision(
                    id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!),
                    author: deviceID,
                    deviceID: deviceID,
                    periods: [.init(start: start, end: until.end)],
                    change: .ignore(until),
                    predecessors: [],
                    version: RecordingEvidencePolicy.version,
                )
                switch surface {
                    case .history(.history), .history(.conflict), .history(.expired),
                         .editor(.resume), .editor(.undo):
                        let record = try RecordingControlCodec.encode(
                            .ignore(decision),
                            generationID: .initial,
                        )
                        try await store
                            .perform { try await store.addVersionedHistoryRecord(record) }
                    case .editor(.draft), .editor(.reviewed), .editor(.stale), .editor(.failed),
                         .editor(.saved), .history(.empty), .devices:
                        break
                }
                switch surface {
                    case .devices:
                        let session = WhereSession(
                            services: services,
                            preferences: PreviewSupport.previewPreferences(),
                            now: { now },
                        )
                        await session.start()
                        content = .devices(session)
                    case let .history(scenario):
                        if scenario == .conflict {
                            let reversal = try RecordingIgnoreDecision(
                                id: .init(
                                    rawValue: UUID(
                                        uuidString: "00000000-0000-0000-0000-000000000102",
                                    )!,
                                ),
                                author: deviceID,
                                deviceID: deviceID,
                                periods: decision.periods,
                                change: .restoreEligibility,
                                predecessors: [],
                                version: RecordingEvidencePolicy.version,
                            )
                            let record = try RecordingControlCodec.encode(
                                .ignore(reversal),
                                generationID: .initial,
                            )
                            try await store
                                .perform { try await store.addVersionedHistoryRecord(record) }
                        }
                        let clock = scenario == .expired ? until.end.addingTimeInterval(86400) : now
                        let model = RecordingIgnoreModel(
                            services: services,
                            deviceID: deviceID,
                            name: "Travel iPhone",
                            now: { clock },
                        )
                        await model.refresh()
                        content = .history(model)
                    case let .editor(scenario):
                        let intent: RecordingIgnoreEditorModel.Intent = switch scenario {
                            case .resume: .resuming(decision, at: now)
                            case .undo: .restoringElapsed(
                                    deviceID: deviceID,
                                    period: decision.periods[0],
                                    before: now,
                                )
                            case .draft, .reviewed, .stale, .failed, .saved: .starting(
                                    deviceID: deviceID,
                                    at: now,
                                    timeZone: zone,
                                )
                        }
                        let editor = try RecordingIgnoreEditorModel(
                            services: services,
                            name: "Travel iPhone",
                            intent: intent,
                        )
                        if case let .until(end) = editor.draft { end.day = until.day }
                        if scenario != .draft { await editor.review() }
                        if scenario == .stale {
                            let fresh = try await coordinator.review(.ignore(
                                deviceID: deviceID,
                                periods: decision.periods,
                                change: .restoreEligibility,
                            ))
                            _ = try await coordinator.apply(fresh)
                            await editor.apply()
                        }
                        if scenario == .failed {
                            editor.controls
                                .setBeforePublicationForTesting {
                                    throw FixtureError.interruptedReceipt
                                }
                            await editor.apply()
                        }
                        if scenario == .saved { await editor.apply() }
                        content = .editor(editor)
                }
            } catch {
                preconditionFailure("Invalid ignore fixture: \(error)")
            }
        }
    }

    struct RecordingIgnorePreview: View {
        let fixture: RecordingIgnorePreviewFixture

        var body: some View {
            switch fixture.content {
                case let .editor(editor): RecordingIgnoreEditor(model: editor).id(editor.id)
                case let .history(model): NavigationStack { RecordingIgnoreView(model: model) }
                case let .devices(session):
                    NavigationStack {
                        DevicesSettingsView(
                            session: session,
                            configurations: PreviewSupport.recordingDeviceConfigurations(),
                        )
                    }
                    .environment(session)
                case nil: EmptyView()
            }
        }
    }

    #Preview { RecordingIgnoreView.snapshotPreviews }
#endif
