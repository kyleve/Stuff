import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Admitted historical homes and temporary bases, separate from region-level travel planning.
struct RecordingPlaceView: View {
    @State private var model: RecordingPlaceModel
    @Environment(\.scenePhase) private var scenePhase

    init(session: WhereSession) {
        _model = State(initialValue: .init(services: session.services, now: session.now))
    }

    init(model: RecordingPlaceModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Button(String(localized: .recordingPlaceAdd)) { model.start() }
                    .disabled(model.state.history == nil)
                    .accessibilityIdentifier("where_recording_place_add")
            } footer: { Text(String(localized: .recordingPlaceDetail)) }
            if let history = model.state.history {
                if history.entries.isEmpty, history.unknownControls.isEmpty {
                    Section { Text(String(localized: .recordingPlaceEmpty)) }
                }
                ForEach(history.entries, id: \.placeID) { entry in
                    RecordingPlaceHistorySection(model: model, entry: entry)
                }
                RecordingPlaceUnknownControls(records: history.unknownControls)
            }
            switch model.state {
                case .idle:
                    Section { ProgressView(String(localized: .recordingPlaceLoading)) }
                case let .loading(previous) where previous.history == nil:
                    Section { ProgressView(String(localized: .recordingPlaceLoading)) }
                case .loaded, .loading, .retired: EmptyView()
                case let .failed(error, _):
                    Section {
                        Text(WhereFormat.recordingPlaceFailure(error))
                        Button(String(localized: .commonRetry)) { Task { await model.refresh() } }
                    }
            }
        }
        .navigationTitle(String(localized: .recordingPlaceTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) { if scenePhase == .active { await model.run() } }
        .onDisappear { model.pause() }
        .sheet(item: $model.editor) { RecordingPlaceEditor(model: $0) }
        .alert(
            String(localized: .recordingPlaceErrorTitle),
            isPresented: $model.isShowingError,
            presenting: model.actionError,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { error in Text(WhereFormat.recordingPlaceFailure(error)) }
    }
}

private struct RecordingPlaceHistorySection: View {
    let model: RecordingPlaceModel
    let entry: RecordingPlaceHistory.Entry
    var body: some View {
        Section {
            ForEach(entry.segments, id: \.period) { segment in
                VStack(alignment: .leading) {
                    Text(WhereFormat.recordingPlaceResolution(segment.resolution)).font(.headline)
                    Text(WhereFormat.recordingInterval(segment.period)).font(.caption)
                }
                .accessibilityElement(children: .combine)
                if model.isCurrent(segment) {
                    Button(String(localized: .recordingPlaceChangeNow)) {
                        model.current(.change, placeID: entry.placeID, segment: segment)
                    }
                    .accessibilityLabel(WhereFormat.recordingPlaceActionLabel(
                        String(localized: .recordingPlaceChangeNow),
                        segment: segment,
                    ))
                    .accessibilityIdentifier("where_recording_place_change_now")
                    Button(String(localized: .recordingPlaceEndNow)) {
                        model.current(.end, placeID: entry.placeID, segment: segment)
                    }
                    .accessibilityLabel(WhereFormat.recordingPlaceActionLabel(
                        String(localized: .recordingPlaceEndNow),
                        segment: segment,
                    ))
                    .accessibilityIdentifier("where_recording_place_end_now")
                }
                Button(String(localized: .recordingPlaceEdit)) { model.edit(
                    placeID: entry.placeID,
                    segment: segment,
                ) }
                .accessibilityLabel(WhereFormat.recordingPlaceActionLabel(
                    String(localized: .recordingPlaceEdit),
                    segment: segment,
                ))
                .accessibilityIdentifier("where_recording_place_edit")
                if segment.resolution != .absent {
                    Button(String(localized: .recordingPlaceRemove)) { model.remove(
                        placeID: entry.placeID,
                        segment: segment,
                    ) }
                    .accessibilityLabel(WhereFormat.recordingPlaceActionLabel(
                        String(localized: .recordingPlaceRemove),
                        segment: segment,
                    ))
                    .accessibilityIdentifier("where_recording_place_remove")
                }
            }
            DisclosureGroup(String(localized: .recordingPlaceDecisions)) {
                ForEach(entry.decisions, id: \.id) { decision in
                    VStack(alignment: .leading) {
                        Text(WhereFormat.recordingPlaceAction(decision.action))
                        ForEach(decision.periods, id: \.self) { interval in
                            Text(WhereFormat.recordingInterval(interval)).font(.caption)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(String(localized: .recordingPlaceDecisionsDetail)).foregroundStyle(.secondary)
            }
        } header: { Text(String(localized: .recordingPlaceHistory)) }
    }
}

extension RecordingPlaceView: SettingsSection {
    static var destination: SettingsDestination {
        .recordingPlaces
    }

    enum Item: SettingsItem {
        case places
        var title: String {
            String(localized: .recordingPlaceTitle)
        }

        var keywords: [String] {
            String(localized: .recordingPlaceSearchKeywords).components(separatedBy: ", ")
        }
    }
}

#if DEBUG
    extension RecordingPlaceView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingPlacePreviewFixture.HistoryScenario.allCases {
                let fixture = RecordingPlacePreviewFixture(history: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .history ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) {
                    RecordingPlacePreview(fixture: fixture)
                }
            }
        }
    }

    #Preview { RecordingPlaceView.snapshotPreviews }
    extension RecordingPlaceView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingPlaceView.self,
            title: "Place history",
            navigationContainer: .none,
            routes: [.modal(to: RecordingPlaceEditor.flyoverID)],
        )
    }
#endif
