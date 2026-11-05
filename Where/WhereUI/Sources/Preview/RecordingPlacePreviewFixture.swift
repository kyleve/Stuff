#if DEBUG
    import Foundation
    import Observation
    import SwiftUI
    @_spi(Testing) import WhereCore

    /// Real admitted place history and reviewed proposals over a fresh store for each capture.
    @MainActor
    @Observable
    final class RecordingPlacePreviewFixture {
        enum EditorScenario: String, CaseIterable {
            case draft = "Draft", reviewed = "Reviewed", ended = "EndedHome", base = "TemporaryBase"
            case stale = "ChangedEvidence", failed = "FailedSave", saved = "Saved"
        }

        enum HistoryScenario: String, CaseIterable {
            case empty = "Empty", history = "History", conflict = "ConflictingDefinitions",
                 incomplete = "MissingHistory"
        }

        enum Surface { case editor(EditorScenario), history(HistoryScenario) }
        enum Content { case editor(RecordingPlaceEditorModel), history(RecordingPlaceModel) }
        enum FixtureError: Error { case interruptedReceipt }
        private let surface: Surface
        private(set) var content: Content?
        init(editor: EditorScenario) {
            surface = .editor(editor)
        }

        init(history: HistoryScenario) {
            surface = .history(history)
        }

        func prepare() async {
            do {
                let start = try Date("2026-07-01T14:00:00Z", strategy: .iso8601)
                let change = try Date("2026-07-16T14:00:00Z", strategy: .iso8601)
                let placeID = RecordingPlace
                    .ID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!)
                let author =
                    RecordingDeviceID(
                        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    )
                let decision = try RecordingPlaceDecision(
                    id: .init(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!),
                    author: author,
                    placeID: placeID,
                    validity: [.init(start: start, end: nil)],
                    action: .set(
                        kind: .regularHome,
                        coordinate: .init(latitude: 40.71, longitude: -74),
                    ),
                    predecessors: [],
                    version: RecordingEvidencePolicy.version,
                )
                let store = try SwiftDataStore.inMemory()
                let services = PreviewSupport.recordingReviewServices(store: store)
                try await store.perform { try await store.raiseRequiredDataMajor(1) }
                func append(_ value: RecordingPlaceDecision) async throws {
                    let record = try RecordingControlCodec.encode(
                        .place(value),
                        generationID: .initial,
                    )
                    try await store.perform { try await store.addVersionedHistoryRecord(record) }
                }
                switch surface {
                    case .history(.empty), .editor(.draft), .editor(.base): break
                    case .history(.history), .history(.conflict), .history(.incomplete),
                         .editor(.reviewed), .editor(.ended), .editor(.stale), .editor(.failed),
                         .editor(.saved):
                        try await append(decision)
                }
                switch surface {
                    case let .history(scenario):
                        if scenario != .empty {
                            let predecessors: Set<RecordingPlaceDecision.ID> = switch scenario {
                                case .empty, .conflict: []
                                case .history: [decision.id]
                                case .incomplete: [
                                        .init(
                                            rawValue: UUID(
                                                uuidString: "00000000-0000-0000-0000-000000000199",
                                            )!,
                                        ),
                                    ]
                            }
                            try await append(.init(
                                id: .init(
                                    rawValue: UUID(
                                        uuidString: "00000000-0000-0000-0000-000000000102",
                                    )!,
                                ),
                                author: author,
                                placeID: placeID,
                                validity: [.init(
                                    start: change,
                                    end: nil,
                                )],
                                action: .set(
                                    kind: .regularHome,
                                    coordinate: .init(latitude: 40.73, longitude: -73.99),
                                ),
                                predecessors: predecessors,
                                version: RecordingEvidencePolicy.version,
                            ))
                        }
                        let model = RecordingPlaceModel(services: services, now: { change })
                        await model.refresh()
                        content = .history(model)
                    case let .editor(scenario):
                        let editor = try RecordingPlaceEditorModel(
                            services: services,
                            intent: .definition(
                                placeID: placeID,
                                kind: scenario == .base ? .temporaryBase :
                                    .regularHome,
                                coordinate: scenario == .draft ? nil : .init(
                                    latitude: 40.73,
                                    longitude: -73.99,
                                ),
                                validity: .init(
                                    start: change,
                                    end: scenario == .base ? change
                                        .addingTimeInterval(86400 * 4) : nil,
                                ),
                            ),
                        )
                        if scenario ==
                            .ended { editor.bounds.end = change.addingTimeInterval(86400) }
                        if scenario != .draft { await editor.review() }
                        if scenario == .stale {
                            try await append(.init(
                                id: .init(
                                    rawValue: UUID(
                                        uuidString: "00000000-0000-0000-0000-000000000102",
                                    )!,
                                ),
                                author: author,
                                placeID: placeID,
                                validity: [.init(
                                    start: change,
                                    end: nil,
                                )],
                                action: .remove,
                                predecessors: [decision.id],
                                version: RecordingEvidencePolicy.version,
                            ))
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
            } catch { preconditionFailure("Invalid place fixture: \(error)") }
        }
    }

    struct RecordingPlacePreview: View {
        let fixture: RecordingPlacePreviewFixture
        var body: some View {
            switch fixture.content {
                case let .editor(model): RecordingPlaceEditor(model: model).id(model.id)
                case let .history(model): NavigationStack { RecordingPlaceView(model: model) }
                case nil: EmptyView()
            }
        }
    }

    #Preview { RecordingPlaceView.snapshotPreviews }
#endif
